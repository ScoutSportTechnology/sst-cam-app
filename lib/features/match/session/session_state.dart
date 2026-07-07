// Live match state — local mirror of what the firmware would push back over
// BLE. The match flow drives this directly from the UI so the wireframe
// interactions are end-to-end clickable without a real device.
//
// Phase model is generalized over `numPeriods`:
//   idle         → before kickoff (pre-game; recording/streaming may be on)
//   period       → a period is in progress; clock counts up to periodLengthSeconds
//   periodBreak  → between periods (or after final period, awaiting end-of-match)
//   ended        → match is over; back-arrow returns to landing

import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ble/ble_providers.dart'
    show
        bleServiceProvider,
        connectionStateProvider,
        matchStateProvider,
        telemetryProvider;
import '../../../core/models/command.dart'
    show MatchControlCommand, BleMatchControlAction;
import '../../../core/models/device.dart' show CameraConnectionState;
import '../../../core/models/match.dart' show MatchState, MatchStatus;
import '../../../core/models/overlay_layout.dart';
import '../../../core/models/session_snapshot.dart'
    show LastSessionSummary, SessionEndReason;
import '../../../core/models/telemetry.dart' show DeviceTelemetry;
import '../../../core/models/video_mode.dart';
import '../../../core/state/db_providers.dart' show teamsDaoProvider;
import '../../../core/state/persisted_match_store.dart';
import '../../camera/camera_state.dart' show activeCameraIdProvider;

enum MatchPhase { idle, period, periodBreak, ended }

enum MatchTimer { running, paused }

enum RecState { idle, recording, paused }

@immutable
class LiveEvent {
  const LiveEvent({
    required this.clock,
    required this.label,
    this.kind = 'event',
    this.params = const {},
  });
  final String clock;
  final String label;
  final String kind; // event | phase
  final Map<String, String> params;
}

@immutable
class LiveMatchState {
  const LiveMatchState({
    required this.phase,
    required this.timer,
    required this.rec,
    required this.streaming,
    required this.elapsedSeconds,
    required this.currentPeriod,
    required this.numPeriods,
    required this.periodLengthSeconds,
    required this.scoreHome,
    required this.scoreAway,
    required this.homeName,
    required this.awayName,
    required this.events,
    this.homeColorHex,
    this.awayColorHex,
    this.overlayLayout,
    this.recordQuality,
    this.streamQuality,
  });

  final MatchPhase phase;
  final MatchTimer timer;
  final RecState rec;
  final bool streaming;

  /// Elapsed seconds in the current period. Resets to 0 each period.
  final int elapsedSeconds;

  /// 1-based; 0 in [MatchPhase.idle].
  final int currentPeriod;
  final int numPeriods;
  final int periodLengthSeconds;

  final int scoreHome;
  final int scoreAway;
  final String homeName;
  final String awayName;
  final List<LiveEvent> events;
  final String? homeColorHex;
  final String? awayColorHex;
  final OverlayLayout? overlayLayout;

  /// Operator-selected record/stream quality from setup. Attached to the
  /// RecordingControl / StreamingControl start commands so the firmware applies
  /// them at session start (independent — record may differ from stream). Null =>
  /// firmware default (no advertised modes / older firmware).
  final VideoMode? recordQuality;
  final VideoMode? streamQuality;

  bool get isPeriodActive => phase == MatchPhase.period;
  bool get isLastPeriod => currentPeriod == numPeriods && numPeriods > 0;
  bool get awaitingEndOfMatch =>
      phase == MatchPhase.periodBreak && isLastPeriod;

  String get clockText {
    final m = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Compact phase label for the score overlay / top bar:
  ///   PRE  · idle
  ///   P{N} · period (e.g. P1, P2)
  ///   BRK  · between periods
  ///   FT   · ended
  String get phaseLabel => switch (phase) {
    MatchPhase.idle => 'PRE',
    MatchPhase.period => 'P$currentPeriod',
    MatchPhase.periodBreak => isLastPeriod ? 'END' : 'BRK',
    MatchPhase.ended => 'FT',
  };

  String get periodLabelForOverlay => switch (phase) {
    MatchPhase.idle => 'PRE',
    MatchPhase.period => 'P$currentPeriod',
    MatchPhase.periodBreak => isLastPeriod ? 'FT' : 'HT',
    MatchPhase.ended => 'FT',
  };

  static const _sentinel = Object();

  LiveMatchState copyWith({
    MatchPhase? phase,
    MatchTimer? timer,
    RecState? rec,
    bool? streaming,
    int? elapsedSeconds,
    int? currentPeriod,
    int? numPeriods,
    int? periodLengthSeconds,
    int? scoreHome,
    int? scoreAway,
    String? homeName,
    String? awayName,
    List<LiveEvent>? events,
    String? homeColorHex,
    String? awayColorHex,
    Object? overlayLayout = _sentinel,
    VideoMode? recordQuality,
    VideoMode? streamQuality,
  }) {
    return LiveMatchState(
      phase: phase ?? this.phase,
      timer: timer ?? this.timer,
      rec: rec ?? this.rec,
      streaming: streaming ?? this.streaming,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      currentPeriod: currentPeriod ?? this.currentPeriod,
      numPeriods: numPeriods ?? this.numPeriods,
      periodLengthSeconds: periodLengthSeconds ?? this.periodLengthSeconds,
      scoreHome: scoreHome ?? this.scoreHome,
      scoreAway: scoreAway ?? this.scoreAway,
      homeName: homeName ?? this.homeName,
      awayName: awayName ?? this.awayName,
      events: events ?? this.events,
      homeColorHex: homeColorHex ?? this.homeColorHex,
      awayColorHex: awayColorHex ?? this.awayColorHex,
      overlayLayout: identical(overlayLayout, _sentinel)
          ? this.overlayLayout
          : overlayLayout as OverlayLayout?,
      recordQuality: recordQuality ?? this.recordQuality,
      streamQuality: streamQuality ?? this.streamQuality,
    );
  }

  static const initial = LiveMatchState(
    phase: MatchPhase.idle,
    timer: MatchTimer.paused,
    rec: RecState.idle,
    streaming: false,
    elapsedSeconds: 0,
    currentPeriod: 0,
    numPeriods: 2,
    periodLengthSeconds: 35 * 60,
    scoreHome: 0,
    scoreAway: 0,
    homeName: 'NR',
    awayName: 'EFC',
    events: [],
  );
}

class LiveMatchController extends Notifier<LiveMatchState> {
  @override
  LiveMatchState build() {
    // Persist-on-change (U2): every mutation snapshots the scoreboard into
    // the per-device live-match store so an app kill loses nothing.
    listenSelf((_, next) => _persistOnChange(next));
    return LiveMatchState.initial;
  }

  /// Injectable wall clock — tests pin it to make the anchor math
  /// deterministic. Production always uses [DateTime.now].
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// The team_match id this live session finalizes into when the match ends
  /// (set by [loadFromUpcoming]). Null for an ad-hoc session with no library
  /// row. In the setup flow this id IS the session's `match_uuid` (setup
  /// pushes `matchUuid = match.id`), so it also keys persistence/reconcile.
  String? _matchId;
  String? get matchId => _matchId;

  // Wall-clock period anchor (U2): while the timer runs, elapsed derives from
  // `_anchorElapsedSeconds + (now - _anchorEpochMs)` instead of counting UI
  // ticks — immune to UI-timer drift and, once persisted, to app kills.
  int? _anchorEpochMs;
  int _anchorElapsedSeconds = 0;

  // Last firmware-observed runtime flag (telemetry poll). Null until the
  // firmware has been observed at least once — the uncommanded-stop detector
  // fires only on an observed true→false edge, so a just-sent start command
  // that the firmware hasn't reflected yet never reads as a stop.
  bool? _fwRecordingObserved;

  static String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  void _setAnchor(int elapsedSeconds) {
    _anchorEpochMs = clock().millisecondsSinceEpoch;
    _anchorElapsedSeconds = elapsedSeconds;
  }

  void _clearAnchor() => _anchorEpochMs = null;

  /// Elapsed seconds derived from the wall-clock anchor while the timer runs
  /// (falls back to the last stored value when paused / no anchor).
  int _currentElapsedSeconds() {
    final anchor = _anchorEpochMs;
    if (state.phase != MatchPhase.period ||
        state.timer != MatchTimer.running ||
        anchor == null) {
      return state.elapsedSeconds;
    }
    final delta = ((clock().millisecondsSinceEpoch - anchor) / 1000).floor();
    return delta > 0 ? _anchorElapsedSeconds + delta : _anchorElapsedSeconds;
  }

  /// Called once per second by the live page as a cadence driver; the value
  /// itself derives from the wall-clock anchor (UI-timer drift immune). When
  /// the period length is reached the timer auto-stops and we transition to
  /// [MatchPhase.periodBreak] (the user must explicitly end the match
  /// from the periodBreak after the final period).
  void tick() {
    if (state.phase != MatchPhase.period) return;
    if (state.timer != MatchTimer.running) return;
    if (_anchorEpochMs == null) {
      // Defensive: a running period always has an anchor; re-anchor if a
      // legacy path dropped it so the clock keeps moving.
      _setAnchor(state.elapsedSeconds);
    }
    final next = _currentElapsedSeconds();
    if (next >= state.periodLengthSeconds && state.periodLengthSeconds > 0) {
      _clearAnchor();
      _endPeriodInternal(elapsed: state.periodLengthSeconds);
      return;
    }
    if (next != state.elapsedSeconds) {
      state = state.copyWith(elapsedSeconds: next);
    }
  }

  /// Start the next period (period 1 from idle, period N+1 from break).
  /// Optionally toggles recording / streaming on at the same time — the
  /// kickoff modal in the UI passes the user's choices here.
  void startPeriod({bool? startRecording, bool? startStreaming}) {
    if (state.phase != MatchPhase.idle &&
        state.phase != MatchPhase.periodBreak) {
      return;
    }
    if (state.awaitingEndOfMatch) return; // last period already played
    final next = state.currentPeriod + 1;
    if (next > state.numPeriods) return;
    final rec = startRecording == true && state.rec == RecState.idle
        ? RecState.recording
        : state.rec;
    final streaming = startStreaming ?? state.streaming;
    _setAnchor(0);
    state = state.copyWith(
      phase: MatchPhase.period,
      timer: MatchTimer.running,
      currentPeriod: next,
      elapsedSeconds: 0,
      rec: rec,
      streaming: streaming,
      events: [
        LiveEvent(
          clock: '00:00',
          label: next == 1 ? 'Kickoff' : 'Start period $next',
          kind: 'phase',
        ),
        ...state.events,
      ],
    );
  }

  /// Manually end the current period — same effect as the auto-stop on
  /// reaching the period length.
  void endPeriod() {
    if (state.phase != MatchPhase.period) return;
    final elapsed = _currentElapsedSeconds();
    _clearAnchor();
    _endPeriodInternal(elapsed: elapsed);
  }

  void _endPeriodInternal({required int elapsed}) {
    state = state.copyWith(
      phase: MatchPhase.periodBreak,
      timer: MatchTimer.paused,
      elapsedSeconds: elapsed,
      events: [
        LiveEvent(
          clock: _fmt(elapsed),
          label: 'End period ${state.currentPeriod}',
          kind: 'phase',
        ),
        ...state.events,
      ],
    );
  }

  /// Final transition — only valid after the last period has ended.
  /// `stopRecording` / `stopStreaming` reflect the user's choices in the
  /// end-of-match modal.
  void endMatch({bool stopRecording = true, bool stopStreaming = true}) {
    final rec = stopRecording ? RecState.idle : state.rec;
    final streaming = stopStreaming ? false : state.streaming;
    _clearAnchor();
    state = state.copyWith(
      phase: MatchPhase.ended,
      timer: MatchTimer.paused,
      rec: rec,
      streaming: streaming,
      events: [
        LiveEvent(
          clock: _fmt(state.elapsedSeconds),
          label: 'End match',
          kind: 'phase',
        ),
        ...state.events,
      ],
    );
  }

  void toggleTimer() {
    if (state.phase != MatchPhase.period) return;
    if (state.timer == MatchTimer.running) {
      // Pause: freeze the wall-derived elapsed, drop the anchor.
      final elapsed = _currentElapsedSeconds();
      _clearAnchor();
      state = state.copyWith(timer: MatchTimer.paused, elapsedSeconds: elapsed);
    } else {
      // Resume: re-anchor at the frozen elapsed.
      _setAnchor(state.elapsedSeconds);
      state = state.copyWith(timer: MatchTimer.running);
    }
  }

  // Recording — independent of the period timer; can run during pre-game
  // and post-game.
  void startRecording() {
    if (state.rec == RecState.idle) {
      state = state.copyWith(rec: RecState.recording);
    }
  }

  void toggleRecPause() {
    if (state.rec == RecState.recording) {
      state = state.copyWith(rec: RecState.paused);
    } else if (state.rec == RecState.paused) {
      state = state.copyWith(rec: RecState.recording);
    } else {
      state = state.copyWith(rec: RecState.recording);
    }
  }

  void stopRecording() {
    state = state.copyWith(rec: RecState.idle);
  }

  // Streaming — independent of the period timer.
  void setStreaming(bool on) => state = state.copyWith(streaming: on);

  void addEvent({
    required String type,
    required String teamLabel,
    String? jersey,
    Map<String, String> params = const {},
  }) {
    final clock = _fmt(_currentElapsedSeconds());
    final jerseyPart = jersey == null || jersey.isEmpty ? '' : ' · #$jersey';
    final isGoal = type == 'Goal';
    final newScoreH = isGoal && teamLabel == state.homeName
        ? state.scoreHome + 1
        : state.scoreHome;
    final newScoreA = isGoal && teamLabel == state.awayName
        ? state.scoreAway + 1
        : state.scoreAway;
    state = state.copyWith(
      scoreHome: newScoreH,
      scoreAway: newScoreA,
      events: [
        LiveEvent(
          clock: clock,
          label: '$type · $teamLabel$jerseyPart',
          params: params,
        ),
        ...state.events,
      ],
    );
  }

  void setTeams(String home, String away) =>
      state = state.copyWith(homeName: home, awayName: away);

  /// Hydrate from an upcoming-match selection. Resets clock + events and
  /// pulls home/away from the team and opponent strings, plus the
  /// scheduled time config (numPeriods, periodLengthSeconds).
  ///
  /// Callers pass the relevant fields from [UpcomingMatch] directly to avoid
  /// a cross-feature import cycle between session_state and match_state.
  void loadFromUpcoming({
    required String matchId,
    required String teamShortName,
    required String teamName,
    required String opponent,
    required int numPeriods,
    required int periodLengthSeconds,
    String? homeColorHex,
  }) {
    _matchId = matchId;
    _clearAnchor();
    _fwRecordingObserved = null;
    final home = teamShortName.isNotEmpty ? teamShortName : teamName;
    final away = opponent.startsWith('vs ') ? opponent.substring(3) : opponent;
    final periods = numPeriods > 0 ? numPeriods : 2;
    final periodLen = periodLengthSeconds > 0 ? periodLengthSeconds : 35 * 60;
    state = LiveMatchState.initial.copyWith(
      homeName: home,
      awayName: away,
      numPeriods: periods,
      periodLengthSeconds: periodLen,
      homeColorHex: homeColorHex,
    );
  }

  void setOverlayLayout(OverlayLayout layout) {
    state = state.copyWith(overlayLayout: layout);
  }

  void setTeamColors(String? home, String? away) {
    state = state.copyWith(homeColorHex: home, awayColorHex: away);
  }

  /// Record the operator's setup-time quality choices so the record/stream start
  /// commands can carry them. Null args leave the existing selection untouched.
  void setQuality({VideoMode? record, VideoMode? stream}) {
    state = state.copyWith(recordQuality: record, streamQuality: stream);
  }

  void reset() {
    _matchId = null;
    _clearAnchor();
    _fwRecordingObserved = null;
    state = LiveMatchState.initial;
  }

  /// Serialize the live events to the Library's eventsJson shape — see
  /// [libraryEventsJson].
  String eventsJson() => libraryEventsJson(state.events);

  String resultString() => '${state.scoreHome}-${state.scoreAway}';

  // ---------------------------------------------------------------------------
  // U2 — persistence, restore, firmware reconcile, finalize
  // ---------------------------------------------------------------------------

  /// Snapshot the scoreboard into the per-device live-match store. Fires on
  /// every state change; skipped pre-kickoff (nothing app-owned to lose) and
  /// when no camera / no match id is in play. A store failure must never
  /// break the session flow — it is logged and swallowed (the camera stays
  /// usable; only kill-survival degrades).
  void _persistOnChange(LiveMatchState s) {
    final uuid = _matchId;
    if (uuid == null) return;
    if (s.phase == MatchPhase.idle && s.currentPeriod == 0) return;
    final deviceId = ref.read(activeCameraIdProvider);
    if (deviceId == null) return;
    unawaited(
      ref
          .read(persistedMatchStoreProvider)
          .save(deviceId, _toPersisted(s, uuid))
          .catchError(
            (Object e) => debugPrint('[live-match] persist failed: $e'),
          ),
    );
  }

  PersistedLiveMatch _toPersisted(LiveMatchState s, String uuid) {
    final nowMs = clock().millisecondsSinceEpoch;
    final running =
        s.phase == MatchPhase.period && s.timer == MatchTimer.running;
    return PersistedLiveMatch(
      matchUuid: uuid,
      libraryMatchId: uuid,
      scoreA: s.scoreHome,
      scoreB: s.scoreAway,
      homeName: s.homeName,
      awayName: s.awayName,
      phase: _toPersistedPhase(s.phase),
      timerRunning: running,
      recPaused: s.rec == RecState.paused,
      currentPeriod: s.currentPeriod,
      numPeriods: s.numPeriods,
      periodLengthSeconds: s.periodLengthSeconds,
      elapsedSeconds: running ? _currentElapsedSeconds() : s.elapsedSeconds,
      anchorEpochMs: running ? nowMs : null,
      eventsJson: encodeLiveEvents(s.events),
      homeColorHex: s.homeColorHex,
      awayColorHex: s.awayColorHex,
      updatedAtEpochMs: nowMs,
    );
  }

  /// Restore the scoreboard from the persisted store on a rejoin (AE1). App
  /// data (scores, events, period structure, names) comes from [p]; runtime
  /// facts come from the firmware: the clock ([firmwareElapsedSeconds] /
  /// [firmwareClockRunning]) wins outright — it is the only clock that ran —
  /// and recording/streaming flags are adopted from the snapshot. When the
  /// firmware clock is absent (older firmware) the wall-clock anchor is the
  /// fallback. An adopted elapsed >= the period length fires the period end
  /// exactly once (the phase transition makes a refire impossible).
  void restoreFromPersisted(
    PersistedLiveMatch p, {
    int? firmwareElapsedSeconds,
    bool? firmwareClockRunning,
    bool? isRecording,
    bool? isStreaming,
  }) {
    _matchId = p.libraryMatchId ?? p.matchUuid;
    _fwRecordingObserved = null;
    final phase = _fromPersistedPhase(p.phase);
    final running =
        phase == MatchPhase.period && (firmwareClockRunning ?? p.timerRunning);
    final elapsed =
        firmwareElapsedSeconds ??
        p.effectiveElapsedSeconds(clock().millisecondsSinceEpoch);
    final rec = (isRecording ?? false)
        ? RecState.recording
        : p.recPaused
        ? RecState.paused
        : RecState.idle;
    state = LiveMatchState(
      phase: phase,
      timer: running ? MatchTimer.running : MatchTimer.paused,
      rec: rec,
      streaming: isStreaming ?? false,
      elapsedSeconds: elapsed,
      currentPeriod: p.currentPeriod,
      numPeriods: p.numPeriods,
      periodLengthSeconds: p.periodLengthSeconds,
      scoreHome: p.scoreA,
      scoreAway: p.scoreB,
      homeName: p.homeName,
      awayName: p.awayName,
      events: decodeLiveEvents(p.eventsJson),
      homeColorHex: p.homeColorHex,
      awayColorHex: p.awayColorHex,
    );
    if (running) {
      _setAnchor(elapsed);
    } else {
      _clearAnchor();
    }
    _maybeAutoEndPeriod(elapsed);
  }

  /// Silent rejoin against an unknown running session (origin R3): no
  /// persisted match for the firmware's `match_uuid` (app killed before the
  /// first persist, or a second phone's session) — rebuild a scoreboard VIEW
  /// from the firmware match state. Period structure isn't on the wire, so
  /// the defaults stand; no period-end auto-fire happens here (the real
  /// period length is unknown).
  void adoptFirmwareView(
    MatchState ms, {
    bool? isRecording,
    bool? isStreaming,
  }) {
    final uuid = ms.matchUuid;
    _matchId = (uuid != null && uuid.isNotEmpty) ? uuid : null;
    _fwRecordingObserved = null;
    final phase = switch (ms.status) {
      MatchStatus.active || MatchStatus.paused => MatchPhase.period,
      MatchStatus.halfTime => MatchPhase.periodBreak,
      MatchStatus.finished => MatchPhase.ended,
      MatchStatus.notStarted || MatchStatus.unknown =>
        ms.currentPeriod > 0 ? MatchPhase.periodBreak : MatchPhase.idle,
    };
    final running =
        phase == MatchPhase.period &&
        (ms.clockRunning ?? ms.status == MatchStatus.active);
    final elapsed = ms.elapsedSeconds ?? 0;
    state = LiveMatchState.initial.copyWith(
      phase: phase,
      timer: running ? MatchTimer.running : MatchTimer.paused,
      rec: (isRecording ?? false) ? RecState.recording : RecState.idle,
      streaming: isStreaming ?? false,
      elapsedSeconds: elapsed,
      currentPeriod: ms.currentPeriod,
      scoreHome: ms.scoreA,
      scoreAway: ms.scoreB,
      // team_a_id is a UUID (useless as a label); team_b_id doubles as the
      // opponent's display name in the session-config contract.
      awayName: ms.teamBId.isNotEmpty ? ms.teamBId : state.awayName,
      // Period structure unknown on the wire: disable the tick auto-end
      // rather than ending against a default length that isn't this match's.
      periodLengthSeconds: 0,
      numPeriods: ms.currentPeriod > 0 ? ms.currentPeriod : 2,
    );
    if (running) {
      _setAnchor(elapsed);
    } else {
      _clearAnchor();
    }
  }

  /// Rejoin runtime adoption for a match the controller ALREADY tracks
  /// in memory (persist failed / store wiped, app not killed): the firmware
  /// clock wins outright — elapsed AND run-state, no agreement guard (a pause
  /// tapped while disconnected never reached the firmware, and the firmware
  /// clock is the only one that ran). Recording/streaming flags follow the
  /// snapshot.
  void adoptFirmwareRuntime({
    int? elapsedSeconds,
    bool? clockRunning,
    bool? isRecording,
    bool? isStreaming,
  }) {
    _fwRecordingObserved = null;
    final s = state;
    final rec = isRecording == null
        ? s.rec
        : isRecording
        ? RecState.recording
        : s.rec == RecState.paused
        ? RecState.paused
        : RecState.idle;
    final streaming = isStreaming ?? s.streaming;
    if (s.phase != MatchPhase.period) {
      state = s.copyWith(rec: rec, streaming: streaming);
      return;
    }
    final running = clockRunning ?? (s.timer == MatchTimer.running);
    final elapsed = elapsedSeconds ?? s.elapsedSeconds;
    state = s.copyWith(
      rec: rec,
      streaming: streaming,
      elapsedSeconds: elapsed,
      timer: running ? MatchTimer.running : MatchTimer.paused,
    );
    if (running) {
      _setAnchor(elapsed);
    } else {
      _clearAnchor();
    }
    _maybeAutoEndPeriod(elapsed);
  }

  /// Continuous drift correction (U2): the 2 s match-state poll pushes the
  /// firmware clock into the local one while connected. Applies only when
  /// the poll belongs to the current match and both sides agree on whether
  /// the clock is running (a pause/resume command in flight makes them
  /// disagree transiently — skipping that sample avoids flapping).
  void onFirmwareMatchState(MatchState ms) {
    final uuid = ms.matchUuid;
    if (uuid == null || uuid.isEmpty || uuid != _matchId) return;
    if (state.phase != MatchPhase.period) return;
    final elapsed = ms.elapsedSeconds;
    if (elapsed == null) return;
    final localRunning = state.timer == MatchTimer.running;
    final fwRunning = ms.clockRunning;
    if (fwRunning != null && fwRunning != localRunning) return;
    if (_maybeAutoEndPeriod(elapsed)) return;
    if (localRunning) {
      _setAnchor(elapsed);
    }
    if (elapsed != state.elapsedSeconds) {
      state = state.copyWith(elapsedSeconds: elapsed);
    }
  }

  /// Poll truth for runtime flags (U2): a recording that stopped on the
  /// camera without an app command (auto-stop race, firmware recovery) is
  /// followed, never fought — the local flag flips and a one-line notice
  /// explains it. Fires only on an OBSERVED true→false telemetry edge while
  /// the app believes it is recording, so a just-tapped Record (firmware not
  /// yet started) or an app-side pause can never false-positive.
  void onFirmwareTelemetry(DeviceTelemetry t) {
    final wasObserved = _fwRecordingObserved;
    _fwRecordingObserved = t.isRecording;
    if (wasObserved == true &&
        !t.isRecording &&
        state.rec == RecState.recording) {
      state = state.copyWith(rec: RecState.idle);
      ref.read(sessionNoticeProvider.notifier).state =
          'Recording stopped on the camera.';
    }
  }

  /// The session ended while the app was away (reconcile decided so from the
  /// snapshot): follow the firmware — mark the local match ended so a mounted
  /// session screen stops showing a live period. No-op unless mid-match.
  void followAwayEnd() {
    if (!isLiveMatchRunning(state)) return;
    _clearAnchor();
    state = state.copyWith(
      phase: MatchPhase.ended,
      timer: MatchTimer.paused,
      rec: RecState.idle,
      streaming: false,
    );
  }

  /// Fire the period end exactly once when an adopted firmware elapsed has
  /// passed the period length. Returns true when the end fired. The
  /// `MatchPhase.period` guard is what makes "once": the transition to
  /// periodBreak removes the precondition for any repeat.
  bool _maybeAutoEndPeriod(int elapsed) {
    if (state.phase != MatchPhase.period) return false;
    if (state.periodLengthSeconds <= 0) return false;
    if (elapsed < state.periodLengthSeconds) return false;
    _clearAnchor();
    _sendPeriodEndToCamera(state.currentPeriod);
    _endPeriodInternal(elapsed: state.periodLengthSeconds);
    return true;
  }

  /// Best-effort MATCH_PERIOD_END push for an auto-fired period end (the
  /// firmware's own clock passed the length; tell it to freeze the overlay
  /// clock). Skipped while disconnected — fire-and-forget parity with the
  /// session screen's manual button.
  void _sendPeriodEndToCamera(int period) {
    final deviceId = ref.read(activeCameraIdProvider);
    if (deviceId == null) return;
    final connState = ref.read(connectionStateProvider(deviceId)).valueOrNull;
    if (connState != CameraConnectionState.connected) return;
    unawaited(() async {
      try {
        await ref
            .read(bleServiceProvider)
            .sendCommand<void>(
              deviceId,
              MatchControlCommand(
                action: BleMatchControlAction.periodEnd,
                period: period,
              ),
            );
      } catch (e) {
        debugPrint('[live-match] auto period-end push failed: $e');
      }
    }());
  }

  /// THE single finalize path for a match ending in-app (normal end): flips
  /// the team_matches row to 'past' with the final score + events, then
  /// clears the live store LAST (crash in between → the idempotent finalize
  /// simply re-runs on the next connect). Local failures are logged, never
  /// thrown — a Drift hiccup must not break leaving the match.
  Future<void> finalizeToLibrary() async {
    final uuid = _matchId;
    if (uuid == null) {
      debugPrint('[finalize] SKIP — no matchId (ad-hoc session)');
      return;
    }
    final deviceId = ref.read(activeCameraIdProvider);
    try {
      final updated = await finalizeLiveMatchRecord(
        ref,
        deviceId: deviceId,
        record: _toPersisted(state, uuid),
      );
      debugPrint('[finalize] done updated=$updated matchId=$uuid');
    } catch (e) {
      debugPrint('[finalize] ERROR $e');
    }
  }
}

// ---------------------------------------------------------------------------
// U2 — shared finalize path + notices + codecs
// ---------------------------------------------------------------------------

/// One-line session notice ("Match ended while away — …", "Recording stopped
/// on the camera."). Null = nothing to show. Set by the reconcile away-ended
/// path and the poll-truth follower; cleared by the user dismissing the
/// banner (or a new session starting).
final sessionNoticeProvider = StateProvider<String?>((_) => null);

/// THE single team_matches finalize used by every flow — normal end,
/// away-ended reconcile, stale-persisted settlement. Idempotent (the library
/// write is a plain row UPDATE keyed by the match id: re-running writes the
/// same data) and clear-LAST: the persisted live row is removed only after
/// the library row is safely finalized, so a crash in between re-runs the
/// finalize on the next connect instead of orphaning data. Returns whether a
/// library row was updated (false for sessions with no library row).
Future<bool> finalizeLiveMatchRecord(
  Ref ref, {
  required String? deviceId,
  required PersistedLiveMatch record,
}) async {
  var updated = false;
  final libId = record.libraryMatchId;
  if (libId != null) {
    updated = await ref
        .read(teamsDaoProvider)
        .finalizeMatch(
          libId,
          result: '${record.scoreA}-${record.scoreB}',
          eventsJson: libraryEventsJson(decodeLiveEvents(record.eventsJson)),
        );
  }
  if (deviceId != null) {
    // Clear-last, keyed by match_uuid (idempotent; a newer session's row is
    // never touched).
    await ref
        .read(persistedMatchStoreProvider)
        .clear(deviceId, record.matchUuid);
  }
  return updated;
}

/// The one-line "ended while away" copy (AE4). [summary] must already be
/// uuid-matched by the caller — cross-match summaries never reach here.
String awayEndedNoticeText(LastSessionSummary? summary) {
  String fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:'
      '${(s % 60).toString().padLeft(2, '0')}';
  if (summary == null) return 'Match ended while away.';
  switch (summary.endReason) {
    case SessionEndReason.autoStop:
      return 'Match ended while away — recording auto-stopped.';
    case SessionEndReason.cameraFailure:
    case SessionEndReason.reboot:
      return 'Match ended while away — camera restarted, check the recording.';
    case SessionEndReason.appStop:
      final t = summary.endClockSeconds;
      return t == null
          ? 'Match ended while away — recording saved.'
          : 'Match ended while away — saved at ${fmt(t)}.';
    case SessionEndReason.unknown:
      return 'Match ended while away.';
  }
}

PersistedMatchPhase _toPersistedPhase(MatchPhase p) => switch (p) {
  MatchPhase.idle => PersistedMatchPhase.idle,
  MatchPhase.period => PersistedMatchPhase.period,
  MatchPhase.periodBreak => PersistedMatchPhase.periodBreak,
  MatchPhase.ended => PersistedMatchPhase.ended,
};

MatchPhase _fromPersistedPhase(PersistedMatchPhase p) => switch (p) {
  PersistedMatchPhase.idle => MatchPhase.idle,
  PersistedMatchPhase.period => MatchPhase.period,
  PersistedMatchPhase.periodBreak => MatchPhase.periodBreak,
  PersistedMatchPhase.ended => MatchPhase.ended,
};

/// Store codec for [LiveEvent] — the persisted shape mirrors the in-memory
/// one (`{clock, label, kind, params}`), distinct from the Library shape.
String encodeLiveEvents(List<LiveEvent> events) => jsonEncode([
  for (final e in events)
    {'clock': e.clock, 'label': e.label, 'kind': e.kind, 'params': e.params},
]);

List<LiveEvent> decodeLiveEvents(String json) {
  try {
    final raw = jsonDecode(json);
    if (raw is! List) return const [];
    return [
      for (final e in raw.whereType<Map<String, dynamic>>())
        LiveEvent(
          clock: e['clock'] as String? ?? '00:00',
          label: e['label'] as String? ?? '',
          kind: e['kind'] as String? ?? 'event',
          params: {
            for (final MapEntry(:key, :value)
                in (e['params'] as Map<String, dynamic>? ?? const {}).entries)
              key: value.toString(),
          },
        ),
    ];
  } catch (_) {
    // A corrupt persisted blob must never block a restore — the scoreboard
    // (scores/clock) matters more than the event list.
    return const [];
  }
}

/// Serialize live events to the Library's eventsJson shape (a list of
/// `{timeSeconds, label, team, kind}`). Phase markers (kickoff/end) are
/// dropped; the type/team live inside the label string, so team is left empty
/// and kind is generic — enough to show the event list + time in the Library.
String libraryEventsJson(List<LiveEvent> events) {
  final out = <Map<String, Object>>[];
  for (final e in events) {
    if (e.kind == 'phase') continue;
    final parts = e.clock.split(':');
    final seconds = parts.length == 2
        ? (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0)
        : 0;
    out.add({
      'timeSeconds': seconds,
      'label': e.label,
      'team': '',
      'kind': 'other',
    });
  }
  return jsonEncode(out);
}

/// Wires the connected camera's 2 s match-state poll and 1 Hz telemetry into
/// the live-match controller (drift correction + poll-truth runtime flags).
/// Mounted by [MatchPage] (which lives for the whole app session inside the
/// shell's IndexedStack), so the sync runs whenever a camera is connected —
/// not only while the session screen is visible.
final liveMatchFirmwareSyncProvider = Provider<void>((ref) {
  final deviceId = ref.watch(activeCameraIdProvider);
  if (deviceId == null) return;
  ref.listen(matchStateProvider(deviceId), (_, next) {
    final ms = next.valueOrNull;
    if (ms == null) return;
    ref.read(liveMatchProvider.notifier).onFirmwareMatchState(ms);
  });
  ref.listen(telemetryProvider(deviceId), (_, next) {
    final t = next.valueOrNull;
    if (t == null) return;
    ref.read(liveMatchProvider.notifier).onFirmwareTelemetry(t);
  });
});

final liveMatchProvider = NotifierProvider<LiveMatchController, LiveMatchState>(
  LiveMatchController.new,
);

/// True iff a match is in flight — i.e. past kickoff and not yet finalized.
/// Phases `period` (period running) and `periodBreak` (between / after the
/// final period, awaiting end-of-match) both qualify. `idle` and `ended`
/// don't.
///
/// Used by [UsersController.delete] for the R10 live-match precondition. We
/// keep the rule conservative: any live match blocks deleting any user. The
/// per-user-cross-reference variant of this check is deferred (would require
/// `LiveMatchState` to expose owning team / preset / destination ids).
bool isLiveMatchRunning(LiveMatchState s) =>
    s.phase == MatchPhase.period || s.phase == MatchPhase.periodBreak;

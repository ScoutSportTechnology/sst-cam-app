// Live match state — local mirror of what the firmware would push back over
// BLE. The match flow drives this directly from the UI so the wireframe
// interactions are end-to-end clickable without a real device.
//
// Phase model is generalized over `numPeriods`:
//   idle         → before kickoff (pre-game; recording/streaming may be on)
//   period       → a period is in progress; clock counts up to periodLengthSeconds
//   periodBreak  → between periods (or after final period, awaiting end-of-match)
//   ended        → match is over; back-arrow returns to landing

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/overlay_layout.dart';

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
  LiveMatchState build() => LiveMatchState.initial;

  static String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  /// Called once per second by the live page. Increments the per-period
  /// clock when the timer is running and a period is active. When the
  /// period length is reached the timer auto-stops and we transition to
  /// [MatchPhase.periodBreak] (the user must explicitly end the match
  /// from the periodBreak after the final period).
  void tick() {
    if (state.phase != MatchPhase.period) return;
    if (state.timer != MatchTimer.running) return;
    final next = state.elapsedSeconds + 1;
    if (next >= state.periodLengthSeconds && state.periodLengthSeconds > 0) {
      _endPeriodInternal(elapsed: state.periodLengthSeconds);
      return;
    }
    state = state.copyWith(elapsedSeconds: next);
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
    _endPeriodInternal(elapsed: state.elapsedSeconds);
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
    state = state.copyWith(
      timer: state.timer == MatchTimer.running
          ? MatchTimer.paused
          : MatchTimer.running,
    );
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
  }) {
    final clock = _fmt(state.elapsedSeconds);
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
        LiveEvent(clock: clock, label: '$type · $teamLabel$jerseyPart'),
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
    required String teamShortName,
    required String teamName,
    required String opponent,
    required int numPeriods,
    required int periodLengthSeconds,
    String? homeColorHex,
  }) {
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

  void reset() {
    state = LiveMatchState.initial;
  }
}

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

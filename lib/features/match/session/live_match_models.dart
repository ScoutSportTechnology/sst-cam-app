// Live match model — the immutable scoreboard state the session UI renders,
// plus the event codecs shared by the persistence store and the Library
// finalize path. Split from session_state.dart (which keeps the controller +
// providers); re-exported from there, so importers are unaffected.
//
// Phase model is generalized over `numPeriods`:
//   idle         → before kickoff (pre-game; recording/streaming may be on)
//   period       → a period is in progress; clock counts up to periodLengthSeconds
//   periodBreak  → between periods (or after final period, awaiting end-of-match)
//   ended        → match is over; back-arrow returns to landing

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/models/overlay_layout.dart';
import '../../../core/models/video_mode.dart';

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

// ---------------------------------------------------------------------------
// Event codecs — store shape + Library shape
// ---------------------------------------------------------------------------

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

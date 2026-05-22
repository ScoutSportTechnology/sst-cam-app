import '../../features/video/video_state.dart';

/// Immutable snapshot of the on-screen overlay at a particular video timestamp.
class OverlayState {
  const OverlayState({
    required this.timeSeconds,
    required this.homeScore,
    required this.awayScore,
    required this.period,
    required this.recentEventLabel,
  });

  final int timeSeconds;
  final int homeScore;
  final int awayScore;
  final int period;
  final String? recentEventLabel;

  /// Returns a chronologically ordered list of [OverlayState] snapshots
  /// derived from [events].
  ///
  /// The list always starts with a baseline state at t=0 (0-0, period 1, no
  /// label). Each event appends one additional state. Events are processed in
  /// ascending [LibraryEvent.timeSeconds] order.
  ///
  /// - A `goal` event whose [LibraryEvent.team] equals [homeShortName]
  ///   increments [homeScore]; any other `goal` increments [awayScore].
  /// - Non-goal events update only [recentEventLabel]; scores are unchanged.
  /// - [period] is computed as `event.timeSeconds ~/ periodLengthSeconds + 1`.
  static List<OverlayState> fromEvents(
    List<LibraryEvent> events, {
    required int periodLengthSeconds,
    required String homeShortName,
  }) {
    const baseline = OverlayState(
      timeSeconds: 0,
      homeScore: 0,
      awayScore: 0,
      period: 1,
      recentEventLabel: null,
    );

    final sorted = List<LibraryEvent>.from(events)
      ..sort((a, b) => a.timeSeconds.compareTo(b.timeSeconds));

    final states = <OverlayState>[baseline];
    var homeScore = 0;
    var awayScore = 0;

    for (final event in sorted) {
      final period = event.timeSeconds ~/ periodLengthSeconds + 1;

      if (event.kind == 'goal') {
        if (event.team == homeShortName) {
          homeScore++;
        } else {
          awayScore++;
        }
        states.add(OverlayState(
          timeSeconds: event.timeSeconds,
          homeScore: homeScore,
          awayScore: awayScore,
          period: period,
          recentEventLabel: event.label,
        ));
      } else {
        states.add(OverlayState(
          timeSeconds: event.timeSeconds,
          homeScore: homeScore,
          awayScore: awayScore,
          period: period,
          recentEventLabel: event.label,
        ));
      }
    }

    return states;
  }

  /// Returns the [OverlayState] that was active at [timeSeconds] by finding
  /// the latest state whose [OverlayState.timeSeconds] is <= [timeSeconds].
  ///
  /// Returns the baseline state `{t:0, 0-0, period:1, null}` if [states] is
  /// empty or [timeSeconds] is before the first event.
  static OverlayState atTime(List<OverlayState> states, int timeSeconds) {
    const baseline = OverlayState(
      timeSeconds: 0,
      homeScore: 0,
      awayScore: 0,
      period: 1,
      recentEventLabel: null,
    );

    if (states.isEmpty) return baseline;

    // Binary search for the largest index where states[i].timeSeconds <= timeSeconds.
    var lo = 0;
    var hi = states.length - 1;
    var result = -1;

    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (states[mid].timeSeconds <= timeSeconds) {
        result = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }

    if (result == -1) return baseline;
    return states[result];
  }
}

/// Simple configuration for which overlay elements are visible during playback.
class OverlayConfig {
  const OverlayConfig({
    required this.showScore,
    required this.showEvents,
  });

  final bool showScore;
  final bool showEvents;
}

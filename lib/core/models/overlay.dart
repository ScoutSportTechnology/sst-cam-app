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

    final state = states[result];
    // Event labels expire after 30 seconds so they don't stick permanently.
    if (timeSeconds - state.timeSeconds > 30) {
      return OverlayState(
        timeSeconds: state.timeSeconds,
        homeScore: state.homeScore,
        awayScore: state.awayScore,
        period: state.period,
        recentEventLabel: null,
      );
    }
    return state;
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

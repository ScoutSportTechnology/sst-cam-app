// Feature-layer helper that bridges core OverlayState with feature-layer
// LibraryEvent types. Keeping this here avoids an inverted dependency where
// the core model layer imports the feature layer.
import '../../core/models/overlay.dart';
import 'video_state.dart' show LibraryEvent;

/// Builds a chronologically ordered list of [OverlayState] snapshots
/// derived from [events].
///
/// The list always starts with a baseline state at t=0 (0-0, period 1, no
/// label). Each event appends one additional state. Events are processed in
/// ascending [LibraryEvent.timeSeconds] order.
///
/// - A `goal` event whose [LibraryEvent.team] equals [homeShortName]
///   increments homeScore; any other `goal` increments awayScore.
/// - Non-goal events update only recentEventLabel; scores are unchanged.
/// - period is computed as `event.timeSeconds ~/ periodLengthSeconds + 1`.
///   When [periodLengthSeconds] is 0, period defaults to 1.
List<OverlayState> buildOverlayStates(
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
    final period = periodLengthSeconds > 0
        ? event.timeSeconds ~/ periodLengthSeconds + 1
        : 1;

    if (event.kind == 'goal') {
      if (event.team == homeShortName) {
        homeScore++;
      } else {
        awayScore++;
      }
      states.add(
        OverlayState(
          timeSeconds: event.timeSeconds,
          homeScore: homeScore,
          awayScore: awayScore,
          period: period,
          recentEventLabel: event.label,
        ),
      );
    } else {
      states.add(
        OverlayState(
          timeSeconds: event.timeSeconds,
          homeScore: homeScore,
          awayScore: awayScore,
          period: period,
          recentEventLabel: event.label,
        ),
      );
    }
  }

  return states;
}

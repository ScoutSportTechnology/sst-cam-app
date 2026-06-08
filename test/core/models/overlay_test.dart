import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/models/overlay.dart';
import 'package:sst_cam_app/features/video/overlay_helper.dart';
import 'package:sst_cam_app/features/video/video_state.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  LibraryEvent goalEvent({
    required int timeSeconds,
    required String team,
    String label = 'Goal',
  }) => LibraryEvent(
    timeSeconds: timeSeconds,
    label: label,
    team: team,
    kind: 'goal',
  );

  LibraryEvent foulEvent({required int timeSeconds, required String team}) =>
      LibraryEvent(
        timeSeconds: timeSeconds,
        label: 'Foul',
        team: team,
        kind: 'foul',
      );

  // ---------------------------------------------------------------------------
  // OverlayState.fromEvents
  // ---------------------------------------------------------------------------

  group('OverlayState.fromEvents', () {
    test('happy path: 3 goals at 10s (home), 25s (away), 40s (home) → '
        '4 states with expected scores', () {
      final events = [
        goalEvent(timeSeconds: 10, team: 'HOME'),
        goalEvent(timeSeconds: 25, team: 'AWAY'),
        goalEvent(timeSeconds: 40, team: 'HOME'),
      ];

      final states = buildOverlayStates(
        events,
        periodLengthSeconds: 60,
        homeShortName: 'HOME',
      );

      expect(states.length, 4); // baseline + 3 events

      // Baseline.
      expect(states[0].timeSeconds, 0);
      expect(states[0].homeScore, 0);
      expect(states[0].awayScore, 0);
      expect(states[0].period, 1);
      expect(states[0].recentEventLabel, isNull);

      // After first goal (HOME, 10s → 1-0).
      expect(states[1].timeSeconds, 10);
      expect(states[1].homeScore, 1);
      expect(states[1].awayScore, 0);

      // After second goal (AWAY, 25s → 1-1).
      expect(states[2].timeSeconds, 25);
      expect(states[2].homeScore, 1);
      expect(states[2].awayScore, 1);

      // After third goal (HOME, 40s → 2-1).
      expect(states[3].timeSeconds, 40);
      expect(states[3].homeScore, 2);
      expect(states[3].awayScore, 1);
    });

    test('empty event list → single baseline state', () {
      final states = buildOverlayStates(
        const [],
        periodLengthSeconds: 900,
        homeShortName: 'HOME',
      );

      expect(states.length, 1);
      expect(states[0].timeSeconds, 0);
      expect(states[0].homeScore, 0);
      expect(states[0].awayScore, 0);
      expect(states[0].period, 1);
      expect(states[0].recentEventLabel, isNull);
    });

    test(
      'goal by team whose shortName != homeShortName → increments awayScore',
      () {
        final events = [goalEvent(timeSeconds: 30, team: 'VISITOR')];

        final states = buildOverlayStates(
          events,
          periodLengthSeconds: 900,
          homeShortName: 'HOME',
        );

        expect(states.length, 2);
        expect(states[1].homeScore, 0);
        expect(states[1].awayScore, 1);
      },
    );

    test(
      'non-goal event (foul) → recentEventLabel updated, scores unchanged',
      () {
        final events = [foulEvent(timeSeconds: 15, team: 'HOME')];

        final states = buildOverlayStates(
          events,
          periodLengthSeconds: 900,
          homeShortName: 'HOME',
        );

        expect(states.length, 2);
        expect(states[1].homeScore, 0);
        expect(states[1].awayScore, 0);
        expect(states[1].recentEventLabel, 'Foul');
      },
    );

    test('period is computed from timeSeconds ~/ periodLengthSeconds + 1', () {
      // With periodLengthSeconds=900 (15 min):
      //   t=899 → period 1, t=900 → period 2, t=1800 → period 3.
      final events = [
        goalEvent(timeSeconds: 899, team: 'HOME'),
        goalEvent(timeSeconds: 900, team: 'HOME'),
        goalEvent(timeSeconds: 1800, team: 'HOME'),
      ];

      final states = buildOverlayStates(
        events,
        periodLengthSeconds: 900,
        homeShortName: 'HOME',
      );

      expect(states[1].period, 1);
      expect(states[2].period, 2);
      expect(states[3].period, 3);
    });

    test('periodLengthSeconds=0 does not throw and defaults period to 1', () {
      final events = [
        goalEvent(timeSeconds: 500, team: 'HOME'),
        goalEvent(timeSeconds: 1200, team: 'AWAY'),
      ];

      final states = buildOverlayStates(
        events,
        periodLengthSeconds: 0,
        homeShortName: 'HOME',
      );

      expect(states.length, 3);
      expect(states[1].period, 1);
      expect(states[2].period, 1);
    });

    test('events are sorted chronologically before processing', () {
      // Supply events out of order; scores must still accumulate in time order.
      final events = [
        goalEvent(timeSeconds: 50, team: 'HOME', label: 'Third'),
        goalEvent(timeSeconds: 10, team: 'HOME', label: 'First'),
        goalEvent(timeSeconds: 30, team: 'AWAY', label: 'Second'),
      ];

      final states = buildOverlayStates(
        events,
        periodLengthSeconds: 900,
        homeShortName: 'HOME',
      );

      // States should be in chronological order with correct cumulative scores.
      expect(states[1].timeSeconds, 10);
      expect(states[1].homeScore, 1);
      expect(states[1].awayScore, 0);

      expect(states[2].timeSeconds, 30);
      expect(states[2].homeScore, 1);
      expect(states[2].awayScore, 1);

      expect(states[3].timeSeconds, 50);
      expect(states[3].homeScore, 2);
      expect(states[3].awayScore, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // OverlayState.atTime
  // ---------------------------------------------------------------------------

  group('OverlayState.atTime', () {
    // Build a set of states using fromEvents so atTime tests use realistic data.
    late List<OverlayState> states;

    setUp(() {
      final events = [
        goalEvent(timeSeconds: 10, team: 'HOME'),
        goalEvent(timeSeconds: 25, team: 'AWAY'),
        goalEvent(timeSeconds: 40, team: 'HOME'),
      ];
      states = buildOverlayStates(
        events,
        periodLengthSeconds: 900,
        homeShortName: 'HOME',
      );
    });

    test('empty list → returns baseline state', () {
      final result = OverlayState.atTime(const [], 50);

      expect(result.timeSeconds, 0);
      expect(result.homeScore, 0);
      expect(result.awayScore, 0);
      expect(result.period, 1);
      expect(result.recentEventLabel, isNull);
    });

    test('timeSeconds=0, before first event → baseline state', () {
      final result = OverlayState.atTime(states, 0);

      // states[0] is the baseline at t=0, which satisfies <= 0.
      expect(result.timeSeconds, 0);
      expect(result.homeScore, 0);
      expect(result.awayScore, 0);
    });

    test('timeSeconds exactly at first event (10s) → that event state', () {
      final result = OverlayState.atTime(states, 10);

      expect(result.timeSeconds, 10);
      expect(result.homeScore, 1);
      expect(result.awayScore, 0);
    });

    test('timeSeconds between events → most recent preceding state', () {
      // At t=15, the last event was at t=10 (home goal).
      final result = OverlayState.atTime(states, 15);

      expect(result.timeSeconds, 10);
      expect(result.homeScore, 1);
      expect(result.awayScore, 0);
    });

    test('timeSeconds after all events (99999) → last state', () {
      final result = OverlayState.atTime(states, 99999);

      expect(result.timeSeconds, 40);
      expect(result.homeScore, 2);
      expect(result.awayScore, 1);
    });

    test('timeSeconds exactly at last event → last state', () {
      final result = OverlayState.atTime(states, 40);

      expect(result.timeSeconds, 40);
      expect(result.homeScore, 2);
      expect(result.awayScore, 1);
    });

    test('30s expiry: label present at exactly 30s gap (boundary)', () {
      // State at t=10; query at t=40 → gap=30, label still present.
      const stateAt10 = [
        OverlayState(
          timeSeconds: 0,
          homeScore: 0,
          awayScore: 0,
          period: 1,
          recentEventLabel: null,
        ),
        OverlayState(
          timeSeconds: 10,
          homeScore: 1,
          awayScore: 0,
          period: 1,
          recentEventLabel: 'Goal',
        ),
      ];
      final result = OverlayState.atTime(stateAt10, 40);
      expect(
        result.recentEventLabel,
        'Goal',
        reason: 'gap == 30 is not > 30, so label should be present',
      );
    });

    test('30s expiry: label stripped when gap > 30s', () {
      // State at t=10; query at t=41 → gap=31 > 30, label stripped.
      const stateAt10 = [
        OverlayState(
          timeSeconds: 0,
          homeScore: 0,
          awayScore: 0,
          period: 1,
          recentEventLabel: null,
        ),
        OverlayState(
          timeSeconds: 10,
          homeScore: 1,
          awayScore: 0,
          period: 1,
          recentEventLabel: 'Goal',
        ),
      ];
      final result = OverlayState.atTime(stateAt10, 41);
      expect(
        result.recentEventLabel,
        isNull,
        reason: 'gap == 31 > 30, so label should be stripped',
      );
      // Scores and period are preserved.
      expect(result.homeScore, 1);
      expect(result.awayScore, 0);
    });

    test('30s expiry: label present at gap=0', () {
      const stateAt10 = [
        OverlayState(
          timeSeconds: 0,
          homeScore: 0,
          awayScore: 0,
          period: 1,
          recentEventLabel: null,
        ),
        OverlayState(
          timeSeconds: 10,
          homeScore: 1,
          awayScore: 0,
          period: 1,
          recentEventLabel: 'Goal',
        ),
      ];
      final result = OverlayState.atTime(stateAt10, 10);
      expect(
        result.recentEventLabel,
        'Goal',
        reason: 'gap == 0, label should be present',
      );
    });

    test('timeSeconds before any event in a list with no t=0 baseline → '
        'baseline fallback', () {
      // Construct a raw list that starts after t=0 to exercise the -1 branch.
      const rawStates = [
        OverlayState(
          timeSeconds: 100,
          homeScore: 1,
          awayScore: 0,
          period: 1,
          recentEventLabel: null,
        ),
      ];

      final result = OverlayState.atTime(rawStates, 50);

      // 50 < 100, so result == -1 path → baseline.
      expect(result.timeSeconds, 0);
      expect(result.homeScore, 0);
      expect(result.awayScore, 0);
      expect(result.period, 1);
      expect(result.recentEventLabel, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // OverlayConfig
  // ---------------------------------------------------------------------------

  group('OverlayConfig', () {
    test('stores showScore and showEvents fields', () {
      const cfg = OverlayConfig(showScore: true, showEvents: false);

      expect(cfg.showScore, isTrue);
      expect(cfg.showEvents, isFalse);
    });

    test('both flags false is valid', () {
      const cfg = OverlayConfig(showScore: false, showEvents: false);

      expect(cfg.showScore, isFalse);
      expect(cfg.showEvents, isFalse);
    });

    test('both flags true is valid', () {
      const cfg = OverlayConfig(showScore: true, showEvents: true);

      expect(cfg.showScore, isTrue);
      expect(cfg.showEvents, isTrue);
    });
  });
}

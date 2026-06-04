import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/models/overlay_layout.dart';
import 'package:sst_cam_app/features/match/session/session_state.dart';

ProviderContainer _makeContainer() => ProviderContainer();

const _minimalLayout = OverlayLayout(
  canvasWidth: 1920,
  canvasHeight: 1080,
  elements: [],
  templates: [],
);

void main() {
  group('LiveMatchState — new fields', () {
    late ProviderContainer container;
    late LiveMatchController ctrl;

    setUp(() {
      container = _makeContainer();
      ctrl = container.read(liveMatchProvider.notifier);
    });

    tearDown(() => container.dispose());

    // ---- loadFromUpcoming with homeColorHex --------------------------------

    test('loadFromUpcoming with homeColorHex sets state.homeColorHex', () {
      ctrl.loadFromUpcoming(
        teamShortName: 'NR',
        teamName: 'Norton Rangers',
        opponent: 'vs EFC',
        numPeriods: 2,
        periodLengthSeconds: 2100,
        homeColorHex: '#FF0000',
      );
      expect(container.read(liveMatchProvider).homeColorHex, '#FF0000');
    });

    test('loadFromUpcoming with homeColorHex null leaves state.homeColorHex null', () {
      ctrl.loadFromUpcoming(
        teamShortName: 'NR',
        teamName: 'Norton Rangers',
        opponent: 'vs EFC',
        numPeriods: 2,
        periodLengthSeconds: 2100,
        homeColorHex: null,
      );
      expect(container.read(liveMatchProvider).homeColorHex, isNull);
    });

    // ---- setOverlayLayout --------------------------------------------------

    test('setOverlayLayout stores the layout in state', () {
      ctrl.setOverlayLayout(_minimalLayout);
      expect(container.read(liveMatchProvider).overlayLayout, _minimalLayout);
    });

    // ---- reset clears new fields ------------------------------------------

    test('reset sets overlayLayout to null', () {
      ctrl.setOverlayLayout(_minimalLayout);
      ctrl.reset();
      expect(container.read(liveMatchProvider).overlayLayout, isNull);
    });

    test('reset sets homeColorHex to null', () {
      ctrl.loadFromUpcoming(
        teamShortName: 'NR',
        teamName: 'Norton Rangers',
        opponent: 'vs EFC',
        numPeriods: 2,
        periodLengthSeconds: 2100,
        homeColorHex: '#FF0000',
      );
      ctrl.reset();
      expect(container.read(liveMatchProvider).homeColorHex, isNull);
    });

    // ---- periodLabelForOverlay ---------------------------------------------

    test('periodLabelForOverlay is P1 when phase=period currentPeriod=1', () {
      // Start from idle → start period 1
      ctrl.startPeriod();
      final s = container.read(liveMatchProvider);
      expect(s.phase, MatchPhase.period);
      expect(s.currentPeriod, 1);
      expect(s.periodLabelForOverlay, 'P1');
    });

    test('periodLabelForOverlay is HT when phase=periodBreak and not last period', () {
      // 2-period match; advance to end of period 1 → periodBreak (not last)
      ctrl.startPeriod(); // period 1
      ctrl.endPeriod();   // → periodBreak, currentPeriod=1, numPeriods=2
      final s = container.read(liveMatchProvider);
      expect(s.phase, MatchPhase.periodBreak);
      expect(s.isLastPeriod, isFalse);
      expect(s.periodLabelForOverlay, 'HT');
    });

    test('periodLabelForOverlay is FT when phase=ended', () {
      ctrl.startPeriod(); // period 1
      ctrl.endPeriod();   // periodBreak after period 1
      ctrl.startPeriod(); // period 2
      ctrl.endPeriod();   // periodBreak, isLastPeriod=true
      ctrl.endMatch();    // → ended
      final s = container.read(liveMatchProvider);
      expect(s.phase, MatchPhase.ended);
      expect(s.periodLabelForOverlay, 'FT');
    });

    test('periodLabelForOverlay is FT when phase=periodBreak and isLastPeriod', () {
      // 2-period match; end of period 2 → periodBreak with isLastPeriod=true
      ctrl.startPeriod(); // period 1
      ctrl.endPeriod();
      ctrl.startPeriod(); // period 2
      ctrl.endPeriod();   // → periodBreak, currentPeriod=2, numPeriods=2
      final s = container.read(liveMatchProvider);
      expect(s.phase, MatchPhase.periodBreak);
      expect(s.isLastPeriod, isTrue);
      expect(s.periodLabelForOverlay, 'FT');
    });

    // ---- copyWith preserves new fields when omitted -----------------------

    test('copyWith with no args preserves all three new fields', () {
      ctrl.setOverlayLayout(_minimalLayout);
      ctrl.setTeamColors('#FF0000', '#0000FF');
      final before = container.read(liveMatchProvider);

      // copyWith with an unrelated field change
      final after = before.copyWith(elapsedSeconds: 42);

      expect(after.overlayLayout, same(before.overlayLayout));
      expect(after.homeColorHex, before.homeColorHex);
      expect(after.awayColorHex, before.awayColorHex);
    });

    // ---- phaseLabel (existing) is unchanged for periodBreak non-last ------

    test('phaseLabel for periodBreak non-last period returns BRK (not HT)', () {
      ctrl.startPeriod(); // period 1
      ctrl.endPeriod();   // periodBreak, not last
      final s = container.read(liveMatchProvider);
      expect(s.phase, MatchPhase.periodBreak);
      expect(s.isLastPeriod, isFalse);
      expect(s.phaseLabel, 'BRK');
    });
  });
}

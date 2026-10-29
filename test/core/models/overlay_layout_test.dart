import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/models/overlay_layout.dart';

void main() {
  group('defaultScoreboardLayout', () {
    test('returns non-null layout with correct canvas dimensions', () {
      final layout = defaultScoreboardLayout(
        homeName: 'Home',
        awayName: 'Away',
      );

      // Authored at the firmware's native output (Variant A bug).
      expect(layout.canvasWidth, equals(1280));
      expect(layout.canvasHeight, equals(720));
    });

    test('layout contains the bug elements', () {
      final layout = defaultScoreboardLayout(
        homeName: 'Home',
        awayName: 'Away',
      );

      // bg, clock cell, two color tabs, home/away names, score, clock, period.
      expect(layout.elements, hasLength(9));
    });

    test('persistent elements include all required bindings', () {
      final layout = defaultScoreboardLayout(
        homeName: 'Home',
        awayName: 'Away',
      );

      final bindings = layout.elements.map((e) => e.binding).toList();
      expect(bindings, contains(OverlayBinding.teamAName));
      expect(bindings, contains(OverlayBinding.teamBName));
      expect(bindings, contains(OverlayBinding.scoreVs));
      expect(bindings, contains(OverlayBinding.periodLabel));
      expect(bindings, contains(OverlayBinding.matchClock));
    });

    test('persistent elements include at least one rect shape', () {
      final layout = defaultScoreboardLayout(
        homeName: 'Home',
        awayName: 'Away',
      );

      final shapes = layout.elements.map((e) => e.shape).toList();
      expect(shapes, contains(OverlayShape.rect));
    });

    test('layout contains exactly 4 templates', () {
      final layout = defaultScoreboardLayout(
        homeName: 'Home',
        awayName: 'Away',
      );

      expect(layout.templates, hasLength(4));
    });

    test('template eventTypes are correct', () {
      final layout = defaultScoreboardLayout(
        homeName: 'Home',
        awayName: 'Away',
      );

      final eventTypes = layout.templates.map((t) => t.eventType).toList();
      expect(
        eventTypes,
        containsAll(['goal', 'yellow_card', 'red_card', 'substitution']),
      );
    });

    test('goal template has durationMs == 5000', () {
      final layout = defaultScoreboardLayout(
        homeName: 'Home',
        awayName: 'Away',
      );

      final goal = layout.templates.firstWhere((t) => t.eventType == 'goal');
      expect(goal.durationMs, equals(5000));
    });

    test('yellow_card template has durationMs == 4000', () {
      final layout = defaultScoreboardLayout(
        homeName: 'Home',
        awayName: 'Away',
      );

      final t = layout.templates.firstWhere(
        (t) => t.eventType == 'yellow_card',
      );
      expect(t.durationMs, equals(4000));
    });

    test('red_card template has durationMs == 4000', () {
      final layout = defaultScoreboardLayout(
        homeName: 'Home',
        awayName: 'Away',
      );

      final t = layout.templates.firstWhere((t) => t.eventType == 'red_card');
      expect(t.durationMs, equals(4000));
    });

    test('substitution template has durationMs == 4000', () {
      final layout = defaultScoreboardLayout(
        homeName: 'Home',
        awayName: 'Away',
      );

      final t = layout.templates.firstWhere(
        (t) => t.eventType == 'substitution',
      );
      expect(t.durationMs, equals(4000));
    });

    test('null colors fall back to a neutral tab color', () {
      final layout = defaultScoreboardLayout(
        homeName: 'Home',
        awayName: 'Away',
        homeColorHex: null,
        awayColorHex: null,
      );

      // Team colors drive the end tabs (names are white for contrast).
      final homeTab = layout.elements.firstWhere((e) => e.id == 'home_tab');
      final awayTab = layout.elements.firstWhere((e) => e.id == 'away_tab');
      expect(homeTab.style.fillColor, equals('#9AA3B2'));
      expect(awayTab.style.fillColor, equals('#9AA3B2'));
    });

    test('provided colors are applied to the home and away tabs', () {
      final layout = defaultScoreboardLayout(
        homeName: 'Home FC',
        awayName: 'Away FC',
        homeColorHex: '#FF0000',
        awayColorHex: '#0000FF',
      );

      final homeTab = layout.elements.firstWhere((e) => e.id == 'home_tab');
      final awayTab = layout.elements.firstWhere((e) => e.id == 'away_tab');
      expect(homeTab.style.fillColor, equals('#FF0000'));
      expect(awayTab.style.fillColor, equals('#0000FF'));
    });
  });

  group('OverlayRect', () {
    test('constructs without error when x1 == x2 (degenerate rect)', () {
      const rect = OverlayRect(x1: 100, y1: 50, x2: 100, y2: 200, z: 0);
      expect(rect.x1, equals(rect.x2));
    });
  });

  group('OverlayLayout', () {
    test('is valid with empty elements and templates lists', () {
      const layout = OverlayLayout(
        canvasWidth: 1280,
        canvasHeight: 720,
        elements: [],
        templates: [],
      );

      expect(layout.elements, isEmpty);
      expect(layout.templates, isEmpty);
      expect(layout.canvasWidth, equals(1280));
      expect(layout.canvasHeight, equals(720));
    });
  });
}

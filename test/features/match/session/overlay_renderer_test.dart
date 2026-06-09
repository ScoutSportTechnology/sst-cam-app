// Tests for OverlayLayoutRenderer (U9 + U4 + U2 + U3).
//
// Covers:
//  1. Smoke test — pumps without throw
//  2. scoreVs binding renders '0 – 0'
//  3. teamAName binding renders home team name
//  4. periodLabel binding renders 'PRE' in initial state
//  5. matchClock binding renders initial clock text
//  6. Score update — scoreVs shows '1 – 0' after scoreHome=1
//  7. Null overlayLayout / empty layout renders without crash
//  8. RECT element renders a non-transparent Container
//  9. Invisible element not rendered
// 10. Banner timer — goal event shows then hides after durationMs
// 11. Banner timer — second banner cancels first
// 12. Uniform min(sx,sy) scale — Positioned.left matches el.x1 * min(sx,sy)
// 13. Inter fontFamily applied to TextStyle when OverlayStyle.fontFamily='Inter'
// 14. Null fontFamily produces TextStyle.fontFamily == null
// 15. {{param}} substitution — GOAL — Messi rendered with matching params
// 16. Missing param key replaced with empty string — GOAL —  rendered
// 17. Params cleared after banner timer expiry — substituted text disappears
// 18. Z-order sort — out-of-array higher-z element is rendered last (on top)
// 19. Z-order sort — banner template elements also sorted by z
// 20. SHAPE_CIRCLE on square bounds renders a CustomPaint (ellipse)
// 21. SHAPE_CIRCLE on non-square bounds fills the full width (ellipse, not clipped circle)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/models/overlay_layout.dart';
import 'package:sst_cam_app/features/match/session/overlay_renderer.dart';
import 'package:sst_cam_app/features/match/session/session_state.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 400, height: 200, child: child)),
);

OverlayLayout _defaultLayout() =>
    defaultScoreboardLayout(homeName: 'NR', awayName: 'EFC');

// A minimal layout with a single visible text element bound to scoreVs.
const _scoreVsLayout = OverlayLayout(
  canvasWidth: 1920,
  canvasHeight: 1080,
  elements: [
    OverlayElement(
      id: 'score',
      shape: OverlayShape.text,
      bounds: OverlayRect(x1: 760, y1: 960, x2: 1160, y2: 1050, z: 1),
      style: OverlayStyle(
        textColor: '#FFFFFF',
        textAlign: OverlayTextAlign.center,
        fontSize: 48,
        fontWeight: OverlayFontWeight.bold,
      ),
      binding: OverlayBinding.scoreVs,
    ),
  ],
  templates: [],
);

// A minimal layout with a single rect element.
const _rectLayout = OverlayLayout(
  canvasWidth: 1920,
  canvasHeight: 1080,
  elements: [
    OverlayElement(
      id: 'bg',
      shape: OverlayShape.rect,
      bounds: OverlayRect(x1: 0, y1: 950, x2: 1920, y2: 1080, z: 0),
      style: OverlayStyle(fillColor: '#111111', opacity: 0.85),
      binding: OverlayBinding.static,
    ),
  ],
  templates: [],
);

// A layout with one invisible text element.
const _invisibleLayout = OverlayLayout(
  canvasWidth: 1920,
  canvasHeight: 1080,
  elements: [
    OverlayElement(
      id: 'hidden',
      shape: OverlayShape.text,
      bounds: OverlayRect(x1: 0, y1: 0, x2: 400, y2: 100, z: 0),
      style: OverlayStyle(
        staticText: 'SHOULD NOT APPEAR',
        textColor: '#FFFFFF',
        fontSize: 24,
      ),
      binding: OverlayBinding.static,
      visible: false,
    ),
  ],
  templates: [],
);

// A layout with one text element that has fontFamily: 'Inter'.
const _interFontLayout = OverlayLayout(
  canvasWidth: 1920,
  canvasHeight: 1080,
  elements: [
    OverlayElement(
      id: 'label',
      shape: OverlayShape.text,
      bounds: OverlayRect(x1: 100, y1: 100, x2: 500, y2: 200, z: 1),
      style: OverlayStyle(
        staticText: 'FONT TEST',
        textColor: '#FFFFFF',
        fontSize: 24,
        fontFamily: 'Inter',
      ),
      binding: OverlayBinding.static,
    ),
  ],
  templates: [],
);

// A layout with one text element that has fontFamily: null (default).
const _nullFontLayout = OverlayLayout(
  canvasWidth: 1920,
  canvasHeight: 1080,
  elements: [
    OverlayElement(
      id: 'label',
      shape: OverlayShape.text,
      bounds: OverlayRect(x1: 100, y1: 100, x2: 500, y2: 200, z: 1),
      style: OverlayStyle(
        staticText: 'NULL FONT',
        textColor: '#FFFFFF',
        fontSize: 24,
      ),
      binding: OverlayBinding.static,
    ),
  ],
  templates: [],
);

// A layout with a goal template whose text uses a {{player}} token.
// The template eventType 'goal' is matched by _labelToTemplateId for 'Goal' prefix.
const _paramBannerLayout = OverlayLayout(
  canvasWidth: 1920,
  canvasHeight: 1080,
  elements: [],
  templates: [
    OverlayTemplate(
      eventType: 'goal',
      durationMs: 3000,
      elements: [
        OverlayElement(
          id: 'goal_text',
          shape: OverlayShape.text,
          bounds: OverlayRect(x1: 560, y1: 400, x2: 1360, y2: 550, z: 10),
          style: OverlayStyle(
            staticText: 'GOAL — {{player}}',
            textColor: '#000000',
            fontSize: 48,
            fontWeight: OverlayFontWeight.bold,
            textAlign: OverlayTextAlign.center,
          ),
          binding: OverlayBinding.static,
        ),
      ],
    ),
  ],
);

// Two RECT elements with z out of array order:
//   rectFront: z=2, x1=960 → should be rendered LAST (on top)
//   rectBack:  z=1, x1=0   → should be rendered FIRST (behind)
// Array order is [rectFront, rectBack] — reversed from z order.
const _zOrderLayout = OverlayLayout(
  canvasWidth: 1920,
  canvasHeight: 1080,
  elements: [
    OverlayElement(
      id: 'front',
      shape: OverlayShape.rect,
      bounds: OverlayRect(x1: 960, y1: 0, x2: 1920, y2: 100, z: 2),
      style: OverlayStyle(fillColor: '#FF0000'),
      binding: OverlayBinding.static,
    ),
    OverlayElement(
      id: 'back',
      shape: OverlayShape.rect,
      bounds: OverlayRect(x1: 0, y1: 0, x2: 960, y2: 100, z: 1),
      style: OverlayStyle(fillColor: '#0000FF'),
      binding: OverlayBinding.static,
    ),
  ],
  templates: [],
);

// Banner layout with two elements out of z order to test banner sort.
const _zOrderBannerLayout = OverlayLayout(
  canvasWidth: 1920,
  canvasHeight: 1080,
  elements: [],
  templates: [
    OverlayTemplate(
      eventType: 'goal',
      durationMs: 3000,
      elements: [
        OverlayElement(
          id: 'top',
          shape: OverlayShape.rect,
          bounds: OverlayRect(x1: 960, y1: 0, x2: 1920, y2: 100, z: 2),
          style: OverlayStyle(fillColor: '#FF0000'),
          binding: OverlayBinding.static,
        ),
        OverlayElement(
          id: 'bottom',
          shape: OverlayShape.rect,
          bounds: OverlayRect(x1: 0, y1: 0, x2: 960, y2: 100, z: 1),
          style: OverlayStyle(fillColor: '#0000FF'),
          binding: OverlayBinding.static,
        ),
      ],
    ),
  ],
);

// A square-bounds circle element.
const _circleSquareLayout = OverlayLayout(
  canvasWidth: 1920,
  canvasHeight: 1080,
  elements: [
    OverlayElement(
      id: 'dot',
      shape: OverlayShape.circle,
      bounds: OverlayRect(x1: 100, y1: 100, x2: 200, y2: 200, z: 1),
      style: OverlayStyle(fillColor: '#FF0000'),
      binding: OverlayBinding.static,
    ),
  ],
  templates: [],
);

// A non-square-bounds circle element (100 wide, 50 tall) — should render oval.
const _circleNonSquareLayout = OverlayLayout(
  canvasWidth: 1920,
  canvasHeight: 1080,
  elements: [
    OverlayElement(
      id: 'oval',
      shape: OverlayShape.circle,
      bounds: OverlayRect(x1: 100, y1: 100, x2: 200, y2: 150, z: 1),
      style: OverlayStyle(fillColor: '#00FF00'),
      binding: OverlayBinding.static,
    ),
  ],
  templates: [],
);

void main() {
  // ---- 1. Smoke test -------------------------------------------------------

  testWidgets('smoke test — renders without throw', (tester) async {
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _defaultLayout(),
          matchState: LiveMatchState.initial,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  // ---- 2. scoreVs binding --------------------------------------------------

  testWidgets('scoreVs binding renders "0 – 0"', (tester) async {
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _scoreVsLayout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );
    // Find the Text widget with the em-dash separated score.
    expect(find.text('0 – 0'), findsOneWidget);
  });

  // ---- 3. teamAName binding ------------------------------------------------

  testWidgets('teamAName binding renders home name', (tester) async {
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _defaultLayout(),
          matchState: LiveMatchState.initial,
        ),
      ),
    );
    // LiveMatchState.initial.homeName is 'NR'
    expect(find.text(LiveMatchState.initial.homeName), findsAtLeast(1));
  });

  // ---- 4. periodLabel binding ----------------------------------------------

  testWidgets('periodLabel binding renders "PRE" in initial state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _defaultLayout(),
          matchState: LiveMatchState.initial,
        ),
      ),
    );
    expect(find.text('PRE'), findsOneWidget);
  });

  // ---- 5. matchClock binding -----------------------------------------------

  testWidgets('matchClock binding renders initial clock text', (tester) async {
    final state = LiveMatchState.initial;
    await tester.pumpWidget(
      _wrap(OverlayLayoutRenderer(layout: _defaultLayout(), matchState: state)),
    );
    expect(find.text(state.clockText), findsAtLeast(1));
  });

  // ---- 6. Score update -----------------------------------------------------

  testWidgets('scoreVs shows "1 – 0" after scoreHome=1', (tester) async {
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _scoreVsLayout,
          matchState: LiveMatchState.initial.copyWith(scoreHome: 1),
        ),
      ),
    );
    expect(find.text('1 – 0'), findsOneWidget);
  });

  // ---- 7. Empty layout renders without crash --------------------------------

  testWidgets('empty layout renders without crash', (tester) async {
    const emptyLayout = OverlayLayout(
      canvasWidth: 1920,
      canvasHeight: 1080,
      elements: [],
      templates: [],
    );
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: emptyLayout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  // ---- 8. RECT element renders with non-transparent color ------------------

  testWidgets('RECT element renders a Container with non-transparent color', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _rectLayout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );
    // The rect element wraps in Opacity + Container with BoxDecoration.
    // Verify the Opacity widget exists (which wraps the rect element).
    expect(find.byType(Opacity), findsAtLeast(1));
    // Verify the Container with the color exists.
    final containers = tester.widgetList<Container>(find.byType(Container));
    final nonTransparent = containers.where((c) {
      final dec = c.decoration;
      if (dec is BoxDecoration) {
        final color = dec.color;
        return color != null && color != Colors.transparent;
      }
      return false;
    });
    expect(nonTransparent, isNotEmpty);
  });

  // ---- 9. Invisible element not rendered -----------------------------------

  testWidgets('invisible element is not in the widget tree', (tester) async {
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _invisibleLayout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );
    expect(find.text('SHOULD NOT APPEAR'), findsNothing);
  });

  // ---- 10. Banner timer — goal shows then hides ----------------------------

  testWidgets('goal event shows banner then hides after durationMs', (
    tester,
  ) async {
    // Goal template durationMs is 5000 in defaultScoreboardLayout.
    final layout = _defaultLayout();

    // Initial state — no events.
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: layout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );
    // 'GOAL!' text from the goal banner template should not be visible yet.
    expect(find.text('GOAL!'), findsNothing);

    // Pump updated widget with a new Goal event prepended.
    final stateWithGoal = LiveMatchState.initial.copyWith(
      events: const [LiveEvent(clock: '00:01', label: 'Goal · NR')],
    );
    await tester.pumpWidget(
      _wrap(OverlayLayoutRenderer(layout: layout, matchState: stateWithGoal)),
    );
    await tester.pump(); // Allow setState from didUpdateWidget to settle.

    // Banner should now be visible.
    expect(find.text('GOAL!'), findsOneWidget);

    // Advance past durationMs (5000ms).
    await tester.pump(const Duration(milliseconds: 5001));

    // Banner should be gone.
    expect(find.text('GOAL!'), findsNothing);
  });

  // ---- 11. Banner timer — second banner cancels first ----------------------

  testWidgets('second banner cancels first timer and shows new banner', (
    tester,
  ) async {
    final layout = _defaultLayout();

    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: layout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );

    // Pump a Goal event.
    final stateWithGoal = LiveMatchState.initial.copyWith(
      events: const [LiveEvent(clock: '00:01', label: 'Goal · NR')],
    );
    await tester.pumpWidget(
      _wrap(OverlayLayoutRenderer(layout: layout, matchState: stateWithGoal)),
    );
    await tester.pump();
    expect(find.text('GOAL!'), findsOneWidget);

    // Advance only 2000ms — goal timer still running (5000ms total).
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('GOAL!'), findsOneWidget);

    // Pump a Yellow Card event (prepended in front of Goal event).
    final stateWithYellowCard = LiveMatchState.initial.copyWith(
      events: const [
        LiveEvent(clock: '00:03', label: 'Yellow Card · NR'),
        LiveEvent(clock: '00:01', label: 'Goal · NR'),
      ],
    );
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(layout: layout, matchState: stateWithYellowCard),
      ),
    );
    await tester.pump();

    // Yellow card banner should be visible; goal banner should be gone.
    expect(find.text('YELLOW CARD'), findsOneWidget);
    expect(find.text('GOAL!'), findsNothing);

    // Advance past yellow card durationMs (4000ms).
    await tester.pump(const Duration(milliseconds: 4001));

    // No banner should be shown.
    expect(find.text('YELLOW CARD'), findsNothing);
    expect(find.text('GOAL!'), findsNothing);
  });

  // ---- 12. Uniform min(sx,sy) scale ----------------------------------------

  testWidgets('Positioned.left matches el.x1 * min(sx, sy)', (tester) async {
    // _scoreVsLayout: canvasWidth=1920, canvasHeight=1080.
    // _wrap gives SizedBox(400, 200).
    // sx = 400/1920 ≈ 0.2083, sy = 200/1080 ≈ 0.1852 → s = min = 0.1852...
    // Element x1 = 760 → left = 760 * 0.1852 ≈ 140.74
    const expectedS = 200.0 / 1080.0; // min(400/1920, 200/1080)
    const elementX1 = 760.0;
    const expectedLeft = elementX1 * expectedS;

    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _scoreVsLayout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );

    final positioned = tester.widget<Positioned>(find.byType(Positioned).first);
    expect(positioned.left, closeTo(expectedLeft, 0.1));
  });

  // ---- 13. Inter fontFamily applied to TextStyle ---------------------------

  testWidgets('Inter fontFamily produces TextStyle.fontFamily == "Inter"', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _interFontLayout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('FONT TEST'));
    expect(text.style?.fontFamily, equals('Inter'));
  });

  // ---- 14. Null fontFamily produces TextStyle.fontFamily == null ------------

  testWidgets('null fontFamily produces TextStyle.fontFamily == null', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _nullFontLayout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('NULL FONT'));
    expect(text.style?.fontFamily, isNull);
  });

  // ---- 15. {{param}} substitution — happy path -----------------------------

  testWidgets('param substitution renders "GOAL — Messi"', (tester) async {
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _paramBannerLayout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );

    // Fire a Goal event with player param.
    final stateWithGoal = LiveMatchState.initial.copyWith(
      events: const [
        LiveEvent(
          clock: '01:00',
          label: 'Goal · NR',
          params: {'player': 'Messi'},
        ),
      ],
    );
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _paramBannerLayout,
          matchState: stateWithGoal,
        ),
      ),
    );
    await tester.pump(); // settle didUpdateWidget setState

    expect(find.text('GOAL — Messi'), findsOneWidget);
  });

  // ---- 16. Missing param key replaced with empty string --------------------

  testWidgets('missing param key replaced with empty string', (tester) async {
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _paramBannerLayout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );

    // Fire a Goal event with no params — {{player}} has no matching key.
    final stateWithGoal = LiveMatchState.initial.copyWith(
      events: const [LiveEvent(clock: '01:00', label: 'Goal · NR')],
    );
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _paramBannerLayout,
          matchState: stateWithGoal,
        ),
      ),
    );
    await tester.pump(); // settle didUpdateWidget setState

    // {{player}} with no key → empty string → 'GOAL — '
    expect(find.text('GOAL — '), findsOneWidget);
  });

  // ---- 17. Params cleared after banner timer expiry ------------------------

  testWidgets('substituted text disappears after banner timer expires', (
    tester,
  ) async {

    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _paramBannerLayout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );

    // Fire a Goal event with player param.
    final stateWithGoal = LiveMatchState.initial.copyWith(
      events: const [
        LiveEvent(
          clock: '01:00',
          label: 'Goal · NR',
          params: {'player': 'Ronaldo'},
        ),
      ],
    );
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _paramBannerLayout,
          matchState: stateWithGoal,
        ),
      ),
    );
    await tester.pump(); // settle

    // Substituted text is visible during durationMs (3000ms).
    expect(find.text('GOAL — Ronaldo'), findsOneWidget);

    // Advance past durationMs (3000ms).
    await tester.pump(const Duration(milliseconds: 3001));

    // Banner is gone — substituted text no longer visible.
    expect(find.text('GOAL — Ronaldo'), findsNothing);
  });

  // ---- 18. Z-order sort — persistent elements ------------------------------

  testWidgets('higher-z element (array index 0) is rendered last in Stack', (
    tester,
  ) async {
    // _zOrderLayout has [front(z=2, x1=960), back(z=1, x1=0)] in array.
    // After z-sort: [back(z=1, x1=0), front(z=2, x1=960)].
    // Stack children: index 0 = back (left≈0), index 1 = front (left≈960*s).
    const s = 200.0 / 1080.0; // min(400/1920, 200/1080)
    const frontLeft = 960.0 * s;

    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _zOrderLayout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );

    final positioneds =
        tester.widgetList<Positioned>(find.byType(Positioned)).toList();
    expect(positioneds.length, 2);
    // First child in Stack = lower z = back (x1=0 → left≈0).
    expect(positioneds[0].left, closeTo(0.0, 0.1));
    // Second child in Stack = higher z = front (x1=960 → left≈frontLeft).
    expect(positioneds[1].left, closeTo(frontLeft, 0.1));
  });

  // ---- 19. Z-order sort — banner template elements -------------------------

  testWidgets('banner template elements are also sorted by z', (tester) async {
    // _zOrderBannerLayout: banner has [top(z=2, x1=960), bottom(z=1, x1=0)].
    // After z-sort: [bottom(z=1, x1=0), top(z=2, x1=960)].
    const s = 200.0 / 1080.0;
    const topLeft = 960.0 * s;

    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _zOrderBannerLayout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );

    // Fire a goal event to activate the banner.
    final stateWithGoal = LiveMatchState.initial.copyWith(
      events: const [LiveEvent(clock: '01:00', label: 'Goal · NR')],
    );
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _zOrderBannerLayout,
          matchState: stateWithGoal,
        ),
      ),
    );
    await tester.pump();

    final positioneds =
        tester.widgetList<Positioned>(find.byType(Positioned)).toList();
    expect(positioneds.length, 2);
    expect(positioneds[0].left, closeTo(0.0, 0.1));
    expect(positioneds[1].left, closeTo(topLeft, 0.1));
  });

  // ---- 20. SHAPE_CIRCLE renders via CustomPaint (not BoxShape.circle) ------

  testWidgets('SHAPE_CIRCLE child is CustomPaint, not a BoxShape.circle Container', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _circleSquareLayout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    // The Positioned child for the circle element must be Opacity wrapping CustomPaint.
    final positioned = tester.widget<Positioned>(find.byType(Positioned).first);
    expect(positioned.child, isA<Opacity>());
    expect((positioned.child as Opacity).child, isA<CustomPaint>());

    // Must NOT be a Container with BoxShape.circle (old incorrect implementation).
    final containers = tester.widgetList<Container>(find.byType(Container));
    final circleContainers = containers.where((c) {
      final dec = c.decoration;
      return dec is BoxDecoration && dec.shape == BoxShape.circle;
    });
    expect(circleContainers, isEmpty);
  });

  // ---- 21. SHAPE_CIRCLE on non-square bounds fills full width --------------

  testWidgets('SHAPE_CIRCLE non-square bounds: Positioned width > height', (
    tester,
  ) async {
    // bounds x1=100, x2=200, y1=100, y2=150 → width=100, height=50.
    // Positioned width should be 100*s, height should be 50*s (s = 200/1080).
    const s = 200.0 / 1080.0;
    const expectedWidth = 100.0 * s;
    const expectedHeight = 50.0 * s;

    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _circleNonSquareLayout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );

    final positioned = tester.widget<Positioned>(
      find.byType(Positioned).first,
    );
    expect(positioned.width, closeTo(expectedWidth, 0.1));
    expect(positioned.height, closeTo(expectedHeight, 0.1));
    // Width should be wider than height — confirming the oval uses full bounds.
    expect(positioned.width!, greaterThan(positioned.height!));
  });

  // ---- 22. U6 — text fill_color renders a background box -------------------

  testWidgets('text element with fill_color renders a background box + text', (
    tester,
  ) async {
    const layout = OverlayLayout(
      canvasWidth: 1920,
      canvasHeight: 1080,
      elements: [
        OverlayElement(
          id: 'labelled',
          shape: OverlayShape.text,
          bounds: OverlayRect(x1: 100, y1: 100, x2: 500, y2: 200, z: 1),
          style: OverlayStyle(
            staticText: 'BG BOX',
            fillColor: '#222222',
            textColor: '#FFFFFF',
            fontSize: 24,
          ),
          binding: OverlayBinding.static,
        ),
      ],
      templates: [],
    );

    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: layout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );

    // The text still renders.
    expect(find.text('BG BOX'), findsOneWidget);

    // A DecoratedBox with the non-transparent fill color must back the glyphs.
    final decoratedBoxes = tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    );
    final filled = decoratedBoxes.where((d) {
      final dec = d.decoration;
      return dec is BoxDecoration &&
          dec.color != null &&
          dec.color != Colors.transparent;
    });
    expect(filled, isNotEmpty);
  });

  // ---- 23. U6 — text without fill_color renders no background box ----------

  testWidgets('text element without fill_color paints no background box', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: _interFontLayout, // no fillColor
          matchState: LiveMatchState.initial,
        ),
      ),
    );
    expect(find.text('FONT TEST'), findsOneWidget);
    // No DecoratedBox with a non-transparent color from the text element.
    final decoratedBoxes = tester.widgetList<DecoratedBox>(
      find.byType(DecoratedBox),
    );
    final filled = decoratedBoxes.where((d) {
      final dec = d.decoration;
      return dec is BoxDecoration &&
          dec.color != null &&
          dec.color != Colors.transparent;
    });
    expect(filled, isEmpty);
  });

  // ---- 24. U6 — corner_radius clamped to half the smaller side ------------

  testWidgets('corner_radius larger than half smaller side is clamped', (
    tester,
  ) async {
    // bounds 100x40 → smaller side 40 → max radius 20 (canvas px).
    // cornerRadius 999 must clamp to 20, then scale by s.
    const s = 200.0 / 1080.0;
    const expectedRadius = 20.0 * s;
    const layout = OverlayLayout(
      canvasWidth: 1920,
      canvasHeight: 1080,
      elements: [
        OverlayElement(
          id: 'capsule',
          shape: OverlayShape.rect,
          bounds: OverlayRect(x1: 0, y1: 0, x2: 100, y2: 40, z: 1),
          style: OverlayStyle(fillColor: '#FF0000', cornerRadius: 999),
          binding: OverlayBinding.static,
        ),
      ],
      templates: [],
    );

    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: layout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );

    final container = tester.widgetList<Container>(find.byType(Container)).where(
      (c) {
        final dec = c.decoration;
        return dec is BoxDecoration && dec.borderRadius != null;
      },
    ).first;
    final dec = container.decoration as BoxDecoration;
    final radius = (dec.borderRadius as BorderRadius).topLeft.x;
    expect(radius, closeTo(expectedRadius, 0.5));
  });

  // ---- 25. U6 — corner_radius within bounds is not clamped -----------------

  testWidgets('corner_radius within half smaller side is preserved', (
    tester,
  ) async {
    // bounds 200x200 → max radius 100. cornerRadius 10 stays 10 (scaled).
    const s = 200.0 / 1080.0;
    const expectedRadius = 10.0 * s;
    const layout = OverlayLayout(
      canvasWidth: 1920,
      canvasHeight: 1080,
      elements: [
        OverlayElement(
          id: 'rounded',
          shape: OverlayShape.rect,
          bounds: OverlayRect(x1: 0, y1: 0, x2: 200, y2: 200, z: 1),
          style: OverlayStyle(fillColor: '#00FF00', cornerRadius: 10),
          binding: OverlayBinding.static,
        ),
      ],
      templates: [],
    );

    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: layout,
          matchState: LiveMatchState.initial,
        ),
      ),
    );

    final container = tester.widgetList<Container>(find.byType(Container)).where(
      (c) {
        final dec = c.decoration;
        return dec is BoxDecoration && dec.borderRadius != null;
      },
    ).first;
    final dec = container.decoration as BoxDecoration;
    final radius = (dec.borderRadius as BorderRadius).topLeft.x;
    expect(radius, closeTo(expectedRadius, 0.5));
  });
}

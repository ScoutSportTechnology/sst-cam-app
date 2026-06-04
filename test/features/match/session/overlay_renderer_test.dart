// Tests for OverlayLayoutRenderer (U9).
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

OverlayLayout _defaultLayout() => defaultScoreboardLayout(
      homeName: 'NR',
      awayName: 'EFC',
    );

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

  testWidgets('periodLabel binding renders "PRE" in initial state',
      (tester) async {
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
      _wrap(
        OverlayLayoutRenderer(
          layout: _defaultLayout(),
          matchState: state,
        ),
      ),
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

  testWidgets('RECT element renders a Container with non-transparent color',
      (tester) async {
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

  testWidgets('goal event shows banner then hides after durationMs',
      (tester) async {
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
      events: const [
        LiveEvent(clock: '00:01', label: 'Goal · NR'),
      ],
    );
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: layout,
          matchState: stateWithGoal,
        ),
      ),
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

  testWidgets('second banner cancels first timer and shows new banner',
      (tester) async {
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
      events: const [
        LiveEvent(clock: '00:01', label: 'Goal · NR'),
      ],
    );
    await tester.pumpWidget(
      _wrap(
        OverlayLayoutRenderer(
          layout: layout,
          matchState: stateWithGoal,
        ),
      ),
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
        OverlayLayoutRenderer(
          layout: layout,
          matchState: stateWithYellowCard,
        ),
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
}

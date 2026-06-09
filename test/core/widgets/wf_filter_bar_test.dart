// Widget tests for WfFilterBar and FilterSpec.
//
// Verifies the generic contract:
//   - One picker button rendered per FilterSpec
//   - Inactive button shows the spec's label ("All sports")
//   - Active button shows the selected value ("Soccer")
//   - Tapping a button opens a bottom sheet with options + "All" at the top
//   - Selecting an option calls onSelect and closes the sheet
//   - Selecting "All" calls onSelect(null)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/widgets/wf_filter_bar.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('WfFilterBar', () {
    testWidgets('renders a picker button per FilterSpec', (tester) async {
      await tester.pumpWidget(
        _wrap(
          WfFilterBar(
            filters: [
              FilterSpec(
                label: 'All sports',
                options: const ['Soccer'],
                selected: null,
                onSelect: (_) {},
              ),
              FilterSpec(
                label: 'All teams',
                options: const ['Team A'],
                selected: null,
                onSelect: (_) {},
              ),
            ],
          ),
        ),
      );

      expect(find.text('All sports'), findsOneWidget);
      expect(find.text('All teams'), findsOneWidget);
    });

    testWidgets('inactive button shows label; active shows selected value', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          WfFilterBar(
            filters: [
              FilterSpec(
                label: 'All sports',
                options: const ['Soccer', 'Basketball'],
                selected: 'Soccer',
                onSelect: (_) {},
              ),
            ],
          ),
        ),
      );

      // Button label is the selected value, not the category label.
      expect(find.text('Soccer'), findsOneWidget);
      expect(find.text('All sports'), findsNothing);
    });

    testWidgets('tapping button opens sheet with options + "All"', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          WfFilterBar(
            filters: [
              FilterSpec(
                label: 'All sports',
                options: const ['Soccer', 'Basketball'],
                selected: null,
                onSelect: (_) {},
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('All sports'));
      await tester.pumpAndSettle();

      // Sheet shows "All" plus each option.
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Soccer'), findsOneWidget);
      expect(find.text('Basketball'), findsOneWidget);
    });

    testWidgets('selecting an option calls onSelect with that value', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      String? captured;
      await tester.pumpWidget(
        _wrap(
          WfFilterBar(
            filters: [
              FilterSpec(
                label: 'All sports',
                options: const ['Soccer'],
                selected: null,
                onSelect: (v) => captured = v,
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('All sports'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Soccer'));
      await tester.pumpAndSettle();

      expect(captured, equals('Soccer'));
    });

    testWidgets('selecting "All" calls onSelect with null', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      String? captured = 'initial';
      await tester.pumpWidget(
        _wrap(
          WfFilterBar(
            filters: [
              FilterSpec(
                label: 'All sports',
                options: const ['Soccer'],
                selected: 'Soccer',
                onSelect: (v) => captured = v,
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('Soccer')); // opens sheet
      await tester.pumpAndSettle();
      await tester.tap(find.text('All')); // clears filter
      await tester.pumpAndSettle();

      expect(captured, isNull);
    });
  });
}

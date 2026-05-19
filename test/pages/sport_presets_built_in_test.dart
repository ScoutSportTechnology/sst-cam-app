// U6 — SportPresetsPage built-in visual treatment + sport coverage tests.
//
// SportPresetsController is now backed by Drift. Tests use `useInMemoryDb()`
// for isolation and `dbOverrides(db)` to wire the in-memory database into the
// ProviderScope. No BleService or DevDataStore references remain.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/pages/sport_presets_page.dart';
import 'package:sst_cam_app/state/app_data.dart';
import 'package:sst_cam_app/widgets/wf_card.dart';
import 'package:sst_cam_app/widgets/wf_chip.dart';

import '../test_helpers.dart';

void main() {
  SharedPreferences.setMockInitialValues({'active_user_id': 'user-1'});
  final db = useInMemoryDb();

  Widget buildHarness() {
    return ProviderScope(
      overrides: [
        ...dbOverrides(db),
        activeUserProvider.overrideWith((_) => 'user-1'),
      ],
      child: const MaterialApp(home: SportPresetsPage()),
    );
  }

  group('Built-in row treatment (AE5)', () {
    testWidgets('Soccer · Standard and Soccer · Youth (U14) render at the top '
        'of the Soccer group with no edit/delete affordance; a custom soccer '
        'preset renders below them with both affordances', (tester) async {
      // Add a custom soccer preset so we can verify ordering and the
      // delete affordance is rendered for non-builtin rows.
      await db.value.sportPresetsDao.insertPreset(
        SportPresetsTableCompanion.insert(
          id: 'custom-soccer-01',
          userId: 'user-1',
          name: 'Soccer · Custom',
          sport: 'Soccer',
          numPeriods: 2,
          periodLengthSeconds: 30 * 60,
        ),
      );

      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      // Soccer group header is present (filter chip also shows "Soccer").
      expect(
        find.byWidgetPredicate((w) => w is WfSection && w.label == 'Soccer'),
        findsOneWidget,
      );

      // The two built-in soccer presets render.
      final standardFinder = find.text('Soccer · Standard');
      final youthFinder = find.text('Soccer · Youth (U14)');
      final customFinder = find.text('Soccer · Custom');
      expect(standardFinder, findsOneWidget);
      expect(youthFinder, findsOneWidget);
      expect(customFinder, findsOneWidget);

      // Built-ins render at the top of the Soccer group: their dy must be
      // less than the custom row's dy.
      final standardDy = tester.getTopLeft(standardFinder).dy;
      final youthDy = tester.getTopLeft(youthFinder).dy;
      final customDy = tester.getTopLeft(customFinder).dy;
      expect(standardDy, lessThan(customDy));
      expect(youthDy, lessThan(customDy));

      // The two built-in rows have NO IconButton (delete) descendant. The
      // edit affordance is the InkWell tap; for built-ins the InkWell has
      // `onTap == null` (verified via Widget lookup).
      for (final finder in <Finder>[standardFinder, youthFinder]) {
        final rowInkWell = find.ancestor(
          of: finder,
          matching: find.byType(InkWell),
        );
        expect(rowInkWell, findsOneWidget);
        final inkwell = tester.widget<InkWell>(rowInkWell);
        expect(
          inkwell.onTap,
          isNull,
          reason: 'Built-in rows must not have an edit affordance.',
        );
        // No delete icon nested in the row.
        final delete = find.descendant(
          of: rowInkWell,
          matching: find.byIcon(Icons.delete_outline),
        );
        expect(delete, findsNothing);
        // The "Default" chip is rendered as a leading badge.
        final chip = find.descendant(
          of: rowInkWell,
          matching: find.byWidgetPredicate(
            (w) => w is WfChip && w.label == 'Default',
          ),
        );
        expect(chip, findsOneWidget);
      }

      // Custom soccer row HAS both affordances (InkWell.onTap is non-null
      // and a delete icon is in its subtree).
      final customRow = find.ancestor(
        of: customFinder,
        matching: find.byType(InkWell),
      );
      expect(customRow, findsOneWidget);
      final customInkWell = tester.widget<InkWell>(customRow);
      expect(customInkWell.onTap, isNotNull);
      final customDelete = find.descendant(
        of: customRow,
        matching: find.byIcon(Icons.delete_outline),
      );
      expect(customDelete, findsOneWidget);
      // Custom rows do NOT carry the "Default" chip.
      final customChip = find.descendant(
        of: customRow,
        matching: find.byWidgetPredicate(
          (w) => w is WfChip && w.label == 'Default',
        ),
      );
      expect(customChip, findsNothing);
    });
  });

  group('Sport coverage', () {
    testWidgets('every entry in kSports has at least one built-in preset '
        'row in the page after seed', (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      // The page has pinned filter chips + a scrollable preset list.
      // Filter chips and section headers share sport name text, so we
      // check findsAtLeastNWidgets(1) rather than findsOneWidget.
      final presets = await db.value.sportPresetsDao.getForUser('user-1');
      for (final sport in kSports) {
        // Scroll using the section-header WfSection widget. Use scrollable:
        // param to target the preset ListView specifically so the pinned
        // filter chip row doesn't interfere.
        await tester.scrollUntilVisible(
          find.byWidgetPredicate((w) => w is WfSection && w.label == sport),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        expect(
          find.text(sport),
          findsAtLeastNWidgets(1),
          reason: 'Group header for "$sport" should be rendered.',
        );
        final hasBuiltIn = presets.any((p) => p.sport == sport && p.builtIn);
        expect(
          hasBuiltIn,
          isTrue,
          reason: '"$sport" should have at least one built-in preset.',
        );
      }
    });
  });

  group('Group with only built-ins still renders', () {
    testWidgets('Volleyball group renders its header and built-in row even '
        'with no custom preset', (tester) async {
      await tester.pumpWidget(buildHarness());
      await tester.pumpAndSettle();

      // "Volleyball" appears as both a filter chip and a section header.
      expect(
        find.byWidgetPredicate(
          (w) => w is WfSection && w.label == 'Volleyball',
        ),
        findsOneWidget,
      );
      expect(find.text('Volleyball · 5-set'), findsOneWidget);

      // Built-in row has no delete affordance and a "Default" chip leading.
      final row = find.ancestor(
        of: find.text('Volleyball · 5-set'),
        matching: find.byType(InkWell),
      );
      expect(row, findsOneWidget);
      final delete = find.descendant(
        of: row,
        matching: find.byIcon(Icons.delete_outline),
      );
      expect(delete, findsNothing);
      final chip = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (w) => w is WfChip && w.label == 'Default',
        ),
      );
      expect(chip, findsOneWidget);
    });
  });

  group('Sport filter chips (AE6)', () {
    testWidgets(
      'selecting Soccer shows only soccer rows; All restores all groups',
      (tester) async {
        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        // Tap the Soccer filter chip (not a section header WfSection).
        final soccerChip = find.byWidgetPredicate(
          (w) => w is WfChip && w.label == 'Soccer',
        );
        expect(soccerChip, findsOneWidget);
        await tester.tap(soccerChip);
        await tester.pumpAndSettle();

        // Soccer rows are visible.
        expect(find.text('Soccer · Standard'), findsOneWidget);
        // Non-soccer section headers are gone.
        expect(
          find.byWidgetPredicate(
            (w) => w is WfSection && w.label == 'Basketball',
          ),
          findsNothing,
        );

        // Tap "All" to restore all groups.
        await tester.tap(
          find.byWidgetPredicate((w) => w is WfChip && w.label == 'All'),
        );
        await tester.pumpAndSettle();

        // Basketball section header returns.
        expect(
          find.byWidgetPredicate(
            (w) => w is WfSection && w.label == 'Basketball',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('Bypass-controller delete throws', () {
    test('deleting a built-in preset via SportPresetsController throws '
        'a SportPresetsControllerException', () async {
      final presets = await db.value.sportPresetsDao.getForUser('user-1');
      final builtIn = presets.firstWhere((p) => p.builtIn);
      // Create a ProviderContainer with the in-memory DB and active user.
      final container = ProviderContainer(
        overrides: [
          ...dbOverrides(db),
          activeUserProvider.overrideWith((_) => 'user-1'),
        ],
      );
      addTearDown(container.dispose);

      // Build the controller state.
      await container.read(sportPresetsControllerProvider.future);

      expect(
        () => container
            .read(sportPresetsControllerProvider.notifier)
            .delete(builtIn.id),
        throwsA(isA<SportPresetsControllerException>()),
      );
    });
  });
}

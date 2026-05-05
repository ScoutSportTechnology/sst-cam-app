// U10 — SportPresetsPage built-in visual treatment + sport coverage tests.
//
// We pump SportPresetsPage directly under a ProviderScope with
// `bleServiceProvider` overridden to a fresh `MockBleService` and the
// `activeCameraIdProvider` set so `listSportPresets` resolves to the seed
// active user (`user-1`). Test isolation is automatic via
// `useDevDataStoreReset()`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/ble/dev_data_store.dart';
import 'package:scout_camera/ble/mock_ble_service.dart';
import 'package:scout_camera/pages/sport_presets_page.dart';
import 'package:scout_camera/state/app_data.dart';
import 'package:scout_camera/state/ble_providers.dart';
import 'package:scout_camera/widgets/wf_chip.dart';

import '../test_helpers.dart';

const String _kFakeDeviceId = 'SST-CAM-001';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 1,
);

Widget _buildHarness({required MockBleService service}) {
  return ProviderScope(
    overrides: [
      bleServiceProvider.overrideWithValue(service),
      activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
      activeUserProvider.overrideWith((_) => 'user-1'),
    ],
    child: const MaterialApp(home: SportPresetsPage()),
  );
}

void main() {
  useDevDataStoreReset();

  group('Built-in row treatment (AE5)', () {
    testWidgets('Soccer · Standard and Soccer · Youth (U14) render at the top '
        'of the Soccer group with no edit/delete affordance; a custom soccer '
        'preset renders below them with both affordances', (tester) async {
      // Add a custom soccer preset so we can verify ordering and the
      // delete affordance is rendered for non-builtin rows.
      DevDataStore.instance.createSportPreset(
        'user-1',
        const SportPresetDraft(
          name: 'Soccer · Custom',
          sport: 'Soccer',
          numPeriods: 2,
          periodLengthSeconds: 30 * 60,
        ),
      );

      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      // Soccer group header is present.
      expect(find.text('Soccer'), findsOneWidget);

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
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      // The page is a ListView of (header, rows...). Some entries may be
      // below the fold; scroll to ensure each header is realized in the
      // tree. For each kSports entry we assert: (a) the group header text
      // is reachable in the tree (after scrolling), and (b) the
      // DevDataStore has at least one builtIn preset for that sport.
      final presets = DevDataStore.instance.listSportPresets('user-1');
      for (final sport in kSports) {
        await tester.scrollUntilVisible(find.text(sport), 200);
        expect(
          find.text(sport),
          findsOneWidget,
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
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock));
      await tester.pumpAndSettle();

      expect(find.text('Volleyball'), findsOneWidget);
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

  group('Bypass-controller delete throws', () {
    test('deleting a built-in preset directly via DevDataStore throws '
        'a DevDataStoreException', () {
      final builtIn = DevDataStore.instance
          .listSportPresets('user-1')
          .firstWhere((p) => p.builtIn);
      expect(
        () => DevDataStore.instance.deleteSportPreset('user-1', builtIn.id),
        throwsA(isA<DevDataStoreException>()),
      );
    });
  });
}

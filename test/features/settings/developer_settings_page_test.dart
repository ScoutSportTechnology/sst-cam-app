import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/config/dev_config.dart';
import 'package:sst_cam_app/features/settings/developer/developer_settings_page.dart';
import 'package:sst_cam_app/features/settings/developer/developer_settings_state.dart';

Widget _page({DevConfig activeConfig = const DevConfig()}) {
  return ProviderScope(
    overrides: [devConfigProvider.overrideWithValue(activeConfig)],
    child: const MaterialApp(home: DeveloperSettingsPage()),
  );
}

/// Pump the page on a tall surface so every control (the switches, the bottom
/// "Close & restart" button) is on-screen and hit-testable. With the default
/// 800×600 the lower controls fall below the fold under CI font metrics and
/// taps miss them ("widget is off-screen").
Future<void> _pumpPage(
  WidgetTester tester, {
  DevConfig activeConfig = const DevConfig(),
}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_page(activeConfig: activeConfig));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('DeveloperSettingsPage', () {
    testWidgets('renders seed data and camera switches (no mode chips)', (
      tester,
    ) async {
      await _pumpPage(tester);

      expect(find.byKey(const Key('seedDataSwitch')), findsOneWidget);
      expect(find.byKey(const Key('cameraEmulationSwitch')), findsOneWidget);
      expect(find.byKey(const Key('previewBaseField')), findsOneWidget);
      expect(find.byKey(const Key('downloadBaseField')), findsOneWidget);
      expect(find.text('Full'), findsNothing);
      expect(find.text('Seed only'), findsNothing);
      expect(find.text('Empty'), findsNothing);
    });

    testWidgets(
      'editing the download base commits and shows the restart indicator',
      (tester) async {
        await _pumpPage(tester);

        expect(find.text('Restart to apply'), findsNothing);

        await tester.enterText(
          find.byKey(const Key('downloadBaseField')),
          'https://mws.domain',
        );
        // Commit on focus loss.
        await tester.tap(find.byKey(const Key('seedDataSwitch')));
        await tester.pumpAndSettle();

        expect(find.text('Restart to apply'), findsOneWidget);
      },
    );

    testWidgets(
      'toggling seed data shows restart indicator when active is seeded',
      (tester) async {
        const active = DevConfig(seedData: true);
        await _pumpPage(tester, activeConfig: active);

        // No indicator initially
        expect(find.text('Restart to apply'), findsNothing);

        await tester.tap(find.byKey(const Key('seedDataSwitch')));
        await tester.pumpAndSettle();

        expect(find.text('Restart to apply'), findsOneWidget);
      },
    );

    testWidgets('toggling camera emulation shows restart indicator', (
      tester,
    ) async {
      const active = DevConfig(cameraEmulation: true);
      await _pumpPage(tester, activeConfig: active);

      expect(find.text('Restart to apply'), findsNothing);

      await tester.tap(find.byKey(const Key('cameraEmulationSwitch')));
      await tester.pumpAndSettle();

      expect(find.text('Restart to apply'), findsOneWidget);
    });

    testWidgets(
      'no restart indicator when staged config matches active config',
      (tester) async {
        await _pumpPage(tester);

        expect(find.text('Restart to apply'), findsNothing);
      },
    );

    testWidgets('close button is disabled when no pending changes', (
      tester,
    ) async {
      await _pumpPage(tester);

      // No pending changes → button disabled (onPressed == null)
      final button = find.text('Close & restart');
      expect(button, findsOneWidget);

      // Tap should be no-op (no dialog shown)
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets(
      'close button shows confirmation dialog when changes are pending',
      (tester) async {
        await _pumpPage(tester);

        // Make a change to enable the button
        await tester.tap(find.byKey(const Key('seedDataSwitch')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Close & restart'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Restart app?'), findsOneWidget);
      },
    );

    testWidgets('Cancel in restart dialog closes dialog without restarting', (
      tester,
    ) async {
      await _pumpPage(tester);

      await tester.tap(find.byKey(const Key('seedDataSwitch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close & restart'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(DeveloperSettingsPage), findsOneWidget);
    });

    testWidgets('confirming restart after the page is popped does not throw '
        '(mounted guard)', (tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [devConfigProvider.overrideWithValue(const DevConfig())],
          child: MaterialApp(
            navigatorKey: navKey,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DeveloperSettingsPage(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Make a change so the restart button is enabled, then open the dialog.
      await tester.tap(find.byKey(const Key('seedDataSwitch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close & restart'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Pop the underlying DeveloperSettingsPage route out from under the
      // dialog, then confirm. The mounted guard must swallow this safely
      // (SystemNavigator.pop would otherwise fire on a disposed widget).
      navKey.currentState!.removeRoute(
        ModalRoute.of(tester.element(find.byType(DeveloperSettingsPage)))!,
      );
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('DeveloperSettingsNotifier', () {
    test('setPreviewBase coerces an empty string to the default', () async {
      final container = ProviderContainer(
        overrides: [devConfigProvider.overrideWithValue(const DevConfig())],
      );
      addTearDown(container.dispose);

      await container
          .read(developerSettingsProvider.notifier)
          .setPreviewBase('');

      final staged = container.read(developerSettingsProvider).stagedConfig;
      expect(staged.previewBaseUrl, DevConfig.defaults.previewBaseUrl);
    });

    test('setDownloadBase coerces an empty string to the default', () async {
      final container = ProviderContainer(
        overrides: [devConfigProvider.overrideWithValue(const DevConfig())],
      );
      addTearDown(container.dispose);

      await container
          .read(developerSettingsProvider.notifier)
          .setDownloadBase('');

      final staged = container.read(developerSettingsProvider).stagedConfig;
      expect(staged.downloadBaseUrl, DevConfig.defaults.downloadBaseUrl);
    });

    test('setDownloadBase stores a custom value', () async {
      final container = ProviderContainer(
        overrides: [devConfigProvider.overrideWithValue(const DevConfig())],
      );
      addTearDown(container.dispose);

      await container
          .read(developerSettingsProvider.notifier)
          .setDownloadBase('https://mws.domain');

      final state = container.read(developerSettingsProvider);
      expect(state.stagedConfig.downloadBaseUrl, 'https://mws.domain');
      expect(state.hasPendingChanges, isTrue);
    });

    test('setSeedData updates stagedConfig', () async {
      final container = ProviderContainer(
        overrides: [
          devConfigProvider.overrideWithValue(const DevConfig(seedData: true)),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(developerSettingsProvider.notifier)
          .setSeedData(false);

      final state = container.read(developerSettingsProvider);
      expect(state.stagedConfig.seedData, false);
      expect(state.hasPendingChanges, isTrue);
    });
  });
}

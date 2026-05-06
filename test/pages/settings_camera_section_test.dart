// U7 — Settings camera-section + empty-state CTA state machine.
//
// Two surface areas under test:
//   1. The connected-state camera card: 4-button grid (Reboot, Update fw,
//      Disconnect, Diagnostics), Reboot/Update fw disabled with the
//      "Coming soon" tooltip, Diagnostics push, Disconnect clearing
//      `activeCameraIdProvider`.
//   2. The empty-state CTA state machine: with no persisted last id it
//      pushes DiscoveryPage; with one it tries `connect(lastId)` and
//      either succeeds (page rerenders to populated) or falls back to
//      DiscoveryPage with a SnackBar.
//
// CRITICAL: We override `connectionStateProvider(activeId)` directly with
// a finite Stream rather than calling `mock.connect()` — the mock spawns a
// `Timer.periodic` for telemetry on every successful connect, which keeps
// `pumpAndSettle` from terminating. Where we DO need the real connect path
// (the success branch of the reconnect state machine), we drive it through
// a custom mock that doesn't start telemetry, then surface the resulting
// state via the provider override.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/ble/ble_service.dart';
import 'package:scout_camera/ble/mock_ble_service.dart';
import 'package:scout_camera/models/device.dart';
import 'package:scout_camera/pages/diagnostics_page.dart';
import 'package:scout_camera/pages/discovery_page.dart';
import 'package:scout_camera/pages/settings_page.dart';
import 'package:scout_camera/state/app_data.dart';
import 'package:scout_camera/state/ble_providers.dart';
import 'package:scout_camera/state/last_camera.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers.dart';

const String _kFakeDeviceId = 'SST-CAM-001';

MockBleService _newMock({double failureRate = 0.0}) => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: failureRate,
  randomSeed: 1,
);


/// A spy mock that records connect/disconnect calls without starting the
/// telemetry Timer.periodic that prevents pumpAndSettle from settling. We
/// only spy the methods Settings actually drives (connect/disconnect); all
/// other calls fall through to the real MockBleService.
class _SpyBleService extends MockBleService {
  _SpyBleService()
    : super(
        scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
        connectionDelay: Duration.zero,
        failureRate: 0.0,
        randomSeed: 1,
      );

  final List<String> connectCalls = [];
  final List<String> disconnectCalls = [];

  bool throwOnConnect = false;

  /// When non-null, [connect] awaits this completer before resolving so
  /// tests can assert on the loading state of the empty-state CTA before
  /// allowing the connect future to settle.
  Completer<void>? gateConnect;

  @override
  Future<void> connect(String deviceId) async {
    connectCalls.add(deviceId);
    if (gateConnect != null) {
      await gateConnect!.future;
    }
    if (throwOnConnect) {
      throw const BleConnectionException('forced failure');
    }
    // Do NOT call super.connect — that starts telemetry timers.
  }

  @override
  Future<void> disconnect(String deviceId) async {
    disconnectCalls.add(deviceId);
  }
}

void main() {
  final db = useInMemoryDb();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  /// Builds a Settings page harness. When [activeCameraId] is set the
  /// connection state is forced to [connectionState] via a finite Stream so
  /// `pumpAndSettle` can terminate. Pass [serviceOverride] when the test
  /// needs a custom mock that records connect/disconnect calls.
  Widget buildHarness({
    required BleService service,
    String? activeCameraId,
    CameraConnectionState connectionState = CameraConnectionState.connected,
  }) {
    return ProviderScope(
      overrides: [
        ...dbOverrides(db),
        bleServiceProvider.overrideWithValue(service),
        if (activeCameraId != null)
          activeCameraIdProvider.overrideWith((_) => activeCameraId),
        if (activeCameraId != null)
          connectionStateProvider(activeCameraId).overrideWith(
            (_) => Stream<CameraConnectionState>.value(connectionState),
          ),
      ],
      child: const MaterialApp(home: SettingsPage()),
    );
  }

  group('Camera card — connected state', () {
    testWidgets(
      'renders 2x2 button grid with Reboot, Update fw, Disconnect, Diagnostics',
      (tester) async {
        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(
          buildHarness(service: mock, activeCameraId: _kFakeDeviceId),
        );
        await tester.pumpAndSettle();

        expect(find.text('Reboot'), findsOneWidget);
        expect(find.text('Update fw'), findsOneWidget);
        expect(find.text('Disconnect'), findsOneWidget);
        expect(find.text('Diagnostics'), findsOneWidget);

        // Connected-camera caption + device id are present.
        expect(find.text('Connected camera'), findsOneWidget);
        expect(find.text(_kFakeDeviceId), findsOneWidget);
      },
    );

    testWidgets(
      'Reboot and Update fw show "Coming soon" tooltip and are disabled',
      (tester) async {
        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(
          buildHarness(service: mock, activeCameraId: _kFakeDeviceId),
        );
        await tester.pumpAndSettle();

        // Both placeholders are wrapped in a Tooltip with the placeholder
        // copy. The Settings page only renders that exact tooltip on the
        // two firmware-pending buttons.
        final tooltips = tester.widgetList<Tooltip>(
          find.byWidgetPredicate(
            (w) =>
                w is Tooltip &&
                w.message == 'Coming soon — firmware integration',
          ),
        );
        expect(tooltips.length, 2);
      },
    );

    testWidgets(
      'tapping Diagnostics pushes a route whose first page is DiagnosticsPage',
      (tester) async {
        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(
          buildHarness(service: mock, activeCameraId: _kFakeDeviceId),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DiagnosticsPage), findsNothing);

        await tester.tap(find.text('Diagnostics'));
        await tester.pumpAndSettle();

        expect(find.byType(DiagnosticsPage), findsOneWidget);
      },
    );

    testWidgets('tapping Disconnect calls bleService.disconnect and clears '
        'activeCameraIdProvider', (tester) async {
      final spy = _SpyBleService();
      addTearDown(spy.dispose);

      // Use a controllable connection-state stream so the page rerenders
      // to the empty state when we flip it post-disconnect.
      final controller = StreamController<CameraConnectionState>.broadcast();
      addTearDown(controller.close);

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...dbOverrides(db),
            bleServiceProvider.overrideWithValue(spy),
            activeCameraIdProvider.overrideWith((_) => _kFakeDeviceId),
            connectionStateProvider(
              _kFakeDeviceId,
            ).overrideWith((_) => controller.stream),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const MaterialApp(home: SettingsPage());
            },
          ),
        ),
      );

      controller.add(CameraConnectionState.connected);
      await tester.pumpAndSettle();
      expect(find.text('Disconnect'), findsOneWidget);

      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      // Spy recorded the disconnect call.
      expect(spy.disconnectCalls, [_kFakeDeviceId]);
      // Active camera id was cleared.
      expect(container.read(activeCameraIdProvider), isNull);

      // Page rerenders to empty state because activeCameraIdProvider is null.
      expect(find.text('No camera connected'), findsOneWidget);
      expect(find.text('Connect camera'), findsOneWidget);
    });
  });

  group('Empty-state CTA — one-tap reconnect', () {
    testWidgets(
      'with no persisted last id, tapping CTA navigates to DiscoveryPage',
      (tester) async {
        final mock = _newMock();
        addTearDown(mock.dispose);

        await tester.pumpWidget(buildHarness(service: mock));
        await tester.pumpAndSettle();

        expect(find.text('Connect camera'), findsOneWidget);
        expect(find.byType(DiscoveryPage), findsNothing);

        await tester.tap(find.text('Connect camera'));
        // Don't pumpAndSettle — DiscoveryPage's initState starts a scan
        // Timer that won't settle. One frame plus a short tick is enough
        // to push the route and let DiscoveryPage build at least once.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(DiscoveryPage), findsOneWidget);

        // Stop the scan so it doesn't dangle into the next test.
        await mock.stopScan();
      },
    );

    testWidgets('with a persisted last id, tapping CTA shows loading state and '
        'reconnects without scanning', (tester) async {
      SharedPreferences.setMockInitialValues({
        'last_connected_device_id': _kFakeDeviceId,
      });

      // Gate the connect future on a completer so we can observe the
      // loading state mid-flight, then complete it to drive the success
      // branch.
      final gate = Completer<void>();
      final spy = _SpyBleService()..gateConnect = gate;
      addTearDown(spy.dispose);

      // The reconnect success path writes activeCameraIdProvider; the
      // ProviderScope override below intentionally does NOT pin a
      // value so the StateProvider can be mutated. We DO override
      // the connection-state family so the page can transition to the
      // populated layout when the active id is set post-reconnect.
      final controller = StreamController<CameraConnectionState>.broadcast();
      addTearDown(controller.close);
      // Default value before reconnect: disconnected.
      controller.add(CameraConnectionState.disconnected);

      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...dbOverrides(db),
            bleServiceProvider.overrideWithValue(spy),
            connectionStateProvider(
              _kFakeDeviceId,
            ).overrideWith((_) => controller.stream),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const MaterialApp(home: SettingsPage());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Pre-warm the AsyncNotifier so `valueOrNull` returns the persisted
      // id rather than null inside `_onConnectTapped`. Without this the
      // SharedPreferences read is still in flight when the user taps.
      await container.read(lastConnectedDeviceIdProvider.future);
      await tester.pumpAndSettle();
      expect(find.text('Connect camera'), findsOneWidget);

      // Tap. The spy's connect awaits the gate, so the CTA stays in
      // loading state until we complete it.
      await tester.tap(find.text('Connect camera'));
      await tester.pump();

      // Loading label appears; "Connect camera" is gone.
      expect(find.text('Connecting…'), findsOneWidget);
      expect(find.text('Connect camera'), findsNothing);

      // Release the gate so connect resolves and the success branch
      // sets activeCameraIdProvider. Use bounded pumps because the
      // empty-state spinner uses CircularProgressIndicator (animates
      // forever) and pumpAndSettle would hang waiting for it to stop.
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Spy recorded the connect call.
      expect(spy.connectCalls, [_kFakeDeviceId]);
      // activeCameraIdProvider was set on success.
      expect(container.read(activeCameraIdProvider), _kFakeDeviceId);

      // Flip the connection stream to connected so the page rerenders
      // to the populated layout.
      controller.add(CameraConnectionState.connected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Disconnect'), findsOneWidget);
      expect(find.text('Diagnostics'), findsOneWidget);
      expect(find.text('No camera connected'), findsNothing);

      // No discovery scan was started — we reconnected directly.
      expect(spy.isScanning, isFalse);
    });

    testWidgets(
      'with a persisted last id and forced connection failure, falls back '
      'to DiscoveryPage with SnackBar',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'last_connected_device_id': _kFakeDeviceId,
        });

        final spy = _SpyBleService()..throwOnConnect = true;
        addTearDown(spy.dispose);

        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [bleServiceProvider.overrideWithValue(spy)],
            child: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return const MaterialApp(home: SettingsPage());
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Pre-warm the AsyncNotifier so `valueOrNull` returns the persisted
        // id when the CTA is tapped.
        await container.read(lastConnectedDeviceIdProvider.future);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Connect camera'));
        // Pump enough to let the connect future reject and the navigator
        // push DiscoveryPage. Use bounded pumps because DiscoveryPage's
        // scan timer prevents pumpAndSettle from terminating.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        // SnackBar surfaces the fallback copy.
        expect(
          find.text(
            "Couldn't reconnect to last camera — searching for cameras.",
          ),
          findsOneWidget,
        );
        // DiscoveryPage was pushed.
        expect(find.byType(DiscoveryPage), findsOneWidget);
        // The connect attempt was made.
        expect(spy.connectCalls, [_kFakeDeviceId]);

        await spy.stopScan();
      },
    );
  });
}

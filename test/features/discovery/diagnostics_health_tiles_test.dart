// U4 — per-sensor status tiles on the diagnostics page (R9, AE6).
//
// Camera 0/1 tiles are driven by deviceHealthProvider's per-camera values
// (OK / Recovering / Down / "—"); the two mic tiles are hardcoded offline
// placeholders (mic hardware unsupported this cycle). Disconnected /
// unreported health renders "—" — never a stale or fabricated OK, per the
// page convention.
//
// The provider's fold/freshness logic is covered in
// test/core/state/device_health_test.dart; here the health state is pinned
// via a ProviderScope override (the standard test seam).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/telemetry.dart';
import 'package:sst_cam_app/core/state/device_health.dart';
import 'package:sst_cam_app/core/version/version_info.dart';
import 'package:sst_cam_app/features/discovery/diagnostics_page.dart';

const _deviceId = 'SST-CAM-001';

/// Pinned-health controller: replaces the derived notifier so the page test
/// controls the exact per-camera values.
class _PinnedHealth extends DeviceHealthController {
  _PinnedHealth(this._value);
  final DeviceHealthState _value;

  @override
  DeviceHealthState build() => _value;
}

Future<void> _pump(WidgetTester tester, {DeviceHealthState? health}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Health pinned when given; otherwise the real derived provider runs
        // with no active camera → DeviceHealthState.unreported (the
        // disconnected case).
        if (health != null)
          deviceHealthProvider.overrideWith(() => _PinnedHealth(health)),
        telemetryProvider(
          _deviceId,
        ).overrideWith((ref) => const Stream.empty()),
        connectedDeviceInfoProvider(
          _deviceId,
        ).overrideWith((ref) async => null),
        appVersionProvider.overrideWith((ref) async => '0.1.0 (dev)'),
      ],
      child: const MaterialApp(home: DiagnosticsPage(deviceId: _deviceId)),
    ),
  );
  await tester.pump();
}

/// The value Text rendered inside the tile labelled [label].
String _tileValue(WidgetTester tester, String label) {
  final tile = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_StatTile',
    ),
  );
  expect(tile, findsOneWidget, reason: 'tile "$label" should render');
  final texts = tester
      .widgetList<Text>(find.descendant(of: tile, matching: find.byType(Text)))
      .map((t) => t.data)
      .toList();
  // [label, value]
  return texts.last!;
}

void main() {
  testWidgets('AE6: both cameras OK → two OK camera tiles + two offline '
      'mic tiles', (tester) async {
    await _pump(
      tester,
      health: const DeviceHealthState(
        camera0: CameraHealth.ok,
        camera1: CameraHealth.ok,
      ),
    );
    expect(_tileValue(tester, 'Camera 0'), 'OK');
    expect(_tileValue(tester, 'Camera 1'), 'OK');
    expect(_tileValue(tester, 'Mic 0'), 'Offline');
    expect(_tileValue(tester, 'Mic 1'), 'Offline');
  });

  testWidgets('disconnected → camera tiles render "—" (unreported), '
      'not a stale OK; mic tiles stay offline', (tester) async {
    await _pump(tester); // no override → derived provider, no camera
    expect(_tileValue(tester, 'Camera 0'), '—');
    expect(_tileValue(tester, 'Camera 1'), '—');
    expect(find.text('OK'), findsNothing);
    // Mic placeholders are connection-independent.
    expect(_tileValue(tester, 'Mic 0'), 'Offline');
    expect(_tileValue(tester, 'Mic 1'), 'Offline');
  });

  testWidgets('one camera down → that tile Down, the other stays OK', (
    tester,
  ) async {
    await _pump(
      tester,
      health: const DeviceHealthState(
        camera0: CameraHealth.down,
        camera1: CameraHealth.ok,
      ),
    );
    expect(_tileValue(tester, 'Camera 0'), 'Down');
    expect(_tileValue(tester, 'Camera 1'), 'OK');
  });

  testWidgets('recovering renders as Recovering, not down and not OK', (
    tester,
  ) async {
    await _pump(
      tester,
      health: const DeviceHealthState(
        camera0: CameraHealth.ok,
        camera1: CameraHealth.recovering,
      ),
    );
    expect(_tileValue(tester, 'Camera 0'), 'OK');
    expect(_tileValue(tester, 'Camera 1'), 'Recovering');
    expect(find.text('Down'), findsNothing);
  });
}

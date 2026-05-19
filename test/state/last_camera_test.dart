// U7 — `lastConnectedDeviceIdProvider` over `shared_preferences`.
//
// Uses `SharedPreferences.setMockInitialValues({...})` to round-trip the
// persisted id without a real platform. Each test sets up a fresh mock
// state in `setUp` so values do not leak across tests.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/state/last_camera.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('initial value is null when nothing persisted', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final value = await container.read(lastConnectedDeviceIdProvider.future);
    expect(value, isNull);
  });

  test('set persists and updates state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Wait for initial build before mutating.
    await container.read(lastConnectedDeviceIdProvider.future);

    await container
        .read(lastConnectedDeviceIdProvider.notifier)
        .set('SST-CAM-001');

    expect(
      container.read(lastConnectedDeviceIdProvider).valueOrNull,
      'SST-CAM-001',
    );

    // Survives a fresh container reading the same SharedPreferences instance.
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    final value = await container2.read(lastConnectedDeviceIdProvider.future);
    expect(value, 'SST-CAM-001');
  });

  test('initial value with pre-populated SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({
      'last_connected_device_id': 'SST-CAM-002',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final value = await container.read(lastConnectedDeviceIdProvider.future);
    expect(value, 'SST-CAM-002');
  });

  test('clear removes persisted value', () async {
    SharedPreferences.setMockInitialValues({
      'last_connected_device_id': 'SST-CAM-003',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(lastConnectedDeviceIdProvider.future);

    await container.read(lastConnectedDeviceIdProvider.notifier).clear();

    expect(container.read(lastConnectedDeviceIdProvider).valueOrNull, isNull);

    // A fresh container reading the same prefs sees no value.
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    final value = await container2.read(lastConnectedDeviceIdProvider.future);
    expect(value, isNull);
  });
}

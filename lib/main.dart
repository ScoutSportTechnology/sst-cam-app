import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'ble/mock_ble_service.dart';
import 'state/ble_providers.dart';

void main() {
  // Until Phase 7 wires BleServiceImpl to firmware, the runtime backend is
  // the in-memory MockBleService — same test double the integration tests
  // use. Swap to BleServiceImpl by removing the override below.
  runApp(
    ProviderScope(
      overrides: [
        bleServiceProvider.overrideWith((ref) {
          final svc = MockBleService(failureRate: 0);
          ref.onDispose(svc.dispose);
          return svc;
        }),
      ],
      child: const ScoutCameraApp(),
    ),
  );
}

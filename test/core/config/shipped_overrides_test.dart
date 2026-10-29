import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/config/dev_navigation.dart';
import 'package:sst_cam_app/core/config/env.dart';
import 'package:sst_cam_app/core/config/shipped_overrides.dart';

void main() {
  group('AppEnv.showsDevTooling', () {
    test('stage and dev expose tooling; prod does not', () {
      expect(AppEnv.stage.showsDevTooling, isTrue);
      expect(AppEnv.dev.showsDevTooling, isTrue);
      expect(AppEnv.prod.showsDevTooling, isFalse);
    });
  });

  group('shippedOverrides', () {
    test('prod build installs no overrides (real backend, no tooling)', () {
      // An empty list means the real BLE/WiFi provider defaults stand AND there
      // is no devNavigationProvider override — prod has no path to tooling (R7).
      expect(shippedOverrides(AppEnv.prod), isEmpty);
    });

    test('stage build exposes dev tooling via devNavigationProvider', () {
      final container = ProviderContainer(
        overrides: shippedOverrides(AppEnv.stage),
      );
      addTearDown(container.dispose);

      final nav = container.read(devNavigationProvider);
      expect(nav.debugPage, isNotNull);
      expect(nav.developerSettings, isNotNull);
    });

    test('prod build leaves devNavigationProvider at its empty default', () {
      final container = ProviderContainer(
        overrides: shippedOverrides(AppEnv.prod),
      );
      addTearDown(container.dispose);

      final nav = container.read(devNavigationProvider);
      expect(nav.debugPage, isNull);
      expect(nav.developerSettings, isNull);
    });
  });
}

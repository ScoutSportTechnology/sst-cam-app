import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/config/env.dart';
import 'package:sst_cam_app/core/config/shipped_overrides.dart';

/// Guards the single-entry (`lib/main.dart`) env-branch selection: which backend
/// + tooling each `AppEnv` boots. `main()` itself is not callable in a unit test
/// (it touches platform channels + `runApp`), so these assert the two seams the
/// entry branches on — the `isDevBackend` predicate and the `shippedOverrides`
/// set — which together determine the container built for every env.
void main() {
  group('entry backend selection', () {
    test('dev boots the mock backend branch', () {
      // main.dart runs _bootstrapDev() (mock BLE/WiFi + seed) iff this is true.
      expect(AppEnv.dev.isDevBackend, isTrue);
    });

    test('stage and prod boot the real backend branch', () {
      // Both fall through to shippedOverrides() with the real impls as defaults.
      expect(AppEnv.stage.isDevBackend, isFalse);
      expect(AppEnv.prod.isDevBackend, isFalse);
    });

    test('default env (no APP_ENV define) is dev/mock', () {
      // A test process sets no APP_ENV, so the compile-time const defaults to
      // dev — the safe default (mock, no real device required).
      expect(kAppEnv, AppEnv.dev);
      expect(kAppEnv.isDevBackend, isTrue);
    });
  });

  group('shipped override set per env', () {
    test('stage installs dev tooling (nav) with the real backend', () {
      // One override: dev navigation. No BLE/WiFi mock override → real backend.
      expect(shippedOverrides(AppEnv.stage), hasLength(1));
    });

    test(
      'prod installs zero overrides (real backend, tooling compiled out)',
      () {
        expect(shippedOverrides(AppEnv.prod), isEmpty);
      },
    );
  });
}

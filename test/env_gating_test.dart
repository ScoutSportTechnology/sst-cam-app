import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/config/env.dart';

/// Compile-time gating that keeps the mock backend + dev tooling OUT of the
/// shipped `prod` binary. Both flags are driven by the const [kAppEnv], so for a
/// `prod` build they are statically false — `main.dart`'s `isDevBackend` branch
/// (mock BLE/WiFi + `MockDataSeeder` + seed sync) and `shippedOverrides`'s
/// tooling branch are dead code and tree-shaken away.
///
/// The runtime flags are asserted here; the actual absence of `Mock*`/seeder
/// symbols from the release APK is verified by the artifact scan documented in
/// the U5 execution notes (build `prod` release, grep the APK — expect absent).
void main() {
  group('prod build gates out dev code', () {
    test('prod uses the real backend (mock branch is dead code)', () {
      expect(AppEnv.prod.isDevBackend, isFalse);
    });

    test('prod compiles out dev tooling', () {
      expect(AppEnv.prod.showsDevTooling, isFalse);
    });
  });

  group('stage keeps tooling but real backend', () {
    test('stage is real backend', () {
      expect(AppEnv.stage.isDevBackend, isFalse);
    });

    test('stage keeps dev tooling on', () {
      expect(AppEnv.stage.showsDevTooling, isTrue);
    });
  });
}

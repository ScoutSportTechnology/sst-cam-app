// U4 — version assembly (R10, R11, R12).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sst_cam_app/core/version/version_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('assembleAppVersion', () {
    test('git-derived define is shown verbatim (no channel/tag suffix)', () {
      final v = assembleAppVersion(
        defineVersion: 'v0.1.0-beta.12-9-g501047f',
        packageVersion: '0.1.0',
        packageBuild: '1',
      );
      expect(v, 'v0.1.0-beta.12-9-g501047f');
    });

    test('bare local build (no define) falls back to package version', () {
      final v = assembleAppVersion(
        defineVersion: '',
        packageVersion: '0.1.0',
        packageBuild: '1',
      );
      expect(v, '0.1.0+1');
    });

    test('empty package build omits the +build suffix', () {
      final v = assembleAppVersion(
        defineVersion: '',
        packageVersion: '0.2.0',
        packageBuild: '',
      );
      expect(v, '0.2.0');
    });
  });

  group('protoVersionDisplay', () {
    test('disconnected: repo tag only', () {
      expect(protoVersionDisplay(), 'proto dev');
    });

    test('connected: repo tag + wire protocol_version', () {
      expect(
        protoVersionDisplay(wireProtocolVersion: 2),
        'proto dev · wire v2',
      );
    });
  });

  test(
    'appVersionProvider resolves from package metadata when no define set',
    () {
      PackageInfo.setMockInitialValues(
        appName: 'SST Cam',
        packageName: 'com.example.sst',
        version: '0.1.0',
        buildNumber: '1',
        buildSignature: '',
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // No --dart-define in the test runner → falls back to package metadata.
      expect(container.read(appVersionProvider.future), completion('0.1.0+1'));
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/config/dev_config.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DevConfig.load', () {
    test('returns defaults when no prefs exist', () async {
      final config = await DevConfig.load();
      // Defaults come from the EMULATE / SEED build flags (both default off);
      // a plain `flutter test` sets no dart-defines, so both are false.
      expect(config.seedData, false);
      expect(config.cameraEmulation, false);
      expect(config.previewBaseUrl, 'rtsp://localhost:8554');
      expect(config.downloadBaseUrl, 'http://localhost:8080');
    });

    test('after save(), subsequent load() returns saved values', () async {
      const original = DevConfig(
        seedData: false,
        cameraEmulation: false,
        previewBaseUrl: 'rtsp://mws.domain',
        downloadBaseUrl: 'https://mws.domain',
      );
      await original.save();
      final loaded = await DevConfig.load();
      expect(loaded.seedData, false);
      expect(loaded.cameraEmulation, false);
      expect(loaded.previewBaseUrl, 'rtsp://mws.domain');
      expect(loaded.downloadBaseUrl, 'https://mws.domain');
    });

    test('missing individual keys fall back to their own defaults', () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_seed_data': false,
        // cameraEmulation and base URLs absent
      });
      final config = await DevConfig.load();
      expect(config.seedData, false);
      expect(config.cameraEmulation, false);
      expect(config.previewBaseUrl, 'rtsp://localhost:8554');
      expect(config.downloadBaseUrl, 'http://localhost:8080');
    });

    test('empty base-URL strings fall back to their defaults', () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_preview_base_url': '',
        'dev_config_download_base_url': '',
      });
      final config = await DevConfig.load();
      expect(config.previewBaseUrl, 'rtsp://localhost:8554');
      expect(config.downloadBaseUrl, 'http://localhost:8080');
    });
  });

  group('DevConfig legacy data-mode migration', () {
    test('legacy "empty" migrates to seedData=false', () async {
      SharedPreferences.setMockInitialValues({'dev_config_data_mode': 'empty'});
      final config = await DevConfig.load();
      expect(config.seedData, false);
    });

    test('legacy "full" migrates to seedData=true', () async {
      SharedPreferences.setMockInitialValues({'dev_config_data_mode': 'full'});
      final config = await DevConfig.load();
      expect(config.seedData, true);
    });

    test('legacy "seed" migrates to seedData=true', () async {
      SharedPreferences.setMockInitialValues({'dev_config_data_mode': 'seed'});
      final config = await DevConfig.load();
      expect(config.seedData, true);
    });

    test(
      'unknown legacy mode migrates to seedData=true (safe default)',
      () async {
        SharedPreferences.setMockInitialValues({
          'dev_config_data_mode': 'something_old',
        });
        final config = await DevConfig.load();
        expect(config.seedData, true);
      },
    );

    test('migration persists the new key and drops the legacy key', () async {
      SharedPreferences.setMockInitialValues({'dev_config_data_mode': 'empty'});
      await DevConfig.load();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('dev_config_seed_data'), false);
      expect(
        prefs.containsKey('dev_config_data_mode'),
        isFalse,
        reason: 'legacy key must be removed after migration',
      );
    });

    test('new key wins over a stale legacy key', () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_seed_data': true,
        'dev_config_data_mode': 'empty',
      });
      final config = await DevConfig.load();
      expect(config.seedData, true);
    });
  });

  group('DevConfig legacy server-address migration', () {
    test('legacy host migrates to scheme+port base URLs', () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_server_address': '192.168.1.5',
      });
      final config = await DevConfig.load();
      expect(config.previewBaseUrl, 'rtsp://192.168.1.5:8554');
      expect(config.downloadBaseUrl, 'http://192.168.1.5:8080');
    });

    test('migration persists the new keys and drops the legacy key', () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_server_address': '192.168.1.5',
      });
      await DevConfig.load();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('dev_config_preview_base_url'),
        'rtsp://192.168.1.5:8554',
      );
      expect(
        prefs.getString('dev_config_download_base_url'),
        'http://192.168.1.5:8080',
      );
      expect(
        prefs.containsKey('dev_config_server_address'),
        isFalse,
        reason: 'legacy key must be removed after migration',
      );
    });

    test('empty legacy host migrates to localhost bases', () async {
      SharedPreferences.setMockInitialValues({'dev_config_server_address': ''});
      final config = await DevConfig.load();
      expect(config.previewBaseUrl, 'rtsp://localhost:8554');
      expect(config.downloadBaseUrl, 'http://localhost:8080');
    });

    test('new base-URL keys win over a stale legacy host', () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_preview_base_url': 'rtsp://kept:8554',
        'dev_config_download_base_url': 'http://kept:8080',
        'dev_config_server_address': '192.168.1.5',
      });
      final config = await DevConfig.load();
      expect(config.previewBaseUrl, 'rtsp://kept:8554');
      expect(config.downloadBaseUrl, 'http://kept:8080');
    });
  });

  group('DevConfig equality', () {
    test('two configs with same fields are equal', () {
      const a = DevConfig(
        seedData: false,
        cameraEmulation: false,
        previewBaseUrl: 'rtsp://host:8554',
        downloadBaseUrl: 'http://host:8080',
      );
      const b = DevConfig(
        seedData: false,
        cameraEmulation: false,
        previewBaseUrl: 'rtsp://host:8554',
        downloadBaseUrl: 'http://host:8080',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different seedData produces inequality', () {
      const a = DevConfig(seedData: true);
      const b = DevConfig(seedData: false);
      expect(a, isNot(equals(b)));
    });

    test('different downloadBaseUrl produces inequality', () {
      const a = DevConfig(downloadBaseUrl: 'http://a:8080');
      const b = DevConfig(downloadBaseUrl: 'http://b:8080');
      expect(a, isNot(equals(b)));
    });
  });

  group('DevConfig.copyWith', () {
    test('overrides only the specified field', () {
      const original = DevConfig(
        seedData: true,
        cameraEmulation: true,
        previewBaseUrl: 'rtsp://10.0.0.1:8554',
        downloadBaseUrl: 'http://10.0.0.1:8080',
      );
      final modified = original.copyWith(cameraEmulation: false);
      expect(modified.seedData, true);
      expect(modified.cameraEmulation, false);
      expect(modified.previewBaseUrl, 'rtsp://10.0.0.1:8554');
      expect(modified.downloadBaseUrl, 'http://10.0.0.1:8080');
    });
  });
}

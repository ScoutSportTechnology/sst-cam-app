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
      expect(config.seedData, true);
      expect(config.cameraEmulation, true);
      expect(config.serverAddress, 'localhost');
    });

    test('after save(), subsequent load() returns saved values', () async {
      const original = DevConfig(
        seedData: false,
        cameraEmulation: false,
        serverAddress: '192.168.1.100',
      );
      await original.save();
      final loaded = await DevConfig.load();
      expect(loaded.seedData, false);
      expect(loaded.cameraEmulation, false);
      expect(loaded.serverAddress, '192.168.1.100');
    });

    test('missing individual keys fall back to their own defaults', () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_seed_data': false,
        // cameraEmulation and serverAddress absent
      });
      final config = await DevConfig.load();
      expect(config.seedData, false);
      expect(config.cameraEmulation, true);
      expect(config.serverAddress, 'localhost');
    });

    test('empty serverAddress string falls back to localhost', () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_server_address': '',
      });
      final config = await DevConfig.load();
      expect(config.serverAddress, 'localhost');
    });
  });

  group('DevConfig legacy data-mode migration', () {
    test('legacy "empty" migrates to seedData=false', () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_data_mode': 'empty',
      });
      final config = await DevConfig.load();
      expect(config.seedData, false);
    });

    test('legacy "full" migrates to seedData=true', () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_data_mode': 'full',
      });
      final config = await DevConfig.load();
      expect(config.seedData, true);
    });

    test('legacy "seed" migrates to seedData=true', () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_data_mode': 'seed',
      });
      final config = await DevConfig.load();
      expect(config.seedData, true);
    });

    test('unknown legacy mode migrates to seedData=true (safe default)',
        () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_data_mode': 'something_old',
      });
      final config = await DevConfig.load();
      expect(config.seedData, true);
    });

    test('migration persists the new key and drops the legacy key', () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_data_mode': 'empty',
      });
      await DevConfig.load();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('dev_config_seed_data'), false);
      expect(prefs.containsKey('dev_config_data_mode'), isFalse,
          reason: 'legacy key must be removed after migration');
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

  group('DevConfig equality', () {
    test('two configs with same fields are equal', () {
      const a = DevConfig(seedData: false, cameraEmulation: false, serverAddress: 'host');
      const b = DevConfig(seedData: false, cameraEmulation: false, serverAddress: 'host');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different seedData produces inequality', () {
      const a = DevConfig(seedData: true);
      const b = DevConfig(seedData: false);
      expect(a, isNot(equals(b)));
    });
  });

  group('DevConfig.copyWith', () {
    test('overrides only the specified field', () {
      const original = DevConfig(
        seedData: true,
        cameraEmulation: true,
        serverAddress: '10.0.0.1',
      );
      final modified = original.copyWith(cameraEmulation: false);
      expect(modified.seedData, true);
      expect(modified.cameraEmulation, false);
      expect(modified.serverAddress, '10.0.0.1');
    });
  });
}

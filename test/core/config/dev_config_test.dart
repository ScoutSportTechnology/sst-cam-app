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
      expect(config.dataMode, DataMode.full);
      expect(config.cameraEmulation, true);
      expect(config.serverAddress, 'localhost');
    });

    test('after save(), subsequent load() returns saved values', () async {
      const original = DevConfig(
        dataMode: DataMode.empty,
        cameraEmulation: false,
        serverAddress: '192.168.1.100',
      );
      await original.save();
      final loaded = await DevConfig.load();
      expect(loaded.dataMode, DataMode.empty);
      expect(loaded.cameraEmulation, false);
      expect(loaded.serverAddress, '192.168.1.100');
    });

    test('missing individual keys fall back to their own defaults', () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_data_mode': 'seed',
        // cameraEmulation and serverAddress absent
      });
      final config = await DevConfig.load();
      expect(config.dataMode, DataMode.seed);
      expect(config.cameraEmulation, true);
      expect(config.serverAddress, 'localhost');
    });

    test('unknown dataMode string falls back to full', () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_data_mode': 'something_old',
      });
      final config = await DevConfig.load();
      expect(config.dataMode, DataMode.full);
    });

    test('empty serverAddress string falls back to localhost', () async {
      SharedPreferences.setMockInitialValues({
        'dev_config_server_address': '',
      });
      final config = await DevConfig.load();
      expect(config.serverAddress, 'localhost');
    });
  });

  group('DevConfig equality', () {
    test('two configs with same fields are equal', () {
      const a = DevConfig(dataMode: DataMode.seed, cameraEmulation: false, serverAddress: 'host');
      const b = DevConfig(dataMode: DataMode.seed, cameraEmulation: false, serverAddress: 'host');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different dataMode produces inequality', () {
      const a = DevConfig(dataMode: DataMode.full);
      const b = DevConfig(dataMode: DataMode.empty);
      expect(a, isNot(equals(b)));
    });
  });

  group('DevConfig.copyWith', () {
    test('overrides only the specified field', () {
      const original = DevConfig(
        dataMode: DataMode.seed,
        cameraEmulation: true,
        serverAddress: '10.0.0.1',
      );
      final modified = original.copyWith(cameraEmulation: false);
      expect(modified.dataMode, DataMode.seed);
      expect(modified.cameraEmulation, false);
      expect(modified.serverAddress, '10.0.0.1');
    });
  });
}

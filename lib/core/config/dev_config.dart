import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSeedDataKey = 'dev_config_seed_data';
const _kLegacyDataModeKey = 'dev_config_data_mode';
const _kCameraEmulationKey = 'dev_config_camera_emulation';
const _kServerAddressKey = 'dev_config_server_address';

class DevConfig {
  const DevConfig({
    this.seedData = true,
    this.cameraEmulation = true,
    this.serverAddress = 'localhost',
  });

  final bool seedData;
  final bool cameraEmulation;
  final String serverAddress;

  static const DevConfig defaults = DevConfig();

  static Future<DevConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return DevConfig(
      seedData: await _loadSeedData(prefs),
      cameraEmulation:
          prefs.getBool(_kCameraEmulationKey) ?? defaults.cameraEmulation,
      serverAddress: _resolveServerAddress(prefs.getString(_kServerAddressKey)),
    );
  }

  /// Reads [seedData], migrating the legacy `dev_config_data_mode` enum on the
  /// first load. Only the old `empty` mode meant "do not seed"; `full`/`seed`
  /// and any unknown/absent value all seeded. The new bool key wins once set.
  static Future<bool> _loadSeedData(SharedPreferences prefs) async {
    final stored = prefs.getBool(_kSeedDataKey);
    if (stored != null) return stored;

    final legacyMode = prefs.getString(_kLegacyDataModeKey);
    if (legacyMode != null) {
      final migrated = legacyMode != 'empty';
      await prefs.setBool(_kSeedDataKey, migrated);
      await prefs.remove(_kLegacyDataModeKey);
      return migrated;
    }
    return defaults.seedData;
  }

  static String _resolveServerAddress(String? stored) =>
      (stored == null || stored.isEmpty) ? defaults.serverAddress : stored;

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSeedDataKey, seedData);
    await prefs.setBool(_kCameraEmulationKey, cameraEmulation);
    await prefs.setString(
      _kServerAddressKey,
      serverAddress.isEmpty ? defaults.serverAddress : serverAddress,
    );
  }

  DevConfig copyWith({
    bool? seedData,
    bool? cameraEmulation,
    String? serverAddress,
  }) =>
      DevConfig(
        seedData: seedData ?? this.seedData,
        cameraEmulation: cameraEmulation ?? this.cameraEmulation,
        serverAddress: serverAddress ?? this.serverAddress,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DevConfig &&
          seedData == other.seedData &&
          cameraEmulation == other.cameraEmulation &&
          serverAddress == other.serverAddress;

  @override
  int get hashCode =>
      Object.hash(seedData, cameraEmulation, serverAddress);
}

/// Safe non-throwing default so common code can read DevConfig in prod without
/// crashing. In dev builds, main.dart overrides this with the loaded config.
final devConfigProvider = Provider<DevConfig>((ref) => DevConfig.defaults);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kDataModeKey = 'dev_config_data_mode';
const _kCameraEmulationKey = 'dev_config_camera_emulation';
const _kServerAddressKey = 'dev_config_server_address';

enum DataMode { full, seed, empty }

class DevConfig {
  const DevConfig({
    this.dataMode = DataMode.full,
    this.cameraEmulation = true,
    this.serverAddress = 'localhost',
  });

  final DataMode dataMode;
  final bool cameraEmulation;
  final String serverAddress;

  static const DevConfig defaults = DevConfig();

  static Future<DevConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeStr = prefs.getString(_kDataModeKey);
    final dataMode = switch (modeStr) {
      'seed' => DataMode.seed,
      'empty' => DataMode.empty,
      'full' => DataMode.full,
      _ => DataMode.full, // unknown or absent → default
    };
    final cameraEmulation =
        prefs.getBool(_kCameraEmulationKey) ?? defaults.cameraEmulation;
    final serverAddress =
        prefs.getString(_kServerAddressKey) ?? defaults.serverAddress;
    return DevConfig(
      dataMode: dataMode,
      cameraEmulation: cameraEmulation,
      serverAddress: serverAddress.isEmpty ? defaults.serverAddress : serverAddress,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDataModeKey, dataMode.name);
    await prefs.setBool(_kCameraEmulationKey, cameraEmulation);
    await prefs.setString(
      _kServerAddressKey,
      serverAddress.isEmpty ? defaults.serverAddress : serverAddress,
    );
  }

  DevConfig copyWith({
    DataMode? dataMode,
    bool? cameraEmulation,
    String? serverAddress,
  }) =>
      DevConfig(
        dataMode: dataMode ?? this.dataMode,
        cameraEmulation: cameraEmulation ?? this.cameraEmulation,
        serverAddress: serverAddress ?? this.serverAddress,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DevConfig &&
          dataMode == other.dataMode &&
          cameraEmulation == other.cameraEmulation &&
          serverAddress == other.serverAddress;

  @override
  int get hashCode =>
      Object.hash(dataMode, cameraEmulation, serverAddress);
}

/// Safe non-throwing default so common code can read DevConfig in prod without
/// crashing. In dev builds, main.dart overrides this with the loaded config.
final devConfigProvider = Provider<DevConfig>((ref) => DevConfig.defaults);

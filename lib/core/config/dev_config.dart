import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Two orthogonal build flags, both default OFF, that seed the [DevConfig]
/// runtime defaults. Only the `dev` env reads them — a `stage`/`prod` build never
/// runs the dev bootstrap, so both are forced false there automatically (real
/// backend, no seed). The in-app Developer switches override these at runtime and
/// persist (SharedPreferences wins over the compile default).
///
/// - [kEmulated] — mock BLE/WiFi backend instead of the real device.
/// - [kSeed]     — insert dev fixture data (teams/matches/…) into the DB.
///
/// Set per build, e.g. `--dart-define=EMULATE=true --dart-define=SEED=true`.
const bool kEmulated = bool.fromEnvironment('EMULATE', defaultValue: false);
const bool kSeed = bool.fromEnvironment('SEED', defaultValue: false);

const _kSeedDataKey = 'dev_config_seed_data';
const _kSeedAppliedKey = 'dev_config_seed_applied';
const _kLegacyDataModeKey = 'dev_config_data_mode';
const _kCameraEmulationKey = 'dev_config_camera_emulation';
const _kPreviewBaseUrlKey = 'dev_config_preview_base_url';
const _kDownloadBaseUrlKey = 'dev_config_download_base_url';
const _kLegacyServerAddressKey = 'dev_config_server_address';

class DevConfig {
  const DevConfig({
    this.seedData = kSeed,
    this.cameraEmulation = kEmulated,
    this.previewBaseUrl = 'rtsp://localhost:8554',
    this.downloadBaseUrl = 'http://localhost:8080',
  });

  final bool seedData;
  final bool cameraEmulation;

  /// Base for the mock RTSP preview stream, e.g. `rtsp://localhost:8554` or
  /// `rtsp://mws.domain` (standard port). The `/preview` path is appended.
  final String previewBaseUrl;

  /// Base for mock HTTP recording downloads, e.g. `http://localhost:8080` or
  /// `https://mws.domain`. The `/recordings/<id>` path is appended.
  final String downloadBaseUrl;

  static const DevConfig defaults = DevConfig();

  static Future<DevConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final (previewBase, downloadBase) = await _loadBaseUrls(prefs);
    return DevConfig(
      seedData: await _loadSeedData(prefs),
      cameraEmulation:
          prefs.getBool(_kCameraEmulationKey) ?? defaults.cameraEmulation,
      previewBaseUrl: previewBase,
      downloadBaseUrl: downloadBase,
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

  /// Reads the two base URLs, migrating the legacy single `serverAddress` host
  /// on the first load: a bare host becomes `rtsp://<host>:8554` +
  /// `http://<host>:8080`. The new keys win once set.
  static Future<(String, String)> _loadBaseUrls(SharedPreferences prefs) async {
    final preview = prefs.getString(_kPreviewBaseUrlKey);
    final download = prefs.getString(_kDownloadBaseUrlKey);
    if (preview != null || download != null) {
      return (
        (preview == null || preview.isEmpty)
            ? defaults.previewBaseUrl
            : preview,
        (download == null || download.isEmpty)
            ? defaults.downloadBaseUrl
            : download,
      );
    }

    final legacyHost = prefs.getString(_kLegacyServerAddressKey);
    if (legacyHost != null) {
      final host = legacyHost.isEmpty ? 'localhost' : legacyHost;
      final migratedPreview = 'rtsp://$host:8554';
      final migratedDownload = 'http://$host:8080';
      await prefs.setString(_kPreviewBaseUrlKey, migratedPreview);
      await prefs.setString(_kDownloadBaseUrlKey, migratedDownload);
      await prefs.remove(_kLegacyServerAddressKey);
      return (migratedPreview, migratedDownload);
    }
    return (defaults.previewBaseUrl, defaults.downloadBaseUrl);
  }

  /// Whether the LAST boot left mock fixtures applied in the DB. Distinct from
  /// [seedData] (the desired state): comparing the two lets the dev bootstrap
  /// wipe fixtures exactly once on the seed→unseed TRANSITION instead of
  /// wiping user data on every launch. Defaults to false (never wipe) when the
  /// marker is absent or prefs are unreadable — the safe direction.
  static Future<bool> loadSeedApplied() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSeedAppliedKey) ?? false;
  }

  static Future<void> saveSeedApplied(bool applied) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSeedAppliedKey, applied);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSeedDataKey, seedData);
    await prefs.setBool(_kCameraEmulationKey, cameraEmulation);
    await prefs.setString(
      _kPreviewBaseUrlKey,
      previewBaseUrl.isEmpty ? defaults.previewBaseUrl : previewBaseUrl,
    );
    await prefs.setString(
      _kDownloadBaseUrlKey,
      downloadBaseUrl.isEmpty ? defaults.downloadBaseUrl : downloadBaseUrl,
    );
  }

  DevConfig copyWith({
    bool? seedData,
    bool? cameraEmulation,
    String? previewBaseUrl,
    String? downloadBaseUrl,
  }) => DevConfig(
    seedData: seedData ?? this.seedData,
    cameraEmulation: cameraEmulation ?? this.cameraEmulation,
    previewBaseUrl: previewBaseUrl ?? this.previewBaseUrl,
    downloadBaseUrl: downloadBaseUrl ?? this.downloadBaseUrl,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DevConfig &&
          seedData == other.seedData &&
          cameraEmulation == other.cameraEmulation &&
          previewBaseUrl == other.previewBaseUrl &&
          downloadBaseUrl == other.downloadBaseUrl;

  @override
  int get hashCode =>
      Object.hash(seedData, cameraEmulation, previewBaseUrl, downloadBaseUrl);
}

/// Safe non-throwing default so common code can read DevConfig in prod without
/// crashing. In dev builds, main.dart overrides this with the loaded config.
final devConfigProvider = Provider<DevConfig>((ref) => DevConfig.defaults);

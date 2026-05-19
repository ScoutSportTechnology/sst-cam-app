// Global environment flag. Drives BLE/WiFi backend selection and
// environment-level behaviour (logging verbosity, diagnostics, etc.).
//
// Override at build/run time:
//   flutter run --dart-define=APP_ENV=dev
//   flutter run --dart-define=APP_ENV=stage
//   flutter run --dart-define=APP_ENV=prod
//
// dev   — MockBleService + MockWifiService; no real device required.
// stage — BleServiceImpl over flutter_blue_plus; real device required.
// prod  — BleServiceImpl; release build.
//
// Mock fixture data is controlled separately:
//   flutter run --dart-define=kUseMockData=true
//
// kUseMockData=true seeds the Drift DB with JSON fixtures from assets/mock/
// on first launch (or after a reset). Independent of APP_ENV — you can run
// stage+kUseMockData=true or dev+kUseMockData=false.

enum AppEnv { dev, stage, prod }

const String _envName = String.fromEnvironment(
  'APP_ENV',
  defaultValue: 'dev',
);

const AppEnv kAppEnv = _envName == 'prod'
    ? AppEnv.prod
    : (_envName == 'stage' ? AppEnv.stage : AppEnv.dev);

/// Whether to load mock fixture data from assets/mock/fixtures/ into the DB.
/// Defaults to true when APP_ENV=dev (the development default), false otherwise.
/// Override at build/run time: --dart-define=kUseMockData=false (or =true).
const bool kUseMockData = bool.fromEnvironment(
  'kUseMockData',
  defaultValue: _envName == 'dev',
);

extension AppEnvX on AppEnv {
  /// Whether the BLE/WiFi backend is the in-memory dev mock.
  /// Controls service instantiation only — not data loading (see kUseMockData).
  bool get isDevBackend => this == AppEnv.dev;

  String get label => switch (this) {
    AppEnv.dev => 'dev',
    AppEnv.stage => 'stage',
    AppEnv.prod => 'prod',
  };
}

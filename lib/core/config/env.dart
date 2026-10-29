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
// Data mode (seed / empty) is controlled at runtime via DevConfig
// (SharedPreferences), not at build time. See lib/core/config/dev_config.dart.

enum AppEnv { dev, stage, prod }

const String _envName = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

const AppEnv kAppEnv = _envName == 'prod'
    ? AppEnv.prod
    : (_envName == 'stage' ? AppEnv.stage : AppEnv.dev);

extension AppEnvX on AppEnv {
  /// Whether the BLE/WiFi backend is the in-memory dev mock.
  /// Controls service instantiation only — not data loading (see DevConfig).
  bool get isDevBackend => this == AppEnv.dev;

  /// Whether this build exposes dev tooling (debug page, developer settings).
  /// True for `stage`/`dev`, false for `prod`. APP_ENV is a compile-time const,
  /// so a `prod` build tree-shakes the tooling branch out entirely — there is no
  /// runtime path to reveal it. Drives `shippedOverrides` in the shipped entry.
  bool get showsDevTooling => this != AppEnv.prod;

  String get label => switch (this) {
    AppEnv.dev => 'dev',
    AppEnv.stage => 'stage',
    AppEnv.prod => 'prod',
  };
}

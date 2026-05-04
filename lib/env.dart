// Global environment flag. Drives BLE backend selection and any other
// behaviour that differs between mock data and a real camera.
//
// Override at build/run time:
//   flutter run --dart-define=APP_ENV=dev-mock
//   flutter run --dart-define=APP_ENV=dev-device
//   flutter run --dart-define=APP_ENV=prod
//
// dev-mock   — MockBleService, in-memory data; no real device required.
// dev-device — BleServiceImpl over flutter_blue_plus; real device required.
// prod       — BleServiceImpl; release build.

enum AppEnv { devMock, devDevice, prod }

const String _envName = String.fromEnvironment(
  'APP_ENV',
  defaultValue: 'dev-mock',
);

const AppEnv kAppEnv = _envName == 'prod'
    ? AppEnv.prod
    : (_envName == 'dev-device' ? AppEnv.devDevice : AppEnv.devMock);

extension AppEnvX on AppEnv {
  /// Whether the BLE backend is the in-memory mock.
  bool get isMock => this == AppEnv.devMock;

  String get label => switch (this) {
    AppEnv.devMock => 'dev-mock',
    AppEnv.devDevice => 'dev-device',
    AppEnv.prod => 'prod',
  };
}

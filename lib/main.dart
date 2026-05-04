import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  // BLE backend is selected by `kAppEnv` inside `bleServiceProvider`.
  // Override APP_ENV at build time: --dart-define=APP_ENV=dev-device
  runApp(const ProviderScope(child: ScoutCameraApp()));
}

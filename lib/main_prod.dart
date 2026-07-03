import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/config/shipped_overrides.dart';
import 'core/services/log_service.dart';

/// Shipped entry-point for BOTH published variants (dev and prod APKs). The
/// backend is always the real impl; dev tooling is gated on the compile-time
/// APP_ENV via [shippedOverrides] — `stage` exposes it, `prod` compiles it out.
/// The mock backend lives only in `lib/main.dart` (local dev), never shipped.
Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Capture debugPrint into an in-app ring buffer so the developer Logs viewer
  // works without adb (the Settings > Developer > Logs surface is stage-only).
  LogService.instance.attach();
  LogService.instance.wireLogging();
  Logger('App').info(
    'SST Cam started · env=$kAppEnv · '
    'build=${const String.fromEnvironment('APP_VERSION', defaultValue: 'dev')}',
  );

  final container = ProviderContainer(overrides: shippedOverrides(kAppEnv));

  runApp(
    UncontrolledProviderScope(container: container, child: const SstCamApp()),
  );

  FlutterNativeSplash.remove();
}

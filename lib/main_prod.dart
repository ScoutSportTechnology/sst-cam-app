import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/config/shipped_overrides.dart';

/// Shipped entry-point for BOTH published variants (dev and prod APKs). The
/// backend is always the real impl; dev tooling is gated on the compile-time
/// APP_ENV via [shippedOverrides] — `stage` exposes it, `prod` compiles it out.
/// The mock backend lives only in `lib/main.dart` (local dev), never shipped.
Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  final container = ProviderContainer(overrides: shippedOverrides(kAppEnv));

  runApp(
    UncontrolledProviderScope(container: container, child: const SstCamApp()),
  );

  FlutterNativeSplash.remove();
}

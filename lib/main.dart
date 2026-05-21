import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'mock/mock_data_seeder.dart';
import 'env.dart';
import 'state/db_providers.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Create the provider container early so we can access the DB for seeding
  // before the widget tree starts.
  final container = ProviderContainer();

  if (kUseMockData) {
    try {
      // Trigger the lazy DB open and seed fixture data.
      final db = container.read(appDatabaseProvider);
      await MockDataSeeder(db).seed();
    } catch (e, st) {
      if (kAppEnv.isDevBackend) {
        // In dev mode, rethrow so the error is immediately visible rather than
        // silently starting with missing fixture data.
        rethrow;
      }
      // In stage/prod mode, log visibly but continue — the app starts with
      // base seed only rather than crashing on a fixture error.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'MockDataSeeder',
          context: ErrorDescription('seeding mock fixture data'),
        ),
      );
    }
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SstCamApp(),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'db/mock_data_seeder.dart';
import 'env.dart';
import 'state/db_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Create the provider container early so we can access the DB for seeding
  // before the widget tree starts.
  final container = ProviderContainer();

  if (kUseMockData) {
    try {
      // Trigger the lazy DB open and seed fixture data.
      final db = container.read(appDatabaseProvider);
      await MockDataSeeder(db).seed();
    } catch (e, st) {
      // Log the failure but continue — the app starts with base seed only
      // rather than crashing on a fixture error.
      debugPrint('MockDataSeeder failed: $e\n$st');
    }
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SstCamApp(),
    ),
  );
}

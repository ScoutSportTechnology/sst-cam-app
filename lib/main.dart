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
    // Trigger the lazy DB open and seed fixture data.
    final db = container.read(appDatabaseProvider);
    await MockDataSeeder(db).seed();
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ScoutCameraApp(),
    ),
  );
}

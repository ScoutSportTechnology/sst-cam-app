import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/services/gallery_service.dart';
import 'core/state/db_providers.dart';
import 'mock/mock_data_seeder.dart';

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
        rethrow;
      }
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

  // After the first frame the Flutter engine and MainActivity are fully
  // attached, so platform channels are available. Sync any seeded "on device"
  // match videos to the device gallery (Movies/SSTCam) so users can share them.
  if (kUseMockData) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncSeedVideosToGallery(container);
    });
  }
}

/// Copies seeded mock videos from internal storage to the gallery.
/// Idempotent — MainActivity skips files that are already present in the gallery.
void _syncSeedVideosToGallery(ProviderContainer container) {
  final pathSvc = container.read(videoPathServiceProvider);
  final db = container.read(appDatabaseProvider);
  // Run async without blocking the UI — fire-and-forget.
  // ignore: discarded_futures
  Future(() async {
    // Fetch all past matches and filter in Dart to avoid Drift import bloat.
    final allRows = await db.select(db.teamMatchesTable).get();
    final rows = allRows.where((r) => r.kind == 'past' && r.sizeMb > 0);
    for (final row in rows) {
      final path = await pathSvc.recordingPath(row.id);
      if (File(path).existsSync()) {
        await GalleryService.saveVideo(
          sourcePath: path,
          displayName: '${row.id}.mp4',
        );
      }
    }
  });
}

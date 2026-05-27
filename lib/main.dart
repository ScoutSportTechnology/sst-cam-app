import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/services/gallery_service.dart';
import 'core/state/db_providers.dart';
import 'mock/seed/mock_data_seeder.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  final container = ProviderContainer();

  if (kUseMockData) {
    try {
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

  // After the first frame the engine and MainActivity are fully attached, so
  // platform channels work. Sync seeded "on device" matches to the gallery.
  if (kUseMockData) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncSeedVideosToGallery(container);
    });
  }
}

/// Ensures seeded "on device" match videos are in `Movies/SSTCam/` so they
/// appear in Google Photos and can be shared.
///
/// Steps per match:
///   1. If the internal file is missing or a stale 1-byte sentinel (written
///      before runApp when rootBundle may not have been ready), write the real
///      mock video from the asset bundle now that the engine is up.
///   2. Call GalleryService.saveVideo — idempotent, Kotlin skips the copy if a
///      MediaStore entry with the same filename already exists.
void _syncSeedVideosToGallery(ProviderContainer container) {
  final pathSvc = container.read(videoPathServiceProvider);
  final db = container.read(appDatabaseProvider);
  // ignore: discarded_futures
  Future(() async {
    final allRows = await db.select(db.teamMatchesTable).get();
    final seededRows = allRows.where((r) => r.kind == 'past' && r.sizeMb > 0);

    for (final row in seededRows) {
      final path = await pathSvc.recordingPath(row.id);
      final file = File(path);

      // Write (or rewrite) the internal file if it is absent or too small to
      // be a real video — this handles the race where rootBundle.load failed
      // in main() before runApp() and only a 1-byte sentinel was written.
      if (!file.existsSync() || file.lengthSync() <= 1024) {
        try {
          await file.parent.create(recursive: true);
          final data = await rootBundle.load('assets/ble/mock-video.mp4');
          await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
        } catch (e) {
          debugPrint('_syncSeedVideosToGallery: asset write failed for ${row.id}: $e');
          continue;
        }
      }

      // Copy to gallery (idempotent on the Kotlin side).
      await GalleryService.saveVideo(
        sourcePath: path,
        displayName: '${row.id}.mp4',
      );
    }
  });
}

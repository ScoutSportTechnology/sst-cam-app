import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/dev_config.dart';
import 'core/services/gallery_service.dart';
import 'core/state/db_providers.dart';
import 'mock/seed/mock_data_seeder.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  final devConfig = await DevConfig.load();
  final shouldSeed = devConfig.dataMode != DataMode.empty;

  final container = ProviderContainer();

  if (shouldSeed) {
    try {
      final db = container.read(appDatabaseProvider);
      await MockDataSeeder(db).seed();
    } catch (e, st) {
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
  if (shouldSeed) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncSeedVideosToGallery(container);
    });
  }
}

/// Ensures seeded "on device" match videos are in `Movies/SSTCam/` so they
/// appear in Google Photos and can be shared.
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

      await GalleryService.saveVideo(
        sourcePath: path,
        displayName: '${row.id}.mp4',
      );
    }
  });
}

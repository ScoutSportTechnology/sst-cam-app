import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/ble/ble_providers.dart';
import 'core/config/dev_config.dart';
import 'core/config/dev_navigation.dart';
import 'core/config/dev_reseeder.dart';
import 'core/services/gallery_service.dart';
import 'core/db/app_database.dart';
import 'core/state/db_providers.dart';
import 'core/wifi/wifi_providers.dart';
import 'features/discovery/debug_page.dart';
import 'features/settings/developer/developer_settings_page.dart';
import 'mock/emulator/mock_ble_service.dart';
import 'mock/emulator/mock_wifi_service.dart';
import 'mock/internal/mock_data_service.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  DevConfig devConfig;
  try {
    devConfig = await DevConfig.load();
  } catch (e) {
    // path_provider_android 2.3.x uses JNI directly; if JNI init fails the
    // channel-error propagates here. Fall back to defaults so the app loads.
    debugPrint('DevConfig.load failed, using defaults: $e');
    devConfig = DevConfig.defaults;
  }

  final db = AppDatabase();

  try {
    await applySeedData(db, seed: devConfig.seedData);
  } catch (e, st) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'applySeedData',
        context: ErrorDescription('applying seedData=${devConfig.seedData}'),
      ),
    );
  }

  final bleMock = MockBleService(
    advertiseDevices: devConfig.cameraEmulation,
    serverAddress: devConfig.serverAddress,
    failureRate: 0,
  );
  final wifiMock = MockWifiService(serverAddress: devConfig.serverAddress);

  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      bleServiceProvider.overrideWithValue(bleMock),
      wifiServiceProvider.overrideWithValue(wifiMock),
      devConfigProvider.overrideWithValue(devConfig),
      devReseedProvider.overrideWithValue(
        () async => MockDataSeeder(db).seed(),
      ),
      devNavigationProvider.overrideWithValue(
        DevNavigation(
          debugPage: () => const DebugPage(),
          developerSettings: () => const DeveloperSettingsPage(),
        ),
      ),
    ],
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SstCamApp(),
    ),
  );

  if (devConfig.seedData) {
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
          final data = await rootBundle.load('lib/mock/emulator/mock-video.mp4');
          await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
        } catch (e) {
          debugPrint(
            '_syncSeedVideosToGallery: asset write failed for ${row.id}: $e',
          );
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

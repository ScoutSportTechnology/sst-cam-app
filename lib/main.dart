import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/ble/ble_providers.dart';
import 'core/config/dev_config.dart';
import 'core/config/dev_navigation.dart';
import 'core/config/dev_reseeder.dart';
import 'core/services/gallery_service.dart';
import 'core/services/log_service.dart';
import 'core/db/app_database.dart';
import 'core/state/db_providers.dart';
import 'core/wifi/wifi_providers.dart';
import 'features/discovery/debug_page.dart';
import 'features/settings/developer/developer_settings_page.dart';
import 'mock/emulator/mock_ble_service.dart';
import 'mock/emulator/mock_wifi_service.dart';
import 'mock/internal/mock_data_service.dart';
import 'mock/mock_video_fetcher.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Capture debugPrint into an in-app ring buffer for the developer Logs viewer.
  LogService.instance.attach();

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
    await applySeedData(
      db,
      seed: devConfig.seedData,
      downloadBaseUrl: devConfig.downloadBaseUrl,
    );
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

  // The "Emulate camera" dev toggle picks the BACKEND, not just whether fake
  // devices advertise: ON → mock BLE/WiFi (emulated camera); OFF → fall through
  // to the real BleServiceImpl/WifiServiceImpl provider defaults, so a dev build
  // with emulation off behaves like a stage build (real backend) but keeps the
  // dev tools + seedable data. Takes effect on the next app start (the toggle is
  // staged + applied like the others).
  final overrides = <Override>[
    appDatabaseProvider.overrideWithValue(db),
    devConfigProvider.overrideWithValue(devConfig),
    devReseedProvider.overrideWithValue(
      () async => applySeedData(
        db,
        seed: devConfig.seedData,
        downloadBaseUrl: devConfig.downloadBaseUrl,
      ),
    ),
    devNavigationProvider.overrideWithValue(
      DevNavigation(
        debugPage: () => const DebugPage(),
        developerSettings: () => const DeveloperSettingsPage(),
      ),
    ),
  ];

  if (devConfig.cameraEmulation) {
    final bleMock = MockBleService(
      advertiseDevices: true,
      downloadBaseUrl: devConfig.downloadBaseUrl,
      failureRate: 0,
    );
    final wifiMock = MockWifiService(
      previewBaseUrl: devConfig.previewBaseUrl,
      downloadBaseUrl: devConfig.downloadBaseUrl,
    );
    overrides.add(bleServiceProvider.overrideWithValue(bleMock));
    overrides.add(wifiServiceProvider.overrideWithValue(wifiMock));
  }

  final container = ProviderContainer(overrides: overrides);

  runApp(
    UncontrolledProviderScope(container: container, child: const SstCamApp()),
  );

  if (devConfig.seedData) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncSeedVideosToGallery(container, devConfig.downloadBaseUrl);
    });
  }
}

/// Ensures seeded "on device" match videos are in `Movies/SSTCam/` so they
/// appear in Google Photos and can be shared. The seeder normally materializes
/// these files already; the fetch here is a safety net that reuses the shared
/// container → bundled → sentinel helper before copying to the gallery.
void _syncSeedVideosToGallery(
  ProviderContainer container,
  String downloadBaseUrl,
) {
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
        await fetchVideoOrFallback(
          url: joinBaseUrl(downloadBaseUrl, 'recordings/${row.id}'),
          authToken: 'dev-token',
          savePath: path,
        );
      }

      await GalleryService.saveVideo(
        sourcePath: path,
        displayName: '${row.id}.mp4',
      );
    }
  });
}

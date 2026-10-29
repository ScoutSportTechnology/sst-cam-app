import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'app.dart';
import 'core/ble/ble_providers.dart';
import 'core/config/dev_config.dart';
import 'core/config/dev_navigation.dart';
import 'core/config/dev_reseeder.dart';
import 'core/config/env.dart';
import 'core/config/shipped_overrides.dart';
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

/// Single entry-point for EVERY build. The backend and dev tooling are selected
/// from the compile-time [kAppEnv] — there is no second `main`:
///
/// - `dev`   → dev nav + two togglable flags ([_bootstrapDev]): the mock BLE/WiFi
///   backend (`EMULATE`) and seed fixtures (`SEED`), both default off and each
///   overridable by its in-app Developer switch. Debug mode → fully debuggable.
/// - `stage` → real backend + dev tooling ([shippedOverrides]).
/// - `prod`  → real backend, tooling compiled out ([shippedOverrides] == const []).
///
/// Because [AppEnv.isDevBackend] is a compile-time const, a `stage`/`prod` build
/// evaluates the dev branch as statically-false: [_bootstrapDev] and everything
/// it references (the mock services, `MockDataSeeder`, seed video sync) are
/// unreachable and tree-shaken out of the release binary. This is the
/// "mock never ships" guarantee, mirroring [shippedOverrides]'s tooling shake.
Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Capture debugPrint + package:logging into an in-app ring buffer so the
  // developer Logs viewer works without adb (that surface is dev/stage-only).
  LogService.instance.attach();
  LogService.instance.wireLogging();
  Logger('App').info(
    'SST Cam started · env=${kAppEnv.label} · '
    'build=${const String.fromEnvironment('APP_VERSION', defaultValue: 'dev')}',
  );

  final ProviderContainer container;
  if (kAppEnv.isDevBackend) {
    container = await _bootstrapDev();
  } else {
    // Shipped path (stage/prod): real backend, tooling gated by APP_ENV.
    container = ProviderContainer(overrides: shippedOverrides(kAppEnv));
  }

  runApp(
    UncontrolledProviderScope(container: container, child: const SstCamApp()),
  );
  // Splash is removed by app_shell's first post-frame callback (both paths).
}

/// Builds the dev (mock-backend) provider container: dev config + seedable
/// database + emulated BLE/WiFi + dev navigation. Reachable ONLY from the
/// `kAppEnv.isDevBackend` branch, so a shipped build tree-shakes it entirely.
Future<ProviderContainer> _bootstrapDev() async {
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

  // Force the first DB open — and with it any pending schema migration —
  // OUTSIDE the seed try/catch below. A migration failure must fail LOUDLY
  // here (crash the boot), never be swallowed as a "seed failure": silently
  // continuing over a broken/half-migrated database is how data loss hides.
  await db.customSelect('SELECT 1').get();

  try {
    // Transition-aware: acts only when the seed flag CHANGED (or is on).
    // The steady-state seed-off boot — the deploy-dev-app default — must not
    // touch the DB at all; the imperative applySeedData(seed:false) wipe used
    // to run here every launch and destroyed all user data on each cold start.
    final seedWasApplied = await DevConfig.loadSeedApplied();
    final seedNowApplied = await applySeedDataOnBoot(
      db,
      seed: devConfig.seedData,
      seedWasApplied: seedWasApplied,
      downloadBaseUrl: devConfig.downloadBaseUrl,
    );
    if (seedNowApplied != seedWasApplied) {
      await DevConfig.saveSeedApplied(seedNowApplied);
    }
  } catch (e, st) {
    // Non-fatal: a seed failure must not brick startup. Reporting via
    // FlutterError.reportError here (before runApp) crashed on a stack-trace
    // demangle assertion and left the app stuck on the splash — on a physical
    // phone the seed step can throw where it wouldn't on the emulator. Log it and
    // boot with whatever seeded so the dev build is usable on-device without a
    // camera.
    debugPrint(
      'applySeedData failed (seedData=${devConfig.seedData}): $e\n$st',
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
      // Explicit user action (debug-page reset) — force-apply is intended
      // here, unlike the transition-aware boot path. Keep the applied marker
      // in sync so the next boot doesn't re-run the transition.
      () async {
        await applySeedData(
          db,
          seed: devConfig.seedData,
          downloadBaseUrl: devConfig.downloadBaseUrl,
        );
        await DevConfig.saveSeedApplied(devConfig.seedData);
      },
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
    // Use overrideWith (not overrideWithValue) so Riverpod runs the factory and
    // honours ref.onDispose — otherwise the mocks' scan timers/streams leak on
    // hot-restart (the provider's own dispose hook never registers for a value
    // override).
    overrides.add(
      bleServiceProvider.overrideWith((ref) {
        ref.onDispose(bleMock.dispose);
        return bleMock;
      }),
    );
    overrides.add(
      wifiServiceProvider.overrideWith((ref) {
        ref.onDispose(wifiMock.dispose);
        return wifiMock;
      }),
    );
  }

  final container = ProviderContainer(overrides: overrides);

  if (devConfig.seedData) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncSeedVideosToGallery(container, devConfig.downloadBaseUrl);
    });
  }

  return container;
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

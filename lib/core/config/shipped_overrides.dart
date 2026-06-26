import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/discovery/debug_page.dart';
import '../../features/settings/developer/developer_settings_page.dart';
import 'dev_navigation.dart';
import 'env.dart';

/// Riverpod overrides for a SHIPPED build (the `lib/main_prod.dart` entry).
///
/// The backend is ALWAYS the real `BleServiceImpl`/`WifiServiceImpl` — those
/// providers are left at their defaults and never mocked here (the mock backend
/// lives only in `lib/main.dart`, the local dev entry, which is never shipped).
///
/// Dev tooling (debug page + developer settings) is installed only when the
/// compile-time [AppEnv] enables it ([AppEnvX.showsDevTooling]). A `prod` build
/// returns an empty list, so it has the real backend and zero debug surfaces —
/// and because APP_ENV is a compile-time const, the tooling branch is
/// tree-shaken out of the prod binary entirely (R6/R7).
List<Override> shippedOverrides(AppEnv env) {
  if (!env.showsDevTooling) return const [];
  return [
    devNavigationProvider.overrideWithValue(
      DevNavigation(
        debugPage: () => const DebugPage(),
        developerSettings: () => const DeveloperSettingsPage(),
      ),
    ),
  ];
}

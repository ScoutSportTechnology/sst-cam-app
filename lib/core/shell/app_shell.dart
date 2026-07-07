import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/camera/main_page.dart';
import '../../features/match/match_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/teams/teams_page.dart';
import '../../features/video/video_page.dart';
import '../../features/camera/camera_state.dart' show activeTabProvider;
import '../state/reconnect_controller.dart';
import '../wifi/wifi_handoff.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => FlutterNativeSplash.remove(),
    );
  }

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Main',
    ),
    NavigationDestination(
      icon: Icon(Icons.groups_outlined),
      selectedIcon: Icon(Icons.groups),
      label: 'Teams',
    ),
    NavigationDestination(
      icon: Icon(Icons.scoreboard_outlined),
      selectedIcon: Icon(Icons.scoreboard),
      label: 'Match',
    ),
    NavigationDestination(
      icon: Icon(Icons.video_library_outlined),
      selectedIcon: Icon(Icons.video_library),
      label: 'Video',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  static const _pages = [
    MainPage(),
    TeamsPage(),
    MatchPage(),
    VideoPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    ref.watch(wifiHandoffProvider);
    // U6 auto-reconnect loop — mounted for the app's lifetime alongside the
    // WiFi handoff so an unexpected BLE drop is always observed (Notifiers
    // are lazy; without a reader the loop would never arm).
    ref.watch(reconnectControllerProvider);
    ref.listen<int>(activeTabProvider, (_, i) => setState(() => _index = i));
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          ref.read(activeTabProvider.notifier).state = i;
        },
        destinations: _destinations,
      ),
    );
  }
}

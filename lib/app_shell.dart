import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pages/main_page.dart';
import 'pages/match_page.dart';
import 'pages/settings_page.dart';
import 'pages/teams_page.dart';
import 'pages/video_page.dart';
import 'state/app_data.dart';
import 'state/wifi_handoff.dart';

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
    ref.listen<int>(activeTabProvider, (_, i) => setState(() => _index = i));
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
      ),
    );
  }
}

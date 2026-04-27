import 'package:flutter/material.dart';
import 'presentation/pages/home_page.dart';
import 'presentation/pages/setting_page.dart';

enum AppTab { home, recorded, stream, scoreboard, settings }

// Control the order of tabs here (Map iteration order is not guaranteed)
const List<AppTab> _tabOrder = [
  AppTab.recorded,
  AppTab.stream,
  AppTab.home,
  AppTab.scoreboard,
  AppTab.settings,
];

// Record type for each tab’s config
typedef NavItem = ({
  IconData icon,
  IconData selectedIcon,
  String label,
  Widget page,
});

// Single source of truth
final Map<AppTab, NavItem> _navItems = {
  AppTab.home: (
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: 'Home',
    page: const HomePage(),
  ),
  AppTab.stream: (
    icon: Icons.videocam_outlined,
    selectedIcon: Icons.videocam,
    label: 'Stream',
    page: const Center(child: Text('Stream')),
  ),
  AppTab.recorded: (
    icon: Icons.video_library_outlined,
    selectedIcon: Icons.video_library,
    label: 'Recorded',
    page: const Center(child: Text('Recorded')),
  ),
  AppTab.scoreboard: (
    icon: Icons.scoreboard_outlined,
    selectedIcon: Icons.scoreboard,
    label: 'Scoreboard',
    page: const Center(child: Text('Scoreboard')),
  ),
  AppTab.settings: (
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: 'Settings',
    page: const SettingsPage(),
  ),
};

class AppNavBar extends StatefulWidget {
  const AppNavBar({super.key});
  @override
  AppNavBarState createState() => AppNavBarState();
}

class AppNavBarState extends State<AppNavBar> {
  int index = 2;

  @override
  Widget build(BuildContext context) {
    final currentTab = _tabOrder[index];
    final currentPage = _navItems[currentTab]!.page;

    return Scaffold(
      body: currentPage,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: _tabOrder
            .map(
              (tab) => NavigationDestination(
                icon: Icon(_navItems[tab]!.icon),
                selectedIcon: Icon(_navItems[tab]!.selectedIcon),
                label: _navItems[tab]!.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

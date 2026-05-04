import 'package:flutter/material.dart';
import '../../../features/device_link/presentation/pages/device_scanner_page.dart';

enum SettingsItem {
  bluetoothDevices,
  videoAudio,
  overlay,
  streaming,
  storage,
  preferences,
  about,
}

const List<SettingsItem> _order = <SettingsItem>[
  SettingsItem.bluetoothDevices,
  SettingsItem.videoAudio,
  SettingsItem.overlay,
  SettingsItem.streaming,
  SettingsItem.storage,
  SettingsItem.preferences,
  SettingsItem.about,
];

typedef SettingRowItem = ({IconData icon, String label, Widget page});

final Map<SettingsItem, SettingRowItem> _settingsItems = {
  SettingsItem.bluetoothDevices: (
    icon: Icons.bluetooth,
    label: 'Bluetooth Devices',
    page: const DeviceScannerPage(),
  ),
  SettingsItem.videoAudio: (
    icon: Icons.videocam,
    label: 'Video & Audio',
    page: const Center(child: Text('Video & Audio')),
  ),
  SettingsItem.overlay: (
    icon: Icons.layers,
    label: 'Overlay',
    page: const Center(child: Text('Overlay')),
  ),
  SettingsItem.streaming: (
    icon: Icons.live_tv,
    label: 'Streaming',
    page: const Center(child: Text('Streaming')),
  ),
  SettingsItem.storage: (
    icon: Icons.storage,
    label: 'Storage',
    page: const Center(child: Text('Storage')),
  ),
  SettingsItem.preferences: (
    icon: Icons.settings_suggest_outlined,
    label: 'Preferences',
    page: const Center(child: Text('Preferences')),
  ),
  SettingsItem.about: (
    icon: Icons.info_outline,
    label: 'About',
    page: const Center(child: Text('About')),
  ),
};

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: List.generate(_order.length, (i) {
              final item = _settingsItems[_order[i]]!;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                child: Material(
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: shape,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    customBorder: shape,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Scaffold(body: item.page),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(item.icon, color: theme.colorScheme.onSurface),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Text(item.label, style: text.titleMedium),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

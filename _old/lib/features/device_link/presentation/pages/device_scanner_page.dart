import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../state/device_scanner_controller.dart';
import '../state/device_scanner_state.dart';
import '../state/device_tile.dart';
import '../../../../core/components/permission_banner.dart';
import '../state/bluetooth_off_dialog.dart';
import '../state/device_not_found.dart';

class DeviceScannerPage extends StatefulWidget {
  const DeviceScannerPage({super.key});

  @override
  State<DeviceScannerPage> createState() => _DeviceScannerPageState();
}

class _DeviceScannerPageState extends State<DeviceScannerPage> {
  late final DeviceScannerController _controller = DeviceScannerController();
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    _search.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScanPressed(DeviceScannerState st) async {
    if (st.adapterState != BluetoothAdapterState.on) {
      await showBluetoothOffDialog(
        context,
        onOpenSettings: () => openAppSettings(),
      );
      return;
    }
    if (st.permission == PermissionGateStatus.denied ||
        st.permission == PermissionGateStatus.permanentlyDenied) {
      await _controller.requestPermissions();
      return;
    }
    await _controller.toggleScan();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ValueListenableBuilder<DeviceScannerState>(
      valueListenable: _controller.state,
      builder: (context, st, _) {
        final devices = st.deviceList.where((r) {
          final q = st.query.trim().toLowerCase();
          if (q.isEmpty) return true;
          final name = r.advertisementData.advName.toLowerCase();
          final id = r.device.remoteId.str.toLowerCase();
          return name.contains(q) || id.contains(q);
        }).toList();

        final toast = st.toast;
        if (toast != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final m = ScaffoldMessenger.of(context);
            m.clearSnackBars();
            m.showSnackBar(SnackBar(content: Text(toast)));
            _controller.state.value = _controller.state.value.copyWith(
              toast: null,
            );
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Bluetooth devices'),
            actions: [
              IconButton(
                tooltip: st.isScanning ? 'Stop scan' : 'Start scan',
                onPressed: () => _onScanPressed(st),
                icon: st.isScanning
                    ? const Icon(Icons.stop_circle_outlined)
                    : const Icon(Icons.search),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (st.permission == PermissionGateStatus.denied ||
                  st.permission == PermissionGateStatus.permanentlyDenied) ...[
                PermissionBanner(
                  text:
                      'Bluetooth permission is required to scan nearby devices.',
                  actionLabel: 'Grant permission',
                  onPressed: _controller.requestPermissions,
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _search,
                onChanged: _controller.updateQuery,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search devices',
                ),
              ),
              const SizedBox(height: 12),
              if (st.adapterState == BluetoothAdapterState.on &&
                  st.permission == PermissionGateStatus.granted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    st.isScanning
                        ? 'Scanning…'
                        : 'Tap search to scan for devices',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (devices.isEmpty)
                const DeviceNotFound()
              else
                ...devices.map((r) {
                  final id = r.device.remoteId.str;
                  final isConnected = st.connected.contains(id);
                  final busy = st.busy.contains(id);
                  return Opacity(
                    opacity: busy ? 0.6 : 1.0,
                    child: IgnorePointer(
                      ignoring: busy,
                      child: DeviceTile(
                        result: r,
                        isConnected: isConnected,
                        isSaved: false,
                        onConnectToggle: () => _controller.connectToggle(id),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 24),
            ],
          ),
          floatingActionButton: (st.permission == PermissionGateStatus.granted)
              ? FloatingActionButton.extended(
                  onPressed: () => _onScanPressed(st),
                  icon: Icon(st.isScanning ? Icons.stop : Icons.search),
                  label: Text(st.isScanning ? 'Stop' : 'Scan'),
                )
              : null,
        );
      },
    );
  }
}

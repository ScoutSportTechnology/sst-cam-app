import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/ble_providers.dart';
import '../models/device.dart';

/// Phase 2 — camera list, connection, telemetry, thumbnail polling.
/// Currently shows discovered devices and basic connection state.
class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key});

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage> {
  @override
  void initState() {
    super.initState();
    // Auto-start scan on first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bleServiceProvider).startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(discoveredDevicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scout Camera'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Scan',
            onPressed: () => ref.read(bleServiceProvider).startScan(),
          ),
        ],
      ),
      body: devicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (devices) => devices.isEmpty
            ? const _EmptyState()
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: devices.length,
                itemBuilder: (context, i) =>
                    _DeviceCard(device: devices[i]),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off_outlined, size: 64),
          SizedBox(height: 16),
          Text('No cameras found'),
          SizedBox(height: 8),
          Text('Tap refresh to scan for nearby ScoutCams',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _DeviceCard extends ConsumerWidget {
  const _DeviceCard({required this.device});
  final ScoutDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connAsync = ref.watch(connectionStateProvider(device.id));
    final scheme = Theme.of(context).colorScheme;

    final connState = connAsync.valueOrNull ??
        CameraConnectionState.disconnected;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          Icons.videocam,
          color: connState == CameraConnectionState.connected
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
        title: Text(device.name),
        subtitle: Text('${device.model} · fw ${device.firmwareVersion}'),
        trailing: _ConnectButton(device: device, state: connState),
      ),
    );
  }
}

class _ConnectButton extends ConsumerWidget {
  const _ConnectButton({required this.device, required this.state});
  final ScoutDevice device;
  final CameraConnectionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(bleServiceProvider);

    if (state == CameraConnectionState.connecting ||
        state == CameraConnectionState.disconnecting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final connected = state == CameraConnectionState.connected;
    return FilledButton.tonal(
      onPressed: () => connected
          ? svc.disconnect(device.id)
          : svc.connect(device.id),
      child: Text(connected ? 'Disconnect' : 'Connect'),
    );
  }
}

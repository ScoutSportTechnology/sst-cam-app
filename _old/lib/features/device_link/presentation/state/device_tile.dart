import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Presentational card for a BLE device (no BLE logic inside).
/// - Pass a ScanResult from flutter_blue_plus
/// - Pass connection & saved flags from your page state
/// - Provide a single onConnectToggle callback
class DeviceTile extends StatelessWidget {
  const DeviceTile({
    super.key,
    required this.result,
    required this.isConnected,
    required this.isSaved,
    required this.onConnectToggle,
  });

  final ScanResult result;
  final bool isConnected;
  final bool isSaved;
  final VoidCallback onConnectToggle;

  @override
  Widget build(BuildContext context) {
    final name = _deviceName(result);
    final id = result.device.remoteId.str; // stable identifier

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: _StatusAvatar(isConnected: isConnected, isSaved: isSaved),
        title: Text(name),
        subtitle: Text(id),
        trailing: FilledButton.tonal(
          onPressed: onConnectToggle,
          child: Text(isConnected ? 'Disconnect' : 'Connect'),
        ),
      ),
    );
  }

  String _deviceName(ScanResult r) {
    final advName = r.advertisementData.advName;
    if (advName.isNotEmpty) return advName;
    // Fallback: some devices don’t broadcast a name
    return 'Unknown';
  }
}

class _StatusAvatar extends StatelessWidget {
  const _StatusAvatar({required this.isConnected, required this.isSaved});
  final bool isConnected;
  final bool isSaved;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Choose icon based on state
    final IconData icon = isConnected
        ? Icons.bluetooth_connected
        : (isSaved ? Icons.bluetooth_disabled : Icons.videocam);

    // Subtle tint for the circle background; stronger when connected
    final bg = isConnected
        ? scheme.primary.withValues(alpha: 0.18)
        : scheme.onSurfaceVariant.withValues(alpha: 0.10);

    final fg = isConnected ? scheme.primary : scheme.onSurfaceVariant;

    return CircleAvatar(
      backgroundColor: bg,
      foregroundColor: fg,
      child: Icon(icon),
    );
  }
}

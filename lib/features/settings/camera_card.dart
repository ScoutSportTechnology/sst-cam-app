// Connected-camera card for the Settings page — identity, fw/proto line,
// Reboot / Upgrade / Disconnect actions. Split from settings_page.dart;
// behavior is unchanged.
//
// Reboot and Update fw remain visual placeholders until firmware lands; they
// render disabled with a tooltip explaining that. fw / proto values are real:
// firmware from the device's firmwareVersion, proto from the built-against
// repo tag + the wire protocol_version.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_providers.dart';
import '../../core/models/command.dart';
import '../../core/state/reconnect_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/version/version_info.dart';
import '../../core/widgets/wf_button.dart';
import '../../core/widgets/wf_card.dart';

class SettingsCameraCard extends ConsumerWidget {
  const SettingsCameraCard({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Real firmware version from the connected camera's DeviceInfo (the
    // scan-time SstDevice carries empty fw). proto = the built-against repo tag.
    // The wire protocol_version is technical — it lives in Diagnostics, not here.
    final info = ref.watch(connectedDeviceInfoProvider(deviceId)).valueOrNull;
    final fwRaw = info?.firmwareVersion ?? '';
    final fw = fwRaw.isEmpty ? '—' : fwRaw;
    final protoLine = 'proto $protoRepoVersion';

    return WfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const WfNote('Connected camera'),
                    const SizedBox(height: 4),
                    Text(
                      deviceId,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: T.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'fw $fw · $protoLine',
                      style: const TextStyle(
                        fontFamily: T.mono,
                        fontSize: 11,
                        color: T.ink2,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: T.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: WfButton(
                  label: 'Reboot',
                  size: WfButtonSize.sm,
                  // Connected => protocol 3 (exact-match version gate), so the
                  // reboot command surface is guaranteed present. Disabled only
                  // while DeviceInfo is still loading.
                  onPressed: info == null
                      ? null
                      : () => _confirmReboot(context, ref),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: WfButton(
                  label: 'Upgrade',
                  size: WfButtonSize.sm,
                  onPressed: () => _showUpgradeInfo(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Disconnect — Diagnostics now lives in the Settings list as its own
          // row (Settings → Diagnostics), not buried on the camera card.
          WfButton(
            label: 'Disconnect',
            variant: WfButtonVariant.danger,
            size: WfButtonSize.sm,
            full: true,
            onPressed: () => _disconnect(ref, deviceId),
          ),
        ],
      ),
    );
  }

  /// Drop the BLE link only — the camera stays in the known list so a
  /// subsequent one-tap reconnect from the empty state works without
  /// rescanning. Per R4. Routed through the reconnect controller so the
  /// auto-reconnect loop never treats this drop as unexpected (U6).
  Future<void> _disconnect(WidgetRef ref, String deviceId) async {
    await ref
        .read(reconnectControllerProvider.notifier)
        .manualDisconnect(deviceId);
  }

  /// Confirm, then send RebootCommand (U11). The camera replies OK and then
  /// goes down, so a timeout here is success (the link dropped), not failure.
  Future<void> _confirmReboot(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reboot camera?'),
        content: const Text(
          'The camera will restart and briefly disconnect. Any recording or '
          'streaming in progress will stop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reboot'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    String message;
    try {
      final resp = await ref
          .read(bleServiceProvider)
          .sendCommand<void>(deviceId, RebootCommand());
      final reached =
          resp.status == BleResponseStatus.ok ||
          resp.status == BleResponseStatus.timeout;
      message = reached
          ? 'Reboot sent — the camera is restarting.'
          : 'Camera could not reboot (${resp.status.name}).';
    } catch (_) {
      // A dropped link mid-send is the camera going down — treat as sent.
      message = 'Reboot sent — the camera is restarting.';
    }
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// OTA firmware upgrade isn't built yet (R14); point at the on-device path.
  void _showUpgradeInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Firmware upgrade'),
        content: const Text(
          'Over-the-air upgrade is not available yet. Update the camera '
          'firmware on the Jetson with deploy/install.sh (see the firmware repo).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

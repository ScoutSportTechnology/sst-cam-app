import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/device.dart';
import '../state/app_data.dart';
import '../state/ble_providers.dart';
import '../state/last_camera.dart';
import '../core/theme/tokens.dart';
import '../core/widgets/indicators.dart';
import '../core/widgets/wf_button.dart';
import '../core/widgets/wf_card.dart';

/// Scan & connect flow. Reachable from Settings → "Connect a different camera".
class DiscoveryPage extends ConsumerStatefulWidget {
  const DiscoveryPage({super.key});

  @override
  ConsumerState<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends ConsumerState<DiscoveryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bleServiceProvider).startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(discoveredDevicesProvider).valueOrNull ?? [];
    final scanning = ref.watch(bleServiceProvider).isScanning;

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: const Text('Connect a camera')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: Row(
              children: [
                _ScanIndicator(active: scanning),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scanning ? 'Scanning for cameras' : 'Idle',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: T.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Filter: sst-cam-*',
                        style: TextStyle(
                          fontSize: 11,
                          color: T.ink2,
                          fontFamily: T.mono,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final svc = ref.read(bleServiceProvider);
                    if (scanning) {
                      svc.stopScan();
                    } else {
                      svc.startScan();
                    }
                    setState(() {});
                  },
                  child: Text(scanning ? 'Stop' : 'Scan'),
                ),
              ],
            ),
          ),
          const WfSection('Found nearby'),
          if (devices.isEmpty && !scanning)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: WfNote('No cameras found yet')),
            ),
          ...devices.map((d) => _DeviceRow(device: d)),
          const WfSection('Help'),
          const Padding(
            padding: EdgeInsets.all(16),
            child: WfCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Can't see your camera?",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: T.ink,
                    ),
                  ),
                  SizedBox(height: 6),
                  WfNote('• Power on the Jetson and wait ~10s for advertising'),
                  WfNote('• Check Bluetooth permission for this app'),
                  WfNote('• Stay within ~10 m line-of-sight'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanIndicator extends StatefulWidget {
  const _ScanIndicator({required this.active});
  final bool active;

  @override
  State<_ScanIndicator> createState() => _ScanIndicatorState();
}

class _ScanIndicatorState extends State<_ScanIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctl,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.active ? T.accent : T.hair,
            width: 2,
          ),
        ),
        foregroundDecoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              widget.active ? T.accent : T.hair,
              Colors.transparent,
              Colors.transparent,
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceRow extends ConsumerWidget {
  const _DeviceRow({required this.device});
  final SstDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState =
        ref.watch(connectionStateProvider(device.id)).valueOrNull ??
        CameraConnectionState.disconnected;
    final connected = connState == CameraConnectionState.connected;
    final connecting = connState == CameraConnectionState.connecting;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const Border(
        bottom: BorderSide(color: T.rule),
      ).toBoxDecoration(),
      child: Row(
        children: [
          const SignalIndicator(bars: 4, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: T.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${device.model} · fw ${device.firmwareVersion}',
                  style: const TextStyle(fontSize: 11, color: T.ink2),
                ),
              ],
            ),
          ),
          if (connecting)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(T.accent),
              ),
            )
          else
            WfButton(
              label: connected ? 'Disconnect' : 'Connect',
              variant: connected
                  ? WfButtonVariant.outline
                  : WfButtonVariant.primary,
              size: WfButtonSize.sm,
              onPressed: () async {
                final svc = ref.read(bleServiceProvider);
                if (connected) {
                  await svc.disconnect(device.id);
                  ref.read(activeCameraIdProvider.notifier).state = null;
                } else {
                  try {
                    await svc.connect(device.id);
                    ref.read(activeCameraIdProvider.notifier).state = device.id;
                    // Persist the last successfully-connected camera id so
                    // the Settings empty-state CTA can offer a one-tap
                    // reconnect on next launch / after disconnect.
                    // Best-effort — failure to persist must not break the
                    // connect flow.
                    unawaited(
                      ref
                          .read(lastConnectedDeviceIdProvider.notifier)
                          .set(device.id),
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  } catch (_) {
                    // Surface failures via SnackBar; UI stays put.
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Connection failed — retry?'),
                        ),
                      );
                    }
                  }
                }
              },
            ),
        ],
      ),
    );
  }
}

extension on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}

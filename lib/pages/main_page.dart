import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../models/telemetry.dart';
import '../state/app_data.dart';
import '../state/ble_providers.dart';
import '../theme/tokens.dart';
import '../widgets/indicators.dart';
import '../widgets/wf_button.dart';
import '../widgets/wf_card.dart';

/// Main tab — hero camera card + telemetry grid.
/// Discovery is intentionally not here; it lives in Settings.
class MainPage extends ConsumerWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeCameraIdProvider);

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: const Text('Main'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.more_vert),
          ),
        ],
      ),
      body: activeId == null
          ? const _NoCameraState()
          : _ConnectedView(deviceId: activeId),
    );
  }
}

class _NoCameraState extends StatelessWidget {
  const _NoCameraState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined, size: 56, color: T.ink3),
            const SizedBox(height: 14),
            const Text(
              'No camera connected',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: T.ink,
              ),
            ),
            const SizedBox(height: 6),
            const WfNote(
              'Pair a ScoutCam from Settings to see live telemetry.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedView extends ConsumerWidget {
  const _ConnectedView({required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telemetry = ref.watch(telemetryProvider(deviceId)).valueOrNull;
    final connState = ref.watch(connectionStateProvider(deviceId)).valueOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        _HeroCameraCard(
          deviceId: deviceId,
          isLive: connState == CameraConnectionState.connected,
          isRecording: telemetry?.isRecording ?? false,
        ),
        const SizedBox(height: 14),
        const WfSection('Telemetry', padding: EdgeInsets.only(bottom: 8)),
        _TelemetryGrid(telemetry: telemetry),
        const SizedBox(height: 16),
        const Center(child: WfNote('One camera at a time · pull-model BLE')),
      ],
    );
  }
}

class _HeroCameraCard extends ConsumerWidget {
  const _HeroCameraCard({
    required this.deviceId,
    required this.isLive,
    required this.isRecording,
  });
  final String deviceId;
  final bool isLive;
  final bool isRecording;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        border: Border.all(color: T.hair, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ThumbPlaceholder(label: 'LIVE THUMBNAIL'),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'sst-cam-01',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: T.ink,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'XX:XX:XX:01 · fw 0.3.2',
                            style: TextStyle(
                              fontSize: 11,
                              color: T.ink2,
                              fontFamily: T.mono,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isLive ? T.accent : T.ink3,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isLive ? 'LIVE' : 'IDLE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isLive ? T.accent : T.ink3,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: WfButton(
                        label: 'Open match',
                        variant: WfButtonVariant.primary,
                        onPressed: () =>
                            DefaultTabController.maybeOf(context)?.animateTo(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    WfButton(
                      label: 'Disconnect',
                      onPressed: () {
                        ref.read(bleServiceProvider).disconnect(deviceId);
                        ref.read(activeCameraIdProvider.notifier).state = null;
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TelemetryGrid extends StatelessWidget {
  const _TelemetryGrid({required this.telemetry});
  final DeviceTelemetry? telemetry;

  @override
  Widget build(BuildContext context) {
    final battery = _battery(telemetry);
    final storage = _storage(telemetry);
    final wifi = _wifi(telemetry);
    final temp = _temp(telemetry);

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 2.2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _TelemetryTile(
          label: 'Battery',
          value: battery.value,
          accessory: BatteryIndicator(level: battery.level),
        ),
        _TelemetryTile(label: 'Storage', value: storage),
        _TelemetryTile(
          label: 'WiFi',
          value: wifi.value,
          accessory: SignalIndicator(bars: wifi.bars),
        ),
        _TelemetryTile(label: 'Temp', value: temp),
      ],
    );
  }

  ({String value, double level}) _battery(DeviceTelemetry? t) {
    // Telemetry doesn't expose battery directly yet — use a stand-in.
    if (t == null) return (value: '—', level: 0.0);
    final pct = (1 - t.cpuUsedPct).clamp(0.0, 1.0);
    return (value: '${(pct * 100).round()}%', level: pct);
  }

  String _storage(DeviceTelemetry? t) {
    if (t == null) return '—';
    final freeGb = t.storageFreeBytes / (1024 * 1024 * 1024);
    return '${freeGb.toStringAsFixed(0)} GB free';
  }

  ({String value, int bars}) _wifi(DeviceTelemetry? t) {
    if (t == null || t.wifiState != WifiState.connected) {
      return (value: 'Off', bars: 0);
    }
    final dbm = t.wifiSignalDbm ?? -90;
    final bars = dbm > -55
        ? 4
        : dbm > -65
        ? 3
        : dbm > -75
        ? 2
        : 1;
    return (value: 'AP · ready', bars: bars);
  }

  String _temp(DeviceTelemetry? t) {
    if (t == null) return '—';
    return '${t.tempCelsius.toStringAsFixed(0)} °C';
  }
}

class _TelemetryTile extends StatelessWidget {
  const _TelemetryTile({
    required this.label,
    required this.value,
    this.accessory,
  });
  final String label;
  final String value;
  final Widget? accessory;

  @override
  Widget build(BuildContext context) {
    return WfCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [WfNote(label), if (accessory != null) accessory!],
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: T.ink,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

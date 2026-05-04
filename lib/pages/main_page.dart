// ignore_for_file: constant_identifier_names

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../models/telemetry.dart';
import '../state/app_data.dart';
import '../state/ble_providers.dart';
import '../theme/tokens.dart';
import '../widgets/indicators.dart';
import '../widgets/live_preview_view.dart';
import '../widgets/wf_button.dart';
import '../widgets/wf_card.dart';
import 'discovery_page.dart';

/// Main tab — hero camera card + telemetry grid.
/// Layout is identical whether or not a camera is connected; the hero card
/// swaps its action row and the telemetry tiles fall back to placeholders.
class MainPage extends ConsumerWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeCameraIdProvider);
    final telemetry = activeId == null
        ? null
        : ref.watch(telemetryProvider(activeId)).valueOrNull;
    final connState = activeId == null
        ? null
        : ref.watch(connectionStateProvider(activeId)).valueOrNull;
    final discovered =
        ref.watch(discoveredDevicesProvider).valueOrNull ??
        const <ScoutDevice>[];
    final device = activeId == null
        ? null
        : discovered.where((d) => d.id == activeId).firstOrNull;

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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          _HeroCameraCard(
            deviceId: activeId,
            device: device,
            isLive: connState == CameraConnectionState.connected,
          ),
          const SizedBox(height: 14),
          const WfSection('Telemetry', padding: EdgeInsets.only(bottom: 8)),
          _TelemetryGrid(telemetry: telemetry),
          const SizedBox(height: 16),
          const Center(child: WfNote('One camera at a time')),
        ],
      ),
    );
  }
}

class _HeroCameraCard extends ConsumerWidget {
  const _HeroCameraCard({
    required this.deviceId,
    required this.device,
    required this.isLive,
  });
  final String? deviceId;
  final ScoutDevice? device;
  final bool isLive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = deviceId != null && isLive;
    final name = device?.name ?? 'No camera';
    final id = deviceId ?? '—';
    final fwRaw = device?.firmwareVersion ?? '';
    final fw = fwRaw.isEmpty ? '—' : fwRaw;

    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        border: Border.all(color: T.hair, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LivePreviewView(deviceId: deviceId, label: 'LIVE THUMBNAIL'),
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
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: T.ink,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$id · fw $fw',
                            style: const TextStyle(
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
                            color: connected ? T.accent : T.ink3,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          connected ? 'LIVE' : 'IDLE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: connected ? T.accent : T.ink3,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (connected)
                  Row(
                    children: [
                      Expanded(
                        child: WfButton(
                          label: 'Open match',
                          variant: WfButtonVariant.primary,
                          onPressed: () => DefaultTabController.maybeOf(
                            context,
                          )?.animateTo(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      WfButton(
                        label: 'Disconnect',
                        onPressed: () {
                          ref.read(bleServiceProvider).disconnect(deviceId!);
                          ref.read(activeCameraIdProvider.notifier).state =
                              null;
                        },
                      ),
                    ],
                  )
                else
                  WfButton(
                    label: 'Connect camera',
                    variant: WfButtonVariant.primary,
                    full: true,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DiscoveryPage(),
                        ),
                      );
                    },
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
  static const IconSize = 15.0;

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
      childAspectRatio: 2.0,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _TelemetryTile(
          label: 'Battery',
          value: battery.value,
          accessory: BatteryIndicator(
            level: battery.level,
            size: _TelemetryGrid.IconSize,
          ),
        ),
        _TelemetryTile(
          label: 'Storage',
          value: storage,
          accessory: const Icon(
            Icons.perm_media_outlined,
            size: _TelemetryGrid.IconSize * 1.8,
            color: T.ink2,
          ),
        ),
        _TelemetryTile(
          label: 'WiFi',
          value: wifi.value,
          accessory: SignalIndicator(
            bars: wifi.bars,
            size: _TelemetryGrid.IconSize,
          ),
        ),
        _TelemetryTile(
          label: 'Temp',
          value: temp,
          accessory: Transform.rotate(
            angle: -math.pi / 2,
            child: const Icon(
              Icons.thermostat_outlined,
              size: _TelemetryGrid.IconSize * 1.8,
              color: T.ink2,
            ),
          ),
        ),
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
    if (t == null) return (value: '—', bars: 0);
    if (t.wifiState != WifiState.connected) return (value: 'Off', bars: 0);
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
          SizedBox(
            height: _TelemetryGrid.IconSize * 1.8,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: WfNote(label)),
                ?accessory,
              ],
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

// ignore_for_file: constant_identifier_names

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/device.dart';
import '../../core/models/telemetry.dart';
import 'camera_state.dart'
    show activeCameraIdProvider, activeTabProvider, AppTab;
import '../../core/ble/ble_providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/indicators.dart';
import '../../core/widgets/live_preview_view.dart';
import '../../core/widgets/output_camera_toggle.dart';
import '../../core/widgets/preview_layout_toggle.dart';
import '../../core/widgets/wf_button.dart';
import '../../core/widgets/wf_card.dart';
import '../../core/wifi/wifi_providers.dart' show livePreviewEnabledProvider;
import '../discovery/discovery_page.dart';

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
        ref.watch(discoveredDevicesProvider).valueOrNull ?? const <SstDevice>[];
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
  final SstDevice? device;
  final bool isLive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = deviceId != null && isLive;
    final name = device?.name ?? 'No camera';
    final id = deviceId ?? '—';
    // Real firmware from the connected camera's DeviceInfo — the scan-time
    // SstDevice carries an empty firmwareVersion (matches the settings card).
    final info = deviceId == null
        ? null
        : ref.watch(connectedDeviceInfoProvider(deviceId!)).valueOrNull;
    final fwRaw = info?.firmwareVersion ?? '';
    final fw = fwRaw.isEmpty ? '—' : fwRaw;

    final previewOn = ref.watch(livePreviewEnabledProvider(deviceId));
    // Only the visible tab's preview surface holds an RTSP/VLC client (two on
    // one single-stream server stalls the second — home vs match both stay
    // mounted in the shell's IndexedStack).
    final onMainTab = ref.watch(activeTabProvider) == AppTab.main;

    // Real camera state from telemetry flags, not connection alone. The dot was
    // green "LIVE" whenever connected even while idle — misleading. Precedence
    // Streaming > Recording > Preview > Standby > Disconnected.
    final telemetry = deviceId == null
        ? null
        : ref.watch(telemetryProvider(deviceId!)).valueOrNull;
    final (camLabel, camColor) = cameraHeroState(
      connected: connected,
      previewOn: previewOn,
      telemetry: telemetry,
    );

    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        border: Border.all(color: T.hair, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video surface — buttons are in the action row below, not overlaid.
          LivePreviewView(
            deviceId: deviceId,
            label: 'LIVE THUMBNAIL',
            showButtons: false,
            paused: !onMainTab,
          ),
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
                            color: camColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          camLabel.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: camColor,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (connected) ...[
                  // Preview controls inline — Preview button + Single|Both mode
                  // toggle in two equal columns, mirroring the match session
                  // screen so widths and right edges line up.
                  Row(
                    children: [
                      Expanded(
                        child: WfButton(
                          label: previewOn ? 'Stop preview' : 'Preview',
                          variant: previewOn
                              ? WfButtonVariant.danger
                              : WfButtonVariant.outline,
                          size: WfButtonSize.sm,
                          full: true,
                          leading: previewOn
                              ? null
                              : const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 13,
                                  color: T.ink,
                                ),
                          onPressed: () {
                            ref
                                    .read(
                                      livePreviewEnabledProvider(
                                        deviceId,
                                      ).notifier,
                                    )
                                    .state =
                                !previewOn;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: previewOn
                            ? PreviewLayoutToggle(
                                deviceId: deviceId,
                                full: true,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  if (previewOn) ...[
                    const SizedBox(height: 8),
                    OutputCameraToggle(deviceId: deviceId, full: true),
                  ],
                  const SizedBox(height: 8),
                  // Primary: open match tab. Full-width md — equal height/width
                  // with Disconnect below.
                  WfButton(
                    label: 'Open match',
                    variant: WfButtonVariant.primary,
                    full: true,
                    // The shell is a NavigationBar + IndexedStack driven by
                    // activeTabProvider — there is no DefaultTabController in the
                    // tree, so maybeOf() returned null and the button no-op'd.
                    // Match is tab index 2; its landing offers "Schedule a match"
                    // when none exist.
                    onPressed: () =>
                        ref.read(activeTabProvider.notifier).state = 2,
                  ),
                  const SizedBox(height: 8),
                  // Disconnect — danger (red), full-width: equal height/width
                  // with Open match (the unequal-button fix from the match card).
                  WfButton(
                    label: 'Disconnect',
                    variant: WfButtonVariant.danger,
                    full: true,
                    onPressed: () {
                      ref.read(bleServiceProvider).disconnect(deviceId!);
                      ref.read(activeCameraIdProvider.notifier).state = null;
                    },
                  ),
                ] else
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

/// Maps connection + preview + telemetry flags to the hero-card status label and
/// color. Precedence: Streaming > Recording > Preview > Standby > Disconnected.
/// Connection gates all live states, so an inconsistent flag combination (e.g.
/// recording reported while disconnected) resolves to Disconnected.
(String, Color) cameraHeroState({
  required bool connected,
  required bool previewOn,
  required DeviceTelemetry? telemetry,
}) {
  if (!connected) return ('Disconnected', T.ink3);
  if (telemetry?.isStreaming ?? false) return ('Streaming', T.ok);
  if (telemetry?.isRecording ?? false) return ('Recording', T.danger);
  if (previewOn) return ('Preview', T.accent);
  return ('Standby', T.warn);
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
    // Firmware reports battery via DeviceTelemetry.batteryLevelPct (0–100),
    // null when the device has no battery.
    if (t == null || t.batteryLevelPct == null) return (value: '—', level: 0.0);
    final pct = (t.batteryLevelPct! / 100.0).clamp(0.0, 1.0);
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

// The manual "Record raw footage (training)" button was removed: the dual-camera
// training proxy is internal/training-only and runs automatically, coupled to the
// match RECORD lifecycle — the app mints a capture_group_id and sends it on the
// RecordingControlCommand START (session_screen), and the firmware starts/stops
// the per-camera proxy alongside the recording (U5/U6). It is NOT tied to
// streaming (a stream-only match has nothing to train on).

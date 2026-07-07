// ignore_for_file: constant_identifier_names

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/device.dart';
import '../../core/models/telemetry.dart';
import 'camera_state.dart'
    show
        activeCameraIdProvider,
        activeTabProvider,
        modalPreviewActiveProvider,
        AppTab;
import '../../core/ble/ble_providers.dart';
import '../../core/state/device_health.dart' show captureBlockedProvider;
import '../../core/theme/tokens.dart';
import '../../core/widgets/device_health_banner.dart';
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
      // Compact enough to fit a phone viewport without scrolling (the point of
      // #1 — telemetry was trimmed to a flatter 2×2 so the hero + stats fit).
      // Kept in a SingleChildScrollView rather than a bare Column so a genuinely
      // short viewport (split-screen, small device, landscape) scrolls gracefully
      // instead of throwing a RenderFlex overflow — on a normal phone it fits, so
      // it never actually scrolls.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          children: [
            _HeroCameraCard(
              deviceId: activeId,
              device: device,
              isLive: connState == CameraConnectionState.connected,
            ),
            // U3 health surface — inoperable banner / recovering note. Shown
            // here because this page hosts the preview action.
            const DeviceHealthNotice(margin: EdgeInsets.only(top: 8)),
            const SizedBox(height: 12),
            const WfSection('Telemetry', padding: EdgeInsets.only(bottom: 8)),
            _TelemetryGrid(telemetry: telemetry),
            const SizedBox(height: 8),
            const Center(child: WfNote('One camera at a time')),
          ],
        ),
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
    // U3 health gate: starting a preview is blocked while the device is
    // inoperable (or health is unknown while connected). Stopping stays
    // allowed. One shared provider — no per-page divergence.
    final captureBlocked = ref.watch(captureBlockedProvider);
    // Only the visible tab's preview surface holds an RTSP/VLC client (two on
    // one single-stream server stalls the second — home vs match both stay
    // mounted in the shell's IndexedStack).
    final onMainTab = ref.watch(activeTabProvider) == AppTab.main;
    // A pushed full-screen preview (e.g. calibration) claims the sole RTSP client;
    // release the hero's while it's up so we never run two on the single stream.
    final modalPreview = ref.watch(modalPreviewActiveProvider);

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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Video surface — buttons are in the action row below, not overlaid.
          LivePreviewView(
            deviceId: deviceId,
            label: 'LIVE THUMBNAIL',
            showButtons: false,
            paused: !onMainTab || modalPreview,
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
                const SizedBox(height: 10),
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
                          onPressed: (captureBlocked && !previewOn)
                              ? null
                              : () {
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
                  // Open match + Disconnect share one row (were two stacked
                  // full-width buttons) to keep the hero card inside the phone
                  // viewport without scrolling. Match is tab index 2; the shell
                  // is a NavigationBar + IndexedStack driven by activeTabProvider
                  // (no DefaultTabController, so maybeOf() would return null).
                  Row(
                    children: [
                      Expanded(
                        child: WfButton(
                          label: 'Open match',
                          variant: WfButtonVariant.primary,
                          full: true,
                          onPressed: () =>
                              ref.read(activeTabProvider.notifier).state = 2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: WfButton(
                          label: 'Disconnect',
                          variant: WfButtonVariant.danger,
                          full: true,
                          onPressed: () {
                            ref.read(bleServiceProvider).disconnect(deviceId!);
                            ref.read(activeCameraIdProvider.notifier).state =
                                null;
                          },
                        ),
                      ),
                    ],
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
    final cpu = _cpu(telemetry);
    final temp = _temp(telemetry);

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 6,
      mainAxisSpacing: 6,
      // Slightly flatter than default so the four stats fit under the hero, but
      // tall enough for the label row + value (2.6 clipped the content by 11px).
      childAspectRatio: 2.3,
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
          label: 'CPU',
          value: cpu,
          accessory: const Icon(
            Icons.memory,
            size: _TelemetryGrid.IconSize * 1.8,
            color: T.ink2,
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

  String _cpu(DeviceTelemetry? t) {
    // cpuUsedPct is already a 0–100 percent from the firmware CPU-busy probe
    // (CpuBusyPercent → [0,100]) — display it directly. Multiplying by 100 read
    // 61.79% as "6179%".
    if (t == null) return '—';
    return '${t.cpuUsedPct.round()}%';
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
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            height: _TelemetryGrid.IconSize * 1.5,
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
              fontSize: 16,
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

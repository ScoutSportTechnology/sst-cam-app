import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_providers.dart';
import '../../core/config/dev_navigation.dart';
import '../../core/models/command.dart' show DeviceInfoResponse;
import '../../core/models/telemetry.dart';
import '../../core/theme/tokens.dart';
import '../../core/version/version_info.dart';
import '../../core/widgets/wf_card.dart';
import '../../core/widgets/wf_chip.dart';
import '../settings/developer/log_viewer_page.dart';

/// Diagnostics — real camera telemetry + app build info, side by side. Replaces
/// the old mock page (fabricated MTU/RSSI/command-log). Camera metrics come from
/// the live telemetry poll; nothing here is invented. Fields the firmware does
/// not report yet (battery without a sensor, wifi RSSI) render "—" rather than a
/// fake number.
/// Lines the live "Camera link" log view keeps — the BLE/WiFi comms the app
/// captures (commands, responses, preview, streaming, p2p). Interim until the
/// firmware streams its own logs over the wire.
bool isCameraLinkLog(String line) {
  final l = line.toLowerCase();
  const needles = [
    'ble',
    'gatt',
    'mtu',
    'wifi',
    'p2p',
    'rtmp',
    'rtsp',
    'preview',
    'telemetry',
    'command',
    'connect',
    'session',
    'handoff',
    'finalize',
    'overlay',
    'stream',
    'camera',
    'dnsmasq',
    'download',
  ];
  for (final n in needles) {
    if (l.contains(n)) return true;
  }
  return false;
}

class DiagnosticsPage extends ConsumerWidget {
  const DiagnosticsPage({super.key, this.deviceId});

  /// Connected camera id, or null when opened with no camera connected (the
  /// top-level Settings → Diagnostics entry). The App section always renders;
  /// the Camera section shows a connect prompt when null.
  final String? deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = deviceId;
    final telemetry = id == null
        ? null
        : ref.watch(telemetryProvider(id)).valueOrNull;
    final info = id == null
        ? null
        : ref.watch(connectedDeviceInfoProvider(id)).valueOrNull;

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: const Text('Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          const WfSection('Camera', padding: EdgeInsets.only(bottom: 8)),
          _CameraDiagnostics(telemetry: telemetry, info: info),
          const SizedBox(height: 18),
          const WfSection('App', padding: EdgeInsets.only(bottom: 8)),
          const _AppDiagnostics(),
        ],
      ),
    );
  }
}

class _CameraDiagnostics extends StatelessWidget {
  const _CameraDiagnostics({required this.telemetry, required this.info});
  final DeviceTelemetry? telemetry;
  final DeviceInfoResponse? info;

  @override
  Widget build(BuildContext context) {
    final t = telemetry;
    if (t == null) {
      // Disconnected / no telemetry yet — a single note, not a grid of zeros.
      return const WfCard(
        child: WfNote('Connect to a camera to view diagnostics'),
      );
    }

    final fw = (info?.firmwareVersion.isNotEmpty ?? false)
        ? info!.firmwareVersion
        : '—';
    // The wire protocol_version (a skew counter) lives here, not on the camera
    // card — it's a technical value, not user-facing version info.
    final wire = info == null ? '—' : 'v${info!.protocolVersion}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WfCard(
          child: Row(
            children: [
              Expanded(child: _kv('Firmware', fw)),
              Expanded(child: _kv('Wire proto', wire)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 2.4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _StatTile(label: 'Storage free', value: _storage(t)),
            _StatTile(
              label: 'Temperature',
              value: '${t.tempCelsius.toStringAsFixed(0)} °C',
            ),
            _StatTile(
              label: 'CPU',
              value: '${t.cpuUsedPct.toStringAsFixed(0)} %',
            ),
            _StatTile(
              label: 'RAM',
              value: '${t.ramUsedPct.toStringAsFixed(0)} %',
            ),
            _StatTile(label: 'Uptime', value: _uptime(t.uptimeSeconds)),
            _StatTile(label: 'Battery', value: _battery(t)),
            _StatTile(label: 'WiFi', value: _wifi(t)),
            _StatTile(label: 'WiFi RSSI', value: _rssi(t)),
            _StatTile(
              label: 'Internet',
              value: t.internetReachable ? 'Online' : 'Offline',
            ),
          ],
        ),
        const SizedBox(height: 8),
        WfCard(
          child: Row(
            children: [
              const Expanded(child: WfNote('Activity')),
              WfChip(label: 'Rec', active: t.isRecording),
              const SizedBox(width: 6),
              WfChip(label: 'Stream', active: t.isStreaming),
              const SizedBox(width: 6),
              WfChip(label: 'Raw', active: t.isRawCapturing),
            ],
          ),
        ),
      ],
    );
  }

  String _storage(DeviceTelemetry t) {
    final freeGb = t.storageFreeBytes / (1024 * 1024 * 1024);
    final totalGb = t.storageTotalBytes / (1024 * 1024 * 1024);
    return '${freeGb.toStringAsFixed(0)} / ${totalGb.toStringAsFixed(0)} GB';
  }

  String _uptime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  // Battery / RSSI are null when the firmware does not report them (no sensor /
  // not wired) — render "—", never a fabricated value (R6).
  String _battery(DeviceTelemetry t) =>
      t.batteryLevelPct == null ? '—' : '${t.batteryLevelPct} %';

  String _rssi(DeviceTelemetry t) =>
      t.wifiSignalDbm == null ? '—' : '${t.wifiSignalDbm} dBm';

  String _wifi(DeviceTelemetry t) {
    if (t.wifiState != WifiState.connected) return 'Off';
    final ssid = t.wifiSsid;
    return (ssid == null || ssid.isEmpty) ? 'Connected' : ssid;
  }

  Widget _kv(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      WfNote(label),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(
          fontFamily: T.mono,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: T.ink,
        ),
      ),
    ],
  );
}

class _AppDiagnostics extends ConsumerWidget {
  const _AppDiagnostics();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).valueOrNull ?? '—';
    final devNav = ref.watch(devNavigationProvider);

    return WfCard(
      padding: EdgeInsets.zero,
      // ListTiles paint ink on the nearest Material; give them a transparent one
      // over the WfCard's coloured box.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            ListTile(
              title: const Text(
                'Version',
                style: TextStyle(color: T.ink, fontSize: 14),
              ),
              trailing: Text(
                version,
                style: const TextStyle(
                  color: T.ink2,
                  fontSize: 12,
                  fontFamily: T.mono,
                ),
              ),
            ),
            const Divider(height: 1, color: T.rule),
            ListTile(
              title: const Text(
                'App logs',
                style: TextStyle(color: T.ink, fontSize: 14),
              ),
              subtitle: const Text(
                'Live in-app capture — copy/share without adb.',
                style: TextStyle(color: T.ink2, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: T.ink3),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LogViewerPage(title: 'App logs'),
                ),
              ),
            ),
            const Divider(height: 1, color: T.rule),
            ListTile(
              title: const Text(
                'Camera link logs',
                style: TextStyle(color: T.ink, fontSize: 14),
              ),
              subtitle: const Text(
                'Live BLE/WiFi comms with the camera (interim — firmware-side '
                'logs land in a later phase).',
                style: TextStyle(color: T.ink2, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: T.ink3),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LogViewerPage(
                    title: 'Camera link',
                    filter: isCameraLinkLog,
                  ),
                ),
              ),
            ),
            // DB browser — dev builds only, injected via devNavigationProvider so
            // it stays out of prod (same gate as developer settings).
            if (devNav.debugPage != null) ...[
              const Divider(height: 1, color: T.rule),
              ListTile(
                title: const Text(
                  'Database browser',
                  style: TextStyle(color: T.ink, fontSize: 14),
                ),
                subtitle: const Text(
                  'Inspect users/teams/matches/clips; reset + reseed.',
                  style: TextStyle(color: T.ink2, fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: T.ink3),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => devNav.debugPage!())),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final unavailable = value == '—';
    return WfCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          WfNote(label),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: T.mono,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              // Muted when unavailable so a "—" never reads as a real reading.
              color: unavailable ? T.ink3 : T.ink,
            ),
          ),
        ],
      ),
    );
  }
}

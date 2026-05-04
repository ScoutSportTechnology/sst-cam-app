import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_data.dart';
import '../theme/tokens.dart';
import '../widgets/indicators.dart';
import '../widgets/wf_button.dart';
import '../widgets/wf_card.dart';
import 'diagnostics_page.dart';
import 'discovery_page.dart';
import 'sport_presets_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeCameraIdProvider);
    final connected = activeId != null;

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: const Text('Settings'),
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
          if (connected) const _CameraCard() else const _NoCameraCard(),
          const SizedBox(height: 14),
          _DiscoveryRow(
            connected: connected,
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const DiscoveryPage()));
            },
          ),
          const SizedBox(height: 14),
          const WfSection(
            'Recording defaults',
            padding: EdgeInsets.only(bottom: 6),
          ),
          const WfCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _ValueRow(label: 'Resolution', value: '1080p · 30 fps'),
                Divider(height: 1, color: T.rule),
                _ValueRow(label: 'Bitrate', value: '12 Mbps'),
                Divider(height: 1, color: T.rule),
                _ValueRow(label: 'Auto-start at kickoff', value: 'On'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const WfSection('Match setup', padding: EdgeInsets.only(bottom: 6)),
          WfCard(
            padding: EdgeInsets.zero,
            child: _NavRow(
              leading: const Icon(Icons.sports_soccer_outlined),
              label: 'Sport setups',
              sub: 'Saved time configs per sport',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SportPresetsPage()),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          const WfSection('Connectivity', padding: EdgeInsets.only(bottom: 6)),
          const WfCard(padding: EdgeInsets.zero, child: _ConnectivityToggles()),
          const SizedBox(height: 14),
          const WfSection('App', padding: EdgeInsets.only(bottom: 6)),
          const _RowItem(
            leading: Icon(Icons.palette_outlined),
            label: 'Theme',
            trailing: Text(
              'Dark',
              style: TextStyle(color: T.ink2, fontSize: 12),
            ),
          ),
          const Divider(height: 1, color: T.rule),
          const _RowItem(
            leading: Icon(Icons.lock_outline),
            label: 'Permissions',
            trailing: Text(
              '3 granted',
              style: TextStyle(color: T.ink2, fontSize: 12),
            ),
          ),
          const Divider(height: 1, color: T.rule),
          _NavRow(
            leading: const Icon(Icons.bug_report_outlined),
            label: 'Diagnostics',
            sub: 'BLE link · proto · logs',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DiagnosticsPage()),
              );
            },
          ),
          const Divider(height: 1, color: T.rule),
          const _RowItem(
            leading: Icon(Icons.info_outline),
            label: 'About',
            trailing: Text(
              '0.3.2',
              style: TextStyle(color: T.ink2, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraCard extends StatelessWidget {
  const _CameraCard();

  @override
  Widget build(BuildContext context) {
    return WfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    WfNote('Connected camera'),
                    SizedBox(height: 4),
                    Text(
                      'sst-cam-01',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: T.ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'fw 0.3.2 · proto v0.3',
                      style: TextStyle(
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
                decoration: BoxDecoration(
                  color: T.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(
                child: WfButton(label: 'Reboot', size: WfButtonSize.sm),
              ),
              SizedBox(width: 8),
              Expanded(
                child: WfButton(label: 'Update fw', size: WfButtonSize.sm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoCameraCard extends StatelessWidget {
  const _NoCameraCard();

  @override
  Widget build(BuildContext context) {
    return const WfCard(
      child: Row(
        children: [
          Icon(Icons.videocam_off_outlined, color: T.ink3),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No camera connected',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: T.ink,
                  ),
                ),
                SizedBox(height: 2),
                WfNote('Tap below to scan for nearby ScoutCams.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryRow extends StatelessWidget {
  const _DiscoveryRow({required this.connected, required this.onTap});
  final bool connected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: WfCard(
        padding: EdgeInsets.zero,
        child: _RowItem(
          leading: const Icon(Icons.bluetooth_searching),
          label: connected ? 'Connect a different camera' : 'Connect a camera',
          sub: 'Scan & pair · ${connected ? '1 paired' : '0 paired'}',
          trailing: const Icon(Icons.chevron_right, color: T.ink3, size: 18),
        ),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: T.ink,
              ),
            ),
          ),
          Text(value, style: const TextStyle(fontSize: 12, color: T.ink2)),
        ],
      ),
    );
  }
}

class _ConnectivityToggles extends StatefulWidget {
  const _ConnectivityToggles();

  @override
  State<_ConnectivityToggles> createState() => _ConnectivityTogglesState();
}

class _ConnectivityTogglesState extends State<_ConnectivityToggles> {
  bool _ap = true;
  bool _stayAwake = true;
  bool _bgBle = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _toggleRow('WiFi AP auto-enable', _ap, (v) => setState(() => _ap = v)),
        const Divider(height: 1, color: T.rule),
        _toggleRow(
          'Stay-awake on download',
          _stayAwake,
          (v) => setState(() => _stayAwake = v),
        ),
        const Divider(height: 1, color: T.rule),
        _toggleRow(
          'Keep BLE alive in background',
          _bgBle,
          (v) => setState(() => _bgBle = v),
        ),
      ],
    );
  }

  Widget _toggleRow(String label, bool v, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: T.ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          WfSwitch(value: v, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _RowItem extends StatelessWidget {
  const _RowItem({
    required this.leading,
    required this.label,
    this.sub,
    this.trailing,
  });
  final Widget leading;
  final String label;
  final String? sub;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 24, child: Center(child: leading)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: T.ink,
                  ),
                ),
                if (sub != null) ...[const SizedBox(height: 2), WfNote(sub!)],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.leading,
    required this.label,
    this.sub,
    required this.onTap,
  });
  final Widget leading;
  final String label;
  final String? sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: _RowItem(
        leading: leading,
        label: label,
        sub: sub,
        trailing: const Icon(Icons.chevron_right, color: T.ink3, size: 18),
      ),
    );
  }
}

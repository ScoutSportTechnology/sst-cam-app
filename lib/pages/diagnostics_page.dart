import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/wf_button.dart';
import '../widgets/wf_card.dart';
import '../widgets/wf_chip.dart';

/// BLE link + proto state. Targeted at firmware integrators.
class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Diagnostics'),
            Text(
              'sst-cam-01 · BLE link',
              style: TextStyle(fontSize: 11, color: T.ink2),
            ),
          ],
        ),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                _StatCard(label: 'MTU', value: '247'),
                _StatCard(label: 'RSSI', value: '−54 dBm'),
                _StatCard(label: 'Phy', value: '2M LE'),
                _StatCard(label: 'Conn int.', value: '15 ms'),
              ],
            ),
          ),
          const WfSection('Recent commands'),
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: _CommandLog(),
          ),
          const WfSection('Implementation'),
          const _ImplRow(
            title: 'BLE service',
            subtitle: 'BleServiceImpl · flutter_blue_plus',
            trailing: WfChip(label: 'Live', active: true),
          ),
          const Divider(height: 1, color: T.rule),
          const _ImplRow(
            title: 'Proto bindings',
            subtitle: 'lib/models/proto · gen-proto',
            trailing: Text(
              'v0.3',
              style: TextStyle(color: T.ink2, fontSize: 12),
            ),
          ),
          const WfSection('Actions'),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
            child: GridView(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 3,
              ),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                WfButton(label: 'Export logs'),
                WfButton(label: 'Run self-test'),
                WfButton(label: 'Reconnect BLE'),
                WfButton(label: 'Reset pairing'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return WfCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          WfNote(label),
          Text(
            value,
            style: const TextStyle(
              fontFamily: T.mono,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: T.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandLog extends StatelessWidget {
  const _CommandLog();

  @override
  Widget build(BuildContext context) {
    const rows = <(String, String, String, String)>[
      ('09:30:14', 'GetTelemetry', 'OK', '12 ms'),
      ('09:30:13', 'GetMatchState', 'OK', '18 ms'),
      ('09:30:13', 'GetTelemetry', 'OK', '11 ms'),
      ('09:30:12', 'StartRecording', 'OK', '34 ms'),
      ('09:30:11', 'GetTelemetry', 'TIMEOUT', '—'),
      ('09:30:10', 'GetTelemetry', 'OK', '14 ms'),
    ];
    return Column(
      children: rows.asMap().entries.map((e) {
        final r = e.value;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: e.key < rows.length - 1
                ? const Border(bottom: BorderSide(color: T.rule))
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: Text(
                  r.$1,
                  style: const TextStyle(
                    fontFamily: T.mono,
                    fontSize: 11,
                    color: T.ink3,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  r.$2,
                  style: const TextStyle(
                    fontFamily: T.mono,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: T.ink,
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  r.$3,
                  style: TextStyle(
                    fontFamily: T.mono,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: r.$3 == 'OK' ? T.accent : T.danger,
                  ),
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(
                  r.$4,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: T.mono,
                    fontSize: 11,
                    color: T.ink2,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ImplRow extends StatelessWidget {
  const _ImplRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: T.ink,
                  ),
                ),
                const SizedBox(height: 2),
                WfNote(subtitle),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

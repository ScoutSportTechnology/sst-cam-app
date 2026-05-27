import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/dev_config.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/wf_button.dart';
import '../../../core/widgets/wf_card.dart';
import '../../../core/widgets/wf_chip.dart';
import 'developer_settings_state.dart';

class DeveloperSettingsPage extends ConsumerStatefulWidget {
  const DeveloperSettingsPage({super.key});

  @override
  ConsumerState<DeveloperSettingsPage> createState() =>
      _DeveloperSettingsPageState();
}

class _DeveloperSettingsPageState extends ConsumerState<DeveloperSettingsPage> {
  late TextEditingController _serverController;
  bool _serverDirty = false;

  @override
  void initState() {
    super.initState();
    final staged = ref.read(developerSettingsProvider).stagedConfig;
    _serverController = TextEditingController(text: staged.serverAddress);
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  void _commitServerAddress() {
    if (!_serverDirty) return;
    _serverDirty = false;
    ref
        .read(developerSettingsProvider.notifier)
        .setServerAddress(_serverController.text);
  }

  Future<void> _confirmRestart(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: T.panel,
        title: const Text('Restart app?'),
        content: const Text(
          'Changes will take effect after the app restarts.',
          style: TextStyle(color: T.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Restart', style: TextStyle(color: T.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(developerSettingsProvider);
    final notifier = ref.read(developerSettingsProvider.notifier);
    final staged = state.stagedConfig;

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: const Text('Developer Settings'),
        backgroundColor: T.bg,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
        children: [
          if (state.hasPendingChanges) ...[
            WfChip(
              label: 'Restart to apply',
              active: true,
              leading: const Icon(Icons.restart_alt, size: 12),
            ),
            const SizedBox(height: 12),
          ],

          // Data mode
          const _SectionHeader('Data mode'),
          WfCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                for (final mode in DataMode.values) ...[
                  if (mode != DataMode.values.first)
                    const SizedBox(width: 8),
                  _ModeChip(
                    label: _dataModeLabel(mode),
                    selected: staged.dataMode == mode,
                    onTap: () => notifier.setDataMode(mode),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Camera emulation
          const _SectionHeader('Camera emulation'),
          WfCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Emulate BLE camera',
                          style: TextStyle(color: T.ink, fontSize: 14)),
                      SizedBox(height: 2),
                      Text(
                        'Mock BLE device advertises and responds to commands',
                        style: TextStyle(color: T.ink2, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: staged.cameraEmulation,
                  onChanged: notifier.setCameraEmulation,
                  activeThumbColor: T.accent,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // WiFi server address
          const _SectionHeader('WiFi server address'),
          WfCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: TextField(
              controller: _serverController,
              style: const TextStyle(color: T.ink, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'localhost',
                hintStyle: TextStyle(color: T.ink3),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (_) => _serverDirty = true,
              onSubmitted: (_) => _commitServerAddress(),
              onTapOutside: (_) => _commitServerAddress(),
              keyboardType: TextInputType.url,
            ),
          ),
          const SizedBox(height: 32),

          WfButton(
            label: 'Close & restart',
            variant: WfButtonVariant.danger,
            full: true,
            onPressed: state.hasPendingChanges
                ? () => _confirmRestart(context)
                : null,
          ),
        ],
      ),
    );
  }
}

String _dataModeLabel(DataMode mode) => switch (mode) {
  DataMode.full => 'Full',
  DataMode.seed => 'Seed only',
  DataMode.empty => 'Empty',
};

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: T.ink3,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: WfChip(label: label, active: selected),
  );
}

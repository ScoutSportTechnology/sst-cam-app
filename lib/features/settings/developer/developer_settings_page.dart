import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;

import 'log_viewer_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/dev_config.dart';
import '../../../core/config/env.dart';
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
  late TextEditingController _previewController;
  late TextEditingController _downloadController;
  bool _previewDirty = false;
  bool _downloadDirty = false;

  @override
  void initState() {
    super.initState();
    final staged = ref.read(developerSettingsProvider).stagedConfig;
    _previewController = TextEditingController(text: staged.previewBaseUrl);
    _downloadController = TextEditingController(text: staged.downloadBaseUrl);
  }

  @override
  void dispose() {
    _previewController.dispose();
    _downloadController.dispose();
    super.dispose();
  }

  void _commitPreviewBase() {
    if (!_previewDirty) return;
    _previewDirty = false;
    ref
        .read(developerSettingsProvider.notifier)
        .setPreviewBase(_previewController.text);
  }

  void _commitDownloadBase() {
    if (!_downloadDirty) return;
    _downloadDirty = false;
    ref
        .read(developerSettingsProvider.notifier)
        .setDownloadBase(_downloadController.text);
  }

  Widget _baseUrlField({
    required Key fieldKey,
    required String label,
    required TextEditingController controller,
    required String hint,
    required VoidCallback onChanged,
    required VoidCallback onCommit,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: T.ink3, fontSize: 12)),
      TextField(
        key: fieldKey,
        controller: controller,
        style: const TextStyle(color: T.ink, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: T.ink3),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (_) => onChanged(),
        onSubmitted: (_) => onCommit(),
        onTapOutside: (_) => onCommit(),
        keyboardType: TextInputType.url,
      ),
    ],
  );

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

          // Diagnostics
          const _SectionHeader('Diagnostics'),
          WfCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              title: const Text(
                'Logs',
                style: TextStyle(color: T.ink, fontSize: 14),
              ),
              subtitle: const Text(
                'In-app debugPrint capture — copy/share without adb.',
                style: TextStyle(color: T.ink2, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: T.ink3),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const LogViewerPage())),
            ),
          ),
          const SizedBox(height: 16),

          // Mock-backend-only controls: emulator advertising, the mock
          // preview/download endpoints, and dev seeding are read only by the
          // dev entry (main.dart). On a real-backend (stage) build they do
          // nothing, so hide them — leaving just Diagnostics/Logs.
          if (kAppEnv.isDevBackend) ...[
            const _SectionHeader('Seed app data'),
            WfCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Seed app data',
                          style: TextStyle(color: T.ink, fontSize: 14),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Fills the local database with sample teams, matches '
                          'and players, plus on-device past-match videos.',
                          style: TextStyle(color: T.ink2, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    key: const Key('seedDataSwitch'),
                    value: staged.seedData,
                    onChanged: notifier.setSeedData,
                    activeThumbColor: T.accent,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Camera (BLE + live WiFi)
            const _SectionHeader('Camera'),
            WfCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Emulate camera',
                              style: TextStyle(color: T.ink, fontSize: 14),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Mock BLE device advertises and the live WiFi '
                              'preview/download endpoints respond.',
                              style: TextStyle(color: T.ink2, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        key: const Key('cameraEmulationSwitch'),
                        value: staged.cameraEmulation,
                        onChanged: notifier.setCameraEmulation,
                        activeThumbColor: T.accent,
                      ),
                    ],
                  ),
                  const Divider(height: 20, color: T.hair),
                  _baseUrlField(
                    fieldKey: const Key('previewBaseField'),
                    label: 'Preview base URL',
                    controller: _previewController,
                    hint: DevConfig.defaults.previewBaseUrl,
                    onChanged: () => _previewDirty = true,
                    onCommit: _commitPreviewBase,
                  ),
                  const SizedBox(height: 10),
                  _baseUrlField(
                    fieldKey: const Key('downloadBaseField'),
                    label: 'Download base URL',
                    controller: _downloadController,
                    hint: DevConfig.defaults.downloadBaseUrl,
                    onChanged: () => _downloadDirty = true,
                    onCommit: _commitDownloadBase,
                  ),
                ],
              ),
            ),
          ],
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

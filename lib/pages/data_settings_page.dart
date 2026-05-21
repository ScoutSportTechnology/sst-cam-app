import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/services/backup_service.dart';
import '../state/app_data.dart';
import '../state/db_providers.dart' show backupServiceProvider;
import '../core/theme/tokens.dart';
import '../core/widgets/wf_card.dart';

class DataSettingsPage extends ConsumerWidget {
  const DataSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: const [
          _DataSection(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data section — moved from settings_page.dart
// ---------------------------------------------------------------------------

class _DataSection extends ConsumerWidget {
  const _DataSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WfCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _NavRow(
            leading: const Icon(Icons.upload_outlined),
            label: 'Export backup',
            onTap: () => _onExportTapped(context, ref),
          ),
          const Divider(height: 1, color: T.rule),
          _NavRow(
            leading: const Icon(Icons.download_outlined),
            label: 'Restore backup',
            onTap: () => _onRestoreTapped(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _onExportTapped(BuildContext context, WidgetRef ref) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.surface,
        title: const Text('Backup contains credentials'),
        content: const Text(
          'This backup includes your streaming keys and passwords. '
          'Store the file securely.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Export Anyway'),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    if (!context.mounted) return;

    final service = ref.read(backupServiceProvider);
    final activeCameraId = ref.read(activeCameraIdProvider);
    try {
      final path = await service.export(deviceId: activeCameraId);
      final filename = path.split('/').last;
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup saved: $filename')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Export failed: ${e is BackupImportException ? e.message : e.toString()}',
          ),
          backgroundColor: T.danger,
        ),
      );
    }
  }

  Future<void> _onRestoreTapped(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.surface,
        title: const Text('Restore backup?'),
        content: const Text('This will replace all your data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    var pathText = '';
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.surface,
        title: const Text('Enter backup file path'),
        content: TextField(
          autofocus: true,
          style: const TextStyle(color: T.ink, fontSize: 13),
          decoration: const InputDecoration(
            hintText: '/path/to/sst-backup-YYYY-MM-DD.json',
            hintStyle: TextStyle(color: T.ink3, fontSize: 12),
          ),
          onChanged: (v) => pathText = v,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(pathText.trim()),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (path == null || path.isEmpty) return;
    if (!context.mounted) return;

    final canonical = p.canonicalize(path);
    String docsDir;
    try {
      docsDir = (await getApplicationDocumentsDirectory()).path;
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not determine safe storage path. Restore cancelled.'),
          backgroundColor: T.danger,
        ),
      );
      return;
    }
    if (!canonical.startsWith('$docsDir/')) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Invalid path. Select a file from the Documents folder.',
          ),
          backgroundColor: T.danger,
        ),
      );
      return;
    }

    final activeCameraId = ref.read(activeCameraIdProvider);
    final service = ref.read(backupServiceProvider);
    try {
      final firstUserId = await service.import(
        File(canonical),
        currentCameraDeviceId: activeCameraId,
      );

      // Fix 13: restoreActive() reads SharedPreferences internally. Invalidating
      // providers before it runs can cause UsersController.build() to race against
      // the prefs write. Restore the active user first, then invalidate so the
      // rebuilt controllers see the correct active-user state.
      await ref
          .read(usersControllerProvider.notifier)
          .restoreActive(firstUserId);

      ref.invalidate(usersControllerProvider);
      ref.invalidate(teamsControllerProvider);
      ref.invalidate(sportPresetsControllerProvider);
      ref.invalidate(streamingDestinationsControllerProvider);
      ref.invalidate(upcomingMatchesProvider);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup restored successfully')),
      );
    } on BackupImportException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: T.danger),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Restore failed'),
          backgroundColor: T.danger,
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Local nav-row primitive (mirrors _NavRow from settings_page.dart)
// ---------------------------------------------------------------------------

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.leading,
    required this.label,
    required this.onTap,
  });
  final Widget leading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            SizedBox(width: 24, child: Center(child: leading)),
            const SizedBox(width: 12),
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
            const Icon(Icons.chevron_right, color: T.ink3, size: 18),
          ],
        ),
      ),
    );
  }
}

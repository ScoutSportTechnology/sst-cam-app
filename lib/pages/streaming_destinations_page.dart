import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_data.dart';
import '../core/theme/tokens.dart';
import '../core/widgets/wf_card.dart';
import '../core/widgets/wf_chip.dart';
import 'streaming_destination_form_sheet.dart';

/// Lists the active user's streaming destinations with add / edit / delete.
/// Extracted from the inline section on SettingsPage.
class StreamingDestinationsPage extends ConsumerWidget {
  const StreamingDestinationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(streamingDestinationsControllerProvider);
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: const Text('Streaming destinations')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load streaming destinations: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: T.ink2, fontSize: 12),
            ),
          ),
        ),
        data: (destinations) {
          if (destinations.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: WfNote(
                  'No streaming destinations yet. Tap + to add one.',
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 80),
            children: [
              WfCard(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < destinations.length; i++) ...[
                      _DestinationRow(
                        destination: destinations[i],
                        onTap: () => _onEdit(context, ref, destinations[i]),
                        onDelete: () =>
                            _onDelete(context, ref, destinations[i]),
                      ),
                      if (i < destinations.length - 1)
                        const Divider(height: 1, color: T.rule),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(heroTag: null,
        onPressed: () => _onAdd(context, ref),
        backgroundColor: T.accent,
        foregroundColor: T.accentInk,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  Future<void> _onAdd(BuildContext context, WidgetRef ref) async {
    final draft = await showStreamingDestinationFormSheet(context);
    if (draft == null) return;
    try {
      await ref
          .read(streamingDestinationsControllerProvider.notifier)
          .create(draft);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't add destination — try again.")),
      );
    }
  }

  Future<void> _onEdit(
    BuildContext context,
    WidgetRef ref,
    StreamingDestination existing,
  ) async {
    final draft = await showStreamingDestinationFormSheet(
      context,
      existing: existing,
    );
    if (draft == null) return;
    try {
      await ref
          .read(streamingDestinationsControllerProvider.notifier)
          .edit(draft);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save destination — try again.")),
      );
    }
  }

  Future<void> _onDelete(
    BuildContext context,
    WidgetRef ref,
    StreamingDestination dest,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.surface,
        title: const Text('Delete destination?'),
        content: Text(
          'Remove ${dest.name} from ${dest.provider.displayLabel} '
          '${dest.protocol.displayLabel}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: T.danger, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(streamingDestinationsControllerProvider.notifier)
          .delete(dest.id);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't delete destination — try again."),
        ),
      );
    }
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.destination,
    required this.onTap,
    required this.onDelete,
  });

  final StreamingDestination destination;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            WfChip(label: destination.provider.displayLabel),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: T.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    destination.protocol.displayLabel,
                    style: const TextStyle(
                      fontFamily: T.mono,
                      fontSize: 11,
                      color: T.ink2,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: T.ink2,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

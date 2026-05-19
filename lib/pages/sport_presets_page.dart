import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_data.dart';
import '../theme/tokens.dart';
import '../widgets/wf_card.dart';
import '../widgets/wf_chip.dart';
import 'sport_preset_form_sheet.dart';

/// Lists sport setups grouped by base sport. Built-in presets are read-only;
/// custom presets can be edited or deleted.
class SportPresetsPage extends ConsumerWidget {
  const SportPresetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sportPresetsControllerProvider);
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: const Text('Sport setups')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load sport setups: $e',
              textAlign: TextAlign.center,
              style: const TextStyle(color: T.ink2, fontSize: 12),
            ),
          ),
        ),
        data: (presets) {
          if (presets.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: WfNote(
                  'No sport setups yet. Tap + to add one — saved setups can '
                  'be picked when scheduling a match.',
                ),
              ),
            );
          }
          return Column(
            children: [
              const SizedBox(height: 44, child: _SportFilterChips()),
              Expanded(child: _PresetList(presets: presets)),
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
    final draft = await showSportPresetFormSheet(context);
    if (draft == null) return;
    try {
      await ref.read(sportPresetsControllerProvider.notifier).create(draft);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add setup: $e')));
    }
  }
}

class _PresetList extends ConsumerWidget {
  const _PresetList({required this.presets});
  final List<SportPreset> presets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedSport = ref.watch(sportPresetsFilterProvider);
    final filtered = selectedSport == null
        ? presets
        : presets.where((p) => p.sport == selectedSport).toList();
    final grouped = _groupBySport(filtered);

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        for (final sport in grouped.keys) ...[
          WfSection(sport),
          ...grouped[sport]!.map(
            (p) => _PresetRow(
              preset: p,
              onEdit: () => _onEdit(context, ref, p),
              onDelete: () => _onDelete(context, ref, p),
            ),
          ),
        ],
      ],
    );
  }

  static Map<String, List<SportPreset>> _groupBySport(
    List<SportPreset> presets,
  ) {
    final out = <String, List<SportPreset>>{};
    for (final p in presets) {
      out.putIfAbsent(p.sport, () => []).add(p);
    }
    // Sort within each group: built-ins first, then alphabetically by name.
    for (final list in out.values) {
      list.sort((a, b) {
        if (a.builtIn != b.builtIn) return a.builtIn ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    }
    return out;
  }

  Future<void> _onEdit(
    BuildContext context,
    WidgetRef ref,
    SportPreset preset,
  ) async {
    if (preset.builtIn) return;
    final draft = await showSportPresetFormSheet(context, existing: preset);
    if (draft == null) return;
    try {
      await ref.read(sportPresetsControllerProvider.notifier).edit(draft);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<void> _onDelete(
    BuildContext context,
    WidgetRef ref,
    SportPreset preset,
  ) async {
    if (preset.builtIn) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: T.surface,
        title: const Text('Delete setup?'),
        content: Text('${preset.name} will be removed from the camera.'),
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
      await ref.read(sportPresetsControllerProvider.notifier).delete(preset.id);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }
}

class _SportFilterChips extends ConsumerWidget {
  const _SportFilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(sportPresetsFilterProvider);
    final entries = <String?>[null, ...kSports];

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (_, i) {
        final s = entries[i];
        final active = s == selected;
        return GestureDetector(
          onTap: () => ref.read(sportPresetsFilterProvider.notifier).state = s,
          child: WfChip(label: s ?? 'All', active: active),
        );
      },
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.preset,
    required this.onEdit,
    required this.onDelete,
  });
  final SportPreset preset;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: preset.builtIn ? null : onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            if (preset.builtIn) ...[
              const WfChip(label: 'Default'),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                preset.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  color: T.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              preset.summary,
              style: const TextStyle(
                fontFamily: T.mono,
                fontSize: 11,
                color: T.ink2,
              ),
            ),
            if (!preset.builtIn)
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

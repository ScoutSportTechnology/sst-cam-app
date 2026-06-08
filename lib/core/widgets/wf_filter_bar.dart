import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Describes one filter slot in a [WfFilterBar].
///
/// [label]    — button text when nothing is selected (e.g. "All sports").
/// [options]  — available options to show in the picker sheet.
/// [selected] — currently active option; null means no filter is applied.
/// [onSelect] — called with the chosen value, or null when the user picks "All".
class FilterSpec {
  const FilterSpec({
    required this.label,
    required this.options,
    this.selected,
    required this.onSelect,
  });

  final String label;
  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelect;
}

/// A horizontally scrollable row of picker buttons, one per [FilterSpec].
///
/// Pass one [FilterSpec] per filter type; the widget builds the buttons and
/// manages the bottom-sheet picker automatically.
class WfFilterBar extends StatelessWidget {
  const WfFilterBar({super.key, required this.filters});

  final List<FilterSpec> filters;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          for (int i = 0; i < filters.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            _PickerButton(spec: filters[i]),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private — picker button (label + chevron)
// ---------------------------------------------------------------------------

class _PickerButton extends StatelessWidget {
  const _PickerButton({required this.spec});
  final FilterSpec spec;

  @override
  Widget build(BuildContext context) {
    final active = spec.selected != null;
    final label = spec.selected ?? spec.label;
    final fg = active ? T.accentInk : T.ink2;

    return GestureDetector(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: T.panel,
        builder: (_) => _PickerSheet(spec: spec),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? T.accent : T.fillSoft,
          border: Border.all(color: active ? T.accent : T.hair, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fg,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.keyboard_arrow_down_rounded, size: 13, color: fg),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private — bottom sheet with option list
// ---------------------------------------------------------------------------

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({required this.spec});
  final FilterSpec spec;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: T.fillDark,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _Tile(
            label: 'All',
            checked: spec.selected == null,
            onTap: () {
              spec.onSelect(null);
              Navigator.of(context).pop();
            },
          ),
          ...spec.options.map(
            (opt) => _Tile(
              label: opt,
              checked: opt == spec.selected,
              onTap: () {
                spec.onSelect(opt);
                Navigator.of(context).pop();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.checked,
    required this.onTap,
  });

  final String label;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: checked ? T.accent : T.ink,
                  fontWeight: checked ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (checked) const Icon(Icons.check, color: T.accent, size: 18),
          ],
        ),
      ),
    );
  }
}

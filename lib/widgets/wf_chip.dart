import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Small label pill — the wireframe `WfChip`. Use `active: true` for the
/// accent-filled variant.
class WfChip extends StatelessWidget {
  const WfChip({
    super.key,
    required this.label,
    this.active = false,
    this.leading,
  });

  final String label;
  final bool active;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final fg = active ? T.accentInk : T.ink2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? T.accent : T.fillSoft,
        border: Border.all(color: active ? T.accent : T.hair, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

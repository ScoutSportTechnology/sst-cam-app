import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum WfButtonVariant { primary, outline, danger, text, filled }

enum WfButtonSize { sm, md, lg }

/// Sharp-cornered button matching the wireframe vocabulary.
class WfButton extends StatelessWidget {
  const WfButton({
    super.key,
    required this.label,
    this.variant = WfButtonVariant.outline,
    this.size = WfButtonSize.md,
    this.onPressed,
    this.leading,
    this.full = false,
  });

  final String label;
  final WfButtonVariant variant;
  final WfButtonSize size;
  final VoidCallback? onPressed;
  final Widget? leading;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final hPad = switch (size) {
      WfButtonSize.sm => 10.0,
      WfButtonSize.md => 14.0,
      WfButtonSize.lg => 18.0,
    };
    final h = switch (size) {
      WfButtonSize.sm => 30.0,
      WfButtonSize.md => 40.0,
      WfButtonSize.lg => 48.0,
    };
    final fontSize = switch (size) {
      WfButtonSize.sm => 12.0,
      WfButtonSize.md => 13.0,
      WfButtonSize.lg => 14.0,
    };

    final (bg, fg, border) = switch (variant) {
      WfButtonVariant.primary => (T.accent, T.accentInk, T.accent),
      WfButtonVariant.danger => (T.danger, T.dangerInk, T.danger),
      WfButtonVariant.filled => (T.fillMid, T.ink, T.hair),
      WfButtonVariant.outline => (Colors.transparent, T.ink, T.ring),
      WfButtonVariant.text => (Colors.transparent, T.ink2, Colors.transparent),
    };

    final child = Row(
      mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 6)],
        Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: bg,
        type: MaterialType.button,
        borderRadius: BorderRadius.zero,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            height: h,
            width: full ? double.infinity : null,
            padding: EdgeInsets.symmetric(horizontal: hPad),
            decoration: BoxDecoration(
              border: Border.all(color: border, width: 1),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

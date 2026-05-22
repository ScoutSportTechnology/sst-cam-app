import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Battery glyph — outlined cell with a fill bar inside.
class BatteryIndicator extends StatelessWidget {
  const BatteryIndicator({super.key, required this.level, this.size = 12});

  /// 0..1
  final double level;
  final double size;

  @override
  Widget build(BuildContext context) {
    final w = size * 1.8;
    final h = size;
    final color = level < 0.2 ? T.danger : T.ink2;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: w,
          height: h,
          decoration: BoxDecoration(border: Border.all(color: color, width: 1)),
          padding: const EdgeInsets.all(1),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: level.clamp(0.05, 1.0),
            child: Container(color: color),
          ),
        ),
        Container(width: 1.5, height: h * 0.5, color: color),
      ],
    );
  }
}

/// Wifi-style signal bars (1..4).
class SignalIndicator extends StatelessWidget {
  const SignalIndicator({super.key, required this.bars, this.size = 12});
  final int bars;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.8,
      height: size,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (i) {
          final on = i < bars;
          final h = (i + 1) / 4 * size;
          return Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Container(
              width: (size - 2) / 4,
              height: h,
              color: on ? T.ink2 : T.ink4,
            ),
          );
        }),
      ),
    );
  }
}

/// Material-style switch in the wireframe palette.
class WfSwitch extends StatelessWidget {
  const WfSwitch({super.key, required this.value, this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: T.fast,
        curve: T.ease,
        width: 38,
        height: 22,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? T.accent : T.fillMid,
          border: Border.all(color: value ? T.accent : T.hair, width: 1),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: value ? T.accentInk : T.ink,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

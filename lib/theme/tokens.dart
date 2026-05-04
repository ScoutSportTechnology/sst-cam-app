import 'package:flutter/material.dart';

/// Design tokens — derived from the wireframe DNA.
/// Dark surface stack, hi-vis yellow accent, danger red.
class T {
  T._();

  // Surface stack
  static const bg = Color(0xFF0A0A0A);
  static const panel = Color(0xFF111113);
  static const surface = Color(0xFF17171A);
  static const surfaceHi = Color(0xFF1F1F23);
  static const fillSoft = Color(0xFF1E1E22);
  static const fillMid = Color(0xFF26262B);
  static const fillDark = Color(0xFF36363C);

  // Strokes (alpha over bg)
  static const hair = Color(0x14FFFFFF); // 0.08
  static const rule = Color(0x0DFFFFFF); // 0.05
  static const ring = Color(0x24FFFFFF); // 0.14

  // Ink
  static const ink = Color(0xF5FFFFFF); // 0.96
  static const ink2 = Color(0x9EFFFFFF); // 0.62
  static const ink3 = Color(0x61FFFFFF); // 0.38
  static const ink4 = Color(0x38FFFFFF); // 0.22

  // Brand
  static const accent = Color(0xFFE8FF3C);
  static const accentDim = Color(0xFFC9DD2A);
  static const accentSoft = Color(0x24E8FF3C); // 0.14
  static const accentInk = Color(0xFF0A0A0A);

  // Status
  static const danger = Color(0xFFFF3B3B);
  static const dangerSoft = Color(0x24FF3B3B); // 0.14
  static const dangerInk = Color(0xFFFFFFFF);
  static const ok = Color(0xFF4ADE80);
  static const warn = Color(0xFFFFB020);

  // Type families. Inter ships system-side on most platforms; falls back to
  // platform default. JetBrains Mono is the data face — used for clocks,
  // scores, IDs, sizes.
  static const font =
      'Inter, -apple-system, BlinkMacSystemFont, Roboto, sans-serif';
  static const mono = 'JetBrains Mono, SF Mono, ui-monospace, Menlo, monospace';

  // Motion
  static const ease = Cubic(0.32, 0.72, 0, 1);
  static const fast = Duration(milliseconds: 160);
  static const med = Duration(milliseconds: 240);
}

/// Convenience getter so `context.t` reads tokens via the theme extension.
extension TokensX on BuildContext {
  // currently unused but available for future per-theme overrides
  // ignore: unused_element
  Type get _self => runtimeType;
}

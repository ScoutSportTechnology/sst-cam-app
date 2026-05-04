import 'package:flutter/material.dart';

final class AppTypography {
  AppTypography._();

  static const String? primary = null;
  static const String? mono = null;

  static const double _xs = 11,
      _sm = 12,
      _md = 14,
      _lg = 16,
      _h3 = 18,
      _h2 = 20,
      _h1 = 22,
      _d1 = 24,
      _d2 = 26,
      _d3 = 28;

  static TextTheme build(ColorScheme scheme) {
    final base = Typography.material2021().black.apply(
      displayColor: scheme.onSurface,
      bodyColor: scheme.onSurface,
    );

    TextStyle s(
      TextStyle? t,
      double sz,
      FontWeight w, {
      bool isMono = false,
    }) => (t ?? const TextStyle()).copyWith(
      fontFamily: isMono ? mono : primary,
      fontSize: sz,
      fontWeight: w,
    );

    return base.copyWith(
      displayLarge: s(base.displayLarge, _d3, FontWeight.w700),
      displayMedium: s(base.displayMedium, _d2, FontWeight.w700),
      displaySmall: s(base.displaySmall, _d1, FontWeight.w700),
      
      headlineLarge: s(base.headlineLarge, _h1, FontWeight.w700),
      headlineMedium: s(base.headlineMedium, _h2, FontWeight.w600),
      headlineSmall: s(base.headlineSmall, _h3, FontWeight.w600),

      titleLarge: s(base.titleLarge, _lg, FontWeight.w600),
      titleMedium: s(base.titleMedium, _md, FontWeight.w600),
      titleSmall: s(base.titleSmall, _sm, FontWeight.w600),

      bodyLarge: s(base.bodyLarge, _lg, FontWeight.w400),
      bodyMedium: s(base.bodyMedium, _md, FontWeight.w400),
      bodySmall: s(base.bodySmall, _sm, FontWeight.w400),

      labelLarge: s(base.labelLarge, _md, FontWeight.w600),
      labelMedium: s(base.labelMedium, _sm, FontWeight.w600),
      labelSmall: s(base.labelSmall, _xs, FontWeight.w600),
    );
  }
}

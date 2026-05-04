import 'package:flutter/material.dart';

final class AppColors {
  AppColors._();

  static const Color brand = Color(0xFFDBB42C);

  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFF9A825);
  static const Color error = Color(0xFFD32F2F);
  static const Color info = Color(0xFF0288D1);

  static final ColorScheme lightScheme = ColorScheme.fromSeed(
    seedColor: brand,
    brightness: Brightness.light,
  );

  static final ColorScheme darkScheme = ColorScheme.fromSeed(
    seedColor: brand,
    brightness: Brightness.dark,
    surface: Color.fromARGB(255, 0, 0, 0),
  );
}

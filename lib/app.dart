import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/config/app_config.dart';
import 'core/shell/app_shell.dart';
import 'core/theme/tokens.dart';

class SstCamApp extends StatelessWidget {
  const SstCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: _buildTheme(),
      home: const AppShell(),
    );
  }

  ThemeData _buildTheme() {
    final scheme = ColorScheme.dark(
      primary: T.accent,
      onPrimary: T.accentInk,
      secondary: T.accent,
      onSecondary: T.accentInk,
      surface: T.bg,
      onSurface: T.ink,
      surfaceContainerLow: T.panel,
      surfaceContainer: T.surface,
      surfaceContainerHigh: T.surfaceHi,
      outline: T.hair,
      error: T.danger,
      onError: T.dangerInk,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: T.bg,
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: T.ink, fontSize: 14, height: 1.4),
        bodyMedium: TextStyle(color: T.ink, fontSize: 13, height: 1.4),
        bodySmall: TextStyle(color: T.ink2, fontSize: 11, height: 1.4),
        titleLarge: TextStyle(
          color: T.ink,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: TextStyle(
          color: T.ink,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        labelLarge: TextStyle(
          color: T.ink,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: T.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: T.ink,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: T.ink),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: T.panel,
        indicatorColor: T.accentSoft,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? T.accent : T.ink2,
            letterSpacing: 0.2,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? T.accent : T.ink2, size: 22);
        }),
      ),
      cardTheme: const CardThemeData(
        color: T.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: T.rule,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: T.ink2, size: 18),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: T.accent,
          foregroundColor: T.accentInk,
          minimumSize: const Size(80, 40),
          shape: const RoundedRectangleBorder(),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: T.ink,
          side: const BorderSide(color: T.ring),
          minimumSize: const Size(80, 40),
          shape: const RoundedRectangleBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: T.accent,
          shape: const RoundedRectangleBorder(),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(T.ink),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? T.accent : T.fillMid,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(T.hair),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: T.bg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        modalBackgroundColor: T.bg,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: T.accent,
        unselectedLabelColor: T.ink2,
        indicatorColor: T.accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: T.rule,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: T.ink2,
        textColor: T.ink,
      ),
    );
  }
}


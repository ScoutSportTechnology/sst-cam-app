import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Navigation callbacks injected by the dev entry-point (main.dart).
/// Defaults to null so prod builds have no debug surfaces at all.
class DevNavigation {
  const DevNavigation({this.debugPage, this.developerSettings});

  /// Builds the hidden debug page, accessible via long-press on About.
  final Widget Function()? debugPage;

  /// Builds the Developer Settings page, shown as a nav row in Settings.
  final Widget Function()? developerSettings;
}

final devNavigationProvider = Provider<DevNavigation>(
  (ref) => const DevNavigation(),
);

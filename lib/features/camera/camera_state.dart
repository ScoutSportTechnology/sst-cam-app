// Camera connection state — active camera ID is set by the discovery flow on a
// successful connect and cleared on disconnect.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The BLE device ID of the currently connected SST Cam, or null when no
/// camera is connected. Written by the discovery / settings connection flows;
/// read by camera-gated UI sections.
final activeCameraIdProvider = StateProvider<String?>((ref) => null);

/// App-level selected tab index. Write to this to switch tabs from anywhere.
/// Tab indices: 0=Main, 1=Teams, 2=Match, 3=Video, 4=Settings.
final activeTabProvider = StateProvider<int>((_) => 0);

/// Named tab indices — use these instead of bare integers when writing to
/// [activeTabProvider].
abstract final class AppTab {
  static const int main = 0;
  static const int teams = 1;
  static const int match = 2;
  static const int video = 3;
  static const int settings = 4;
}

import 'package:flutter/services.dart';

/// Thin Dart-side wrapper for the Android `com.sst.sstcam/wifi` platform
/// channels.
///
/// Keeps all channel name strings and method name strings in one place so
/// renaming them is a single-file change. The Kotlin counterpart
/// (`WifiDirectChannel.kt`) must stay in sync with these constants.
///
/// All methods throw [PlatformException] on native-side failures; callers
/// should catch and translate to [WifiDirectException] as appropriate.
class WifiP2pChannel {
  static const _method = MethodChannel('com.sst.sstcam/wifi');
  static const _event = EventChannel('com.sst.sstcam/wifi/state');

  /// Instruct the native layer to join the P2P group identified by [ssid]
  /// and [psk]. Resolves when the native `connect` call has been dispatched
  /// (not when the group is fully established — group state arrives via
  /// [stateStream]).
  Future<void> connect({required String ssid, required String psk}) async {
    await _method
        .invokeMethod<void>('connect', {'ssid': ssid, 'psk': psk})
        .timeout(const Duration(seconds: 15));
  }

  /// Tear down the active P2P group. Safe to call when no group is active.
  Future<void> disconnect() async {
    await _method
        .invokeMethod<void>('disconnect')
        .timeout(const Duration(seconds: 15));
  }

  /// Integer state codes pushed by the native `BroadcastReceiver`:
  ///   0 = idle
  ///   1 = starting
  ///   2 = connected
  ///   3 = failed
  ///   4 = stopping
  ///
  /// Hot-broadcast — new listeners get the next event, not historical ones.
  // Must be a final field, not a getter — EventChannel.receiveBroadcastStream()
  // registers a new native handler on every call, evicting the previous sink.
  final Stream<int> stateStream = _event.receiveBroadcastStream().cast<int>();
}

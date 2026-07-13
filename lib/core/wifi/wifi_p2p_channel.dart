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

  /// The SSID of the WiFi network the phone is currently joined to, or null when
  /// the phone is not on WiFi (or the SSID is unavailable — e.g. location
  /// permission not granted, or the OS returns `<unknown ssid>`). Never throws:
  /// a [MissingPluginException]/[PlatformException] resolves to null so callers
  /// treat "SSID unknown" the same as "phone offline".
  Future<String?> currentSsid() async {
    try {
      final ssid = await _method
          .invokeMethod<String>('currentSsid')
          .timeout(const Duration(seconds: 5));
      if (ssid == null || ssid.isEmpty) return null;
      return ssid;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on Exception {
      return null;
    }
  }

  /// The phone's current WiFi frequency in MHz (0 = unknown / not on WiFi).
  /// ~2400-2500 = 2.4 GHz, ~4900-5900 = 5 GHz. Any failure resolves to 0.
  Future<int> currentWifiFrequencyMhz() async {
    try {
      final mhz = await _method
          .invokeMethod<int>('currentWifiFrequencyMhz')
          .timeout(const Duration(seconds: 5));
      return mhz ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    } on Exception {
      return 0;
    }
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

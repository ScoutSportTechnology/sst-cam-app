import 'package:flutter/services.dart';

import 'wifi_connectivity_service.dart';

/// Real [WifiConnectivityService] over the native `WifiConnectivityChannel`
/// EventChannel (a `ConnectivityManager.NetworkCallback` for `TRANSPORT_WIFI`).
class WifiConnectivityServiceImpl implements WifiConnectivityService {
  static const EventChannel _events = EventChannel(
    'com.sst.sstcam/wifi_connectivity',
  );

  @override
  Stream<bool> wifiAvailable() => _events
      .receiveBroadcastStream()
      .map((event) => event == true)
      // Fail SAFE: if the platform channel is absent (a unit/widget test, or a
      // platform without the native side) swallow the error so the observer
      // simply never fires — the firmware S2 carrier watchdog (D2a) is the
      // backstop. Never let a missing channel crash a widget that mounts the
      // auto-revert controller.
      .handleError((Object _) {});
}

/// Observes the PHONE's own Wi-Fi (STA) transport (D1a / U5): emits `true` while
/// the phone has a Wi-Fi network and `false` once the last one is lost.
///
/// The app uses this to auto-revert the camera from shared-WiFi (S2) back to the
/// direct WiFi-Direct (P2P) link when the phone drops the shared network, so live
/// preview keeps working. It is an OBSERVER only — it never drives reconnection
/// (that reactive loop was the SSID-flap storm; see [WifiHandoffController]).
abstract class WifiConnectivityService {
  /// Broadcast stream of phone-Wi-Fi availability. The native side seeds the
  /// current state on listen, then emits on each transition. Never throws to the
  /// listener; a missing platform channel simply yields no events.
  Stream<bool> wifiAvailable();
}

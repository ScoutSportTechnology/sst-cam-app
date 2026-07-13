/// The camera's internet uplink configuration — its path to the cloud (RTMP),
/// SEPARATE from the WiFi-Direct link that carries control + live preview.
///
/// Two interfaces, each enable/disable with DHCP-or-static IP:
///  - [ethernet]: the guaranteed uplink when a cable is present.
///  - [wifi]: the camera joins a network (venue wifi / a phone hotspot) as a
///    normal client. GATED on the camera's single-radio GO+STA concurrency.
///
/// Mirrors the firmware `NetworkConfig` proto (bluetooth.proto §10b) and the
/// domain `UplinkData`. Configured in Settings → Network and pushed over BLE.
library;

/// IPv4 addressing for one uplink interface. When [dhcp] is true the static
/// fields are ignored; when false, [address] is CIDR ("10.0.0.5/24").
class UplinkIp {
  const UplinkIp({
    this.dhcp = true,
    this.address = '',
    this.gateway = '',
    this.dns = '',
  });

  final bool dhcp;
  final String address;
  final String gateway;
  final String dns;

  UplinkIp copyWith({
    bool? dhcp,
    String? address,
    String? gateway,
    String? dns,
  }) => UplinkIp(
    dhcp: dhcp ?? this.dhcp,
    address: address ?? this.address,
    gateway: gateway ?? this.gateway,
    dns: dns ?? this.dns,
  );
}

class EthernetUplink {
  const EthernetUplink({this.enabled = false, this.ip = const UplinkIp()});

  final bool enabled;
  final UplinkIp ip;

  EthernetUplink copyWith({bool? enabled, UplinkIp? ip}) =>
      EthernetUplink(enabled: enabled ?? this.enabled, ip: ip ?? this.ip);
}

class WifiUplink {
  const WifiUplink({
    this.enabled = false,
    this.ssid = '',
    this.password = '',
    this.ip = const UplinkIp(),
  });

  final bool enabled;
  final String ssid;
  final String password;
  final UplinkIp ip;

  WifiUplink copyWith({
    bool? enabled,
    String? ssid,
    String? password,
    UplinkIp? ip,
  }) => WifiUplink(
    enabled: enabled ?? this.enabled,
    ssid: ssid ?? this.ssid,
    password: password ?? this.password,
    ip: ip ?? this.ip,
  );
}

class NetworkConfig {
  const NetworkConfig({
    this.ethernet = const EthernetUplink(),
    this.wifi = const WifiUplink(),
  });

  final EthernetUplink ethernet;
  final WifiUplink wifi;

  NetworkConfig copyWith({EthernetUplink? ethernet, WifiUplink? wifi}) =>
      NetworkConfig(
        ethernet: ethernet ?? this.ethernet,
        wifi: wifi ?? this.wifi,
      );
}

/// The camera's reply to Set/GetNetworkConfig: the current config echoed back
/// plus live per-interface status (what Settings → Network displays).
///
/// When a [SetNetworkConfigCommand] with `wifi.enabled = true` begins a
/// shared-WiFi (STA) migration (firmware protocol_version >= 4), the reply also
/// carries [migrationId], [previewEndpoint] and [previewCredential]: the camera
/// has torn down the WiFi-Direct GO, joined the phone's network as STA, and is
/// serving an AUTHENTICATED RTSP preview at `rtsp://previewEndpoint:8554/preview`
/// (HTTP Basic auth = `previewCredential`, "user:pass"). The app probes that
/// endpoint over the LAN, then replies with a [ConfirmPreviewReachableCommand]
/// carrying [migrationId]. These fields are zero/empty on a plain Get or when no
/// migration is in progress.
class NetworkConfigResult {
  const NetworkConfigResult({
    required this.config,
    required this.ethernetUp,
    required this.ethernetAddress,
    required this.wifiUp,
    required this.wifiStatus,
    this.migrationId = 0,
    this.previewEndpoint = '',
    this.previewCredential = '',
  });

  final NetworkConfig config;
  final bool ethernetUp;
  final String ethernetAddress;
  final bool wifiUp;
  final String wifiStatus;

  /// Monotonic migration id for a shared-WiFi (STA) migration in progress; 0
  /// when the reply does not begin a migration. Echoed back in
  /// [ConfirmPreviewReachableCommand].
  final int migrationId;

  /// STA/LAN IP (host only) the camera is serving the authenticated RTSP preview
  /// on during a migration; empty outside a migration.
  final String previewEndpoint;

  /// HTTP Basic-auth credential ("user:pass") for the migration preview; empty
  /// outside a migration. A secret — never render it in UI or diagnostics.
  final String previewCredential;

  /// Whether this reply began a shared-WiFi (STA) migration the app must probe +
  /// confirm (a non-zero migration id with a preview endpoint to reach).
  bool get isMigrating => migrationId != 0 && previewEndpoint.isNotEmpty;
}

/// The camera's reply to [ConfirmPreviewReachableCommand]: the connectivity mode
/// the arbiter settled into after the app's reachability verdict.
class ConfirmPreviewReachableResult {
  const ConfirmPreviewReachableResult({
    required this.migrationId,
    required this.inSharedWifi,
  });

  /// Echo of the confirmed migration id.
  final int migrationId;

  /// True when the camera finalized S2 (STA-only, streaming allowed); false when
  /// it reverted to S1 (WiFi-Direct GO restored, streaming disabled).
  final bool inSharedWifi;
}

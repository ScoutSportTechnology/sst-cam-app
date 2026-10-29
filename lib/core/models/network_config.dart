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
class NetworkConfigResult {
  const NetworkConfigResult({
    required this.config,
    required this.ethernetUp,
    required this.ethernetAddress,
    required this.wifiUp,
    required this.wifiStatus,
  });

  final NetworkConfig config;
  final bool ethernetUp;
  final String ethernetAddress;
  final bool wifiUp;
  final String wifiStatus;
}

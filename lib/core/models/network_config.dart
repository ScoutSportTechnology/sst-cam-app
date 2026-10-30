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

/// Which interface carries the LAN path to the phone (proto v5 `LanPath`). The
/// firmware's `ConnectivityArbiter` selects EXACTLY one — Ethernet-on-phone-subnet
/// → WiFi-STA → WiFi-Direct P2P (single-LAN-path invariant, R2/R3). Orthogonal to
/// [NetworkConfigResult.inSharedWifi] (a radio-mode indicator): [lanPath] names
/// WHICH interface (including Ethernet) carries the LAN, which `inSharedWifi`
/// cannot express.
enum LanPath {
  /// No LAN path committed (or unknown — old firmware leaves the proto enum at 0).
  none,

  /// Ethernet is the committed LAN path (on the phone's subnet).
  ethernet,

  /// WiFi-STA (the phone's shared Wi-Fi) is the committed LAN path.
  wifiSta,

  /// WiFi-Direct P2P direct link — no shared LAN.
  p2p,
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
    this.inSharedWifi = false,
    this.currentSsid = '',
    this.lanPath = LanPath.none,
    this.ethernetEndpoint = '',
    this.ethernetCredential = '',
    this.ethernetConfirmId = 0,
    this.ethernetDhcp,
  });

  final NetworkConfig config;
  final bool ethernetUp;
  final String ethernetAddress;
  final bool wifiUp;
  final String wifiStatus;

  /// Ambient connected-state (R3): true iff the camera's arbiter is SETTLED in
  /// shared-WiFi (S2/kStaOnly) — sourced from the firmware's arbiter, NOT
  /// inferred from [wifiUp] (which reflects raw STA association, not the settled
  /// mode). Populated on BOTH a Set reply and a plain Get, so the app can render
  /// "connected to `<ssid>`" on reconnect without replaying the migration
  /// handshake. False against firmware that predates the field.
  final bool inSharedWifi;

  /// The SSID the camera is connected to while [inSharedWifi]; empty otherwise.
  /// Sourced from the arbiter's settled state, never a failed in-flight config.
  final String currentSsid;

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

  /// The single LAN path the firmware arbiter committed (proto v5, R3/R13).
  /// [LanPath.none] against firmware that predates the field.
  final LanPath lanPath;

  /// LAN IP (host only) the camera serves the authenticated RTSP preview on when
  /// Ethernet is the committed LAN path; empty otherwise. Endpoint always rides;
  /// the secret [ethernetCredential] is gated on the encrypted/bonded link.
  final String ethernetEndpoint;

  /// HTTP Basic-auth credential ("user:pass") for the Ethernet-LAN preview;
  /// empty over an unencrypted link (endpoint rides, secret does not) or when
  /// Ethernet is not the LAN path. A secret — never render it in UI/diagnostics.
  final String ethernetCredential;

  /// The Ethernet-LAN confirmation-handshake id (parallel to [migrationId], but
  /// sharing the firmware's single global epoch counter). 0 outside an Ethernet
  /// selection.
  final int ethernetConfirmId;

  /// The REAL Ethernet addressing mode read back from the firmware-owned
  /// interface: true = DHCP, false = static, null = unknown/down (the proto
  /// `has_ethernet_dhcp()` was false). Replaces the old default-DHCP placeholder
  /// (the DHCP-when-static reporting bug).
  final bool? ethernetDhcp;

  /// The endpoint (host only) of the currently-committed LAN path to identity-
  /// probe (R8): the Ethernet IP when [lanPath] is Ethernet, else the STA preview
  /// endpoint when WiFi-STA. Empty for P2P/none or when the firmware surfaced no
  /// endpoint.
  String get lanEndpoint => switch (lanPath) {
    LanPath.ethernet => ethernetEndpoint,
    LanPath.wifiSta => previewEndpoint,
    LanPath.none || LanPath.p2p => '',
  };

  /// The Basic-auth credential ("user:pass") for the committed LAN path's probe;
  /// empty over an unencrypted link (the secret half is gated) or for P2P/none.
  String get lanCredential => switch (lanPath) {
    LanPath.ethernet => ethernetCredential,
    LanPath.wifiSta => previewCredential,
    LanPath.none || LanPath.p2p => '',
  };

  /// True when the reply reports a committed LAN path (Ethernet or WiFi-STA) —
  /// as opposed to the direct P2P link or no path at all.
  bool get hasCommittedLanPath =>
      lanPath == LanPath.ethernet || lanPath == LanPath.wifiSta;

  /// True when the reply carries a PENDING Ethernet-LAN confirmation handshake
  /// (R11): the arbiter selected Ethernet and is awaiting the phone's
  /// identity-probe verdict (a non-zero [ethernetConfirmId] with an endpoint to
  /// reach). Distinct from an already-committed Ethernet LAN on a plain Get
  /// (confirm id 0), which the reachability gate handles passively.
  bool get isEthernetHandshake =>
      lanPath == LanPath.ethernet &&
      ethernetConfirmId != 0 &&
      ethernetEndpoint.isNotEmpty;

  /// True when the committed LAN path carries a USABLE credential + endpoint —
  /// i.e. the app can run the identity probe without initiating a Set. A
  /// committed path with an EMPTY credential means "must send a Set to establish
  /// the credentialed LAN" (boot-before-Set / unencrypted link), NOT a usable
  /// handshake.
  bool get hasLanCredential =>
      hasCommittedLanPath && lanEndpoint.isNotEmpty && lanCredential.isNotEmpty;
}

/// The camera's reply to a `ConfirmLanPathCommand` (proto v5): the LAN path the
/// arbiter settled into after the app's Ethernet-LAN reachability verdict (R11).
/// The PARALLEL of [ConfirmPreviewReachableResult] for the Ethernet handshake.
class ConfirmLanPathResult {
  const ConfirmLanPathResult({
    required this.confirmId,
    required this.committedPath,
    required this.committed,
  });

  /// Echo of the confirmed handshake id.
  final int confirmId;

  /// The LAN path the arbiter committed to (Ethernet on success; the fallback
  /// path — or [LanPath.none] — when the confirm was a de-select / superseded).
  final LanPath committedPath;

  /// True when the arbiter finalized the confirmed path (the Ethernet LAN is
  /// live); false when it de-selected and fell through to the next provider.
  final bool committed;
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

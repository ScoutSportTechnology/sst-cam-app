/// The single-LAN-path connectivity gate (U9 / R8, R13, R22).
///
/// Turns a stream of [NetworkConfigResult]s (from a plain Get, a Set reply, or a
/// firmware LAN-path notification) into the operator-facing connectivity state,
/// gating "connected" on an IDENTITY-VERIFIED reachability probe against the
/// COMMITTED LAN IP — never on `inSharedWifi` alone. The probe reuses the same
/// `RtspDescribeProbe` (2xx-only RTSP DESCRIBE + Basic auth) the STA migration
/// uses; this gate does NOT build a new identity primitive.
///
/// Two review-hardened behaviours are baked in:
///  * **E1 — auto-re-probe.** A [probeFailed] state is never stranded waiting on
///    an operator retry against an abandoned path. Because the firmware
///    auto-falls Ethernet→STA→P2P (R19) and re-arbitrates on hotplug, any
///    subsequent result advancing the committed [LanPath] simply re-runs the
///    probe and transitions straight back to [reconnecting] for the new
///    candidate.
///  * **E4 — coalesce the cascade.** A generation counter supersedes any
///    in-flight probe when a newer result arrives, so a rapid Ethernet→STA→P2P
///    cascade renders a SINGLE [reconnecting] state (path-agnostic copy) that
///    only resolves to a terminal outcome ([connected], or [offline] when the
///    firmware lands on P2P/none) — never flashing every intermediate candidate.
library;

import '../../../core/models/network_config.dart';
import '../../../core/wifi/wifi_handoff.dart' show PreviewReachabilityProbe;

/// The operator-facing connectivity status derived from the committed LAN path +
/// the identity probe verdict.
enum LanConnectivityStatus {
  /// No committed LAN path — the camera is on its direct WiFi-Direct (P2P) link,
  /// or the path is unknown. Not "connected on the LAN".
  offline,

  /// A committed LAN path is reported but carries NO usable credential yet, so
  /// the app cannot identity-probe it: the operator must send a Set to establish
  /// the credentialed LAN (boot-before-Set / an unencrypted link). Treated as
  /// not-connected — never claimed as a usable handshake.
  mustProvision,

  /// The identity probe against the committed LAN endpoint is in flight — the
  /// single coalesced "switching / reconnecting…" transient (E4).
  reconnecting,

  /// The identity probe passed (2xx) — the camera is reachable on the committed
  /// LAN path.
  connected,

  /// The identity probe FAILED for the committed path (unreachable, or a
  /// same-subnet impostor that failed the auth/identity check, AE7). Distinct
  /// from the different-subnet `isolated` verdict; auto-re-probes on the next
  /// advancing result (E1).
  probeFailed,
}

/// Drives [LanConnectivityStatus] from successive [NetworkConfigResult]s using an
/// injected [PreviewReachabilityProbe]. Not a Riverpod object itself — the owning
/// widget holds one instance and rebuilds via [onChange]; tests drive [submit]
/// directly with a scripted probe.
class LanReachabilityGate {
  LanReachabilityGate({
    required PreviewReachabilityProbe probe,
    required this.onChange,
  }) : _probe = probe;

  final PreviewReachabilityProbe _probe;

  /// Invoked whenever the derived state changes (the owning widget passes a
  /// `setState` closure). Fires synchronously on the transition into
  /// [reconnecting] and again when the probe resolves.
  final void Function() onChange;

  LanConnectivityStatus _status = LanConnectivityStatus.offline;
  LanPath _path = LanPath.none;
  String _ssid = '';

  /// The committed generation. Bumped on every [submit] so a stale in-flight
  /// probe's resolution is dropped (E1/E4 supersede).
  int _generation = 0;

  LanConnectivityStatus get status => _status;

  /// The LAN path the current [status] refers to (the committed candidate).
  LanPath get path => _path;

  /// The SSID for a WiFi-STA committed path (empty for Ethernet/P2P/none).
  String get ssid => _ssid;

  /// True only after the identity probe has passed against the committed LAN.
  bool get isConnected => _status == LanConnectivityStatus.connected;

  /// Feed a plain-Get / Set / notification result. Runs the identity probe when
  /// the committed LAN path carries a credential; otherwise resolves
  /// synchronously. Never throws (the probe swallows its own failures).
  Future<void> submit(NetworkConfigResult result) async {
    // Supersede any in-flight probe (E4 coalesce, E1 advance).
    final generation = ++_generation;
    final path = result.lanPath;

    if (!result.hasCommittedLanPath) {
      // No committed LAN path (P2P / none). Honour a LEGACY inSharedWifi-only
      // report (pre-v5 firmware, or a mock, with no lan_path/credential to probe)
      // as connected so reconnect UX still works; otherwise offline.
      if (result.inSharedWifi && !result.hasLanCredential) {
        _set(
          LanConnectivityStatus.connected,
          LanPath.wifiSta,
          result.currentSsid,
        );
      } else {
        _set(LanConnectivityStatus.offline, path, '');
      }
      return;
    }

    // Committed LAN path but no usable credential → must send a Set (R8 note:
    // "LAN path present but no credential" is NOT a usable handshake).
    if (!result.hasLanCredential) {
      _set(LanConnectivityStatus.mustProvision, path, result.currentSsid);
      return;
    }

    // Credentialed committed LAN → identity-gate on the RTSP probe. Show the
    // single coalesced reconnecting transient while it runs.
    _set(LanConnectivityStatus.reconnecting, path, result.currentSsid);
    final reachable = await _probe.probe(
      result.lanEndpoint,
      result.lanCredential,
    );
    // Dropped if a newer result superseded this probe (E1 advance / E4 cascade).
    if (generation != _generation) return;
    if (reachable) {
      _set(LanConnectivityStatus.connected, path, result.currentSsid);
    } else {
      _set(LanConnectivityStatus.probeFailed, path, result.currentSsid);
    }
  }

  void _set(LanConnectivityStatus status, LanPath path, String ssid) {
    _status = status;
    _path = path;
    _ssid = ssid;
    onChange();
  }
}

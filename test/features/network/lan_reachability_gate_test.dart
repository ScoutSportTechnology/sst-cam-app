// U9 — the identity-verified reachability gate: gates "connected" on an RTSP
// probe against the COMMITTED LAN IP (R8), models the chosen LAN path, and
// coalesces the Ethernet→STA→P2P cascade (E1 auto-re-probe / E4 single
// "reconnecting…") — distinct from the different-subnet `isolated` case.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/models/network_config.dart';
import 'package:sst_cam_app/core/wifi/wifi_handoff.dart'
    show PreviewReachabilityProbe;
import 'package:sst_cam_app/features/settings/network/lan_reachability_gate.dart';

/// A probe with a scripted verdict per call (in order); records the endpoints it
/// was asked to probe. Resolves immediately.
class _ScriptProbe implements PreviewReachabilityProbe {
  _ScriptProbe(this._results);
  final List<bool> _results;
  final List<String> calls = [];
  int _i = 0;
  @override
  Future<bool> probe(String endpoint, String credential) async {
    calls.add(endpoint);
    final r = _i < _results.length ? _results[_i] : false;
    _i++;
    return r;
  }
}

/// A probe that stays PENDING until the test completes it — lets a test drive the
/// in-flight-supersede path (E4 coalesce, E1 advance).
class _GatedProbe implements PreviewReachabilityProbe {
  final List<Completer<bool>> completers = [];
  final List<String> calls = [];
  @override
  Future<bool> probe(String endpoint, String credential) {
    calls.add(endpoint);
    final c = Completer<bool>();
    completers.add(c);
    return c.future;
  }
}

NetworkConfigResult _result({
  LanPath lanPath = LanPath.none,
  String previewEndpoint = '',
  String previewCredential = '',
  String ethernetEndpoint = '',
  String ethernetCredential = '',
  bool inSharedWifi = false,
  String currentSsid = '',
}) => NetworkConfigResult(
  config: const NetworkConfig(),
  ethernetUp: false,
  ethernetAddress: '',
  wifiUp: false,
  wifiStatus: '',
  lanPath: lanPath,
  previewEndpoint: previewEndpoint,
  previewCredential: previewCredential,
  ethernetEndpoint: ethernetEndpoint,
  ethernetCredential: ethernetCredential,
  inSharedWifi: inSharedWifi,
  currentSsid: currentSsid,
);

void main() {
  test('committed WiFi-STA LAN, probe returns 2xx → connected', () async {
    final gate = LanReachabilityGate(
      probe: _ScriptProbe([true]),
      onChange: () {},
    );
    await gate.submit(
      _result(
        lanPath: LanPath.wifiSta,
        previewEndpoint: '10.10.1.142',
        previewCredential: 'preview:secret',
        inSharedWifi: true,
        currentSsid: 'Field-House',
      ),
    );
    expect(gate.status, LanConnectivityStatus.connected);
    expect(gate.path, LanPath.wifiSta);
    expect(gate.ssid, 'Field-House');
    expect(gate.isConnected, isTrue);
  });

  test('committed LAN answers but identity check fails (401/impostor) → NOT '
      'connected, probeFailed (AE7)', () async {
    final gate = LanReachabilityGate(
      probe: _ScriptProbe([false]),
      onChange: () {},
    );
    await gate.submit(
      _result(
        lanPath: LanPath.wifiSta,
        previewEndpoint: '10.10.1.142',
        previewCredential: 'preview:secret',
        inSharedWifi: true,
        currentSsid: 'Field-House',
      ),
    );
    expect(gate.status, LanConnectivityStatus.probeFailed);
    expect(gate.isConnected, isFalse);
  });

  test(
    'committed LAN path with an EMPTY credential → mustProvision (not a usable '
    'handshake), no probe run',
    () async {
      final probe = _ScriptProbe([true]);
      final gate = LanReachabilityGate(probe: probe, onChange: () {});
      await gate.submit(
        _result(
          lanPath: LanPath.wifiSta,
          previewEndpoint: '10.10.1.142',
          // credential empty (unencrypted link / boot-before-Set)
          inSharedWifi: true,
          currentSsid: 'Field-House',
        ),
      );
      expect(gate.status, LanConnectivityStatus.mustProvision);
      expect(probe.calls, isEmpty);
    },
  );

  test('P2P / none committed path → offline, no probe', () async {
    final probe = _ScriptProbe([true]);
    final gate = LanReachabilityGate(probe: probe, onChange: () {});
    await gate.submit(_result(lanPath: LanPath.p2p));
    expect(gate.status, LanConnectivityStatus.offline);
    expect(probe.calls, isEmpty);
  });

  test('legacy inSharedWifi-only (no lan_path/credential, pre-v5) → connected '
      'via fallback', () async {
    final probe = _ScriptProbe([true]);
    final gate = LanReachabilityGate(probe: probe, onChange: () {});
    await gate.submit(_result(inSharedWifi: true, currentSsid: 'Legacy-Net'));
    expect(gate.status, LanConnectivityStatus.connected);
    expect(gate.ssid, 'Legacy-Net');
    // No endpoint to probe → the fallback never touches the probe.
    expect(probe.calls, isEmpty);
  });

  test(
    'E1: a probe failure auto-re-probes when lan_path advances — straight to '
    'reconnecting, never stranded on an operator retry',
    () async {
      // First candidate (Ethernet) fails; the next advancing result (STA)
      // re-probes and succeeds.
      final probe = _ScriptProbe([false, true]);
      final captured = <LanConnectivityStatus>[];
      late final LanReachabilityGate gate;
      gate = LanReachabilityGate(
        probe: probe,
        onChange: () => captured.add(gate.status),
      );

      await gate.submit(
        _result(
          lanPath: LanPath.ethernet,
          ethernetEndpoint: '10.10.1.30',
          ethernetCredential: 'preview:eth',
        ),
      );
      expect(gate.status, LanConnectivityStatus.probeFailed);

      // A subsequent result advancing the LAN path auto-re-triggers a probe —
      // never gated on an operator retry against the abandoned Ethernet path.
      await gate.submit(
        _result(
          lanPath: LanPath.wifiSta,
          previewEndpoint: '10.10.1.142',
          previewCredential: 'preview:sta',
          inSharedWifi: true,
          currentSsid: 'Field-House',
        ),
      );
      expect(gate.status, LanConnectivityStatus.connected);
      // It transitioned back through reconnecting for the new candidate.
      expect(captured.contains(LanConnectivityStatus.reconnecting), isTrue);
      expect(probe.calls, ['10.10.1.30', '10.10.1.142']);
    },
  );

  test(
    'E4: a rapid Ethernet→STA cascade coalesces into a single reconnecting '
    'state; a stale in-flight probe cannot finalize a superseded pick',
    () async {
      final probe = _GatedProbe();
      final states = <LanConnectivityStatus>[];
      late final LanReachabilityGate gate;
      gate = LanReachabilityGate(
        probe: probe,
        onChange: () => states.add(gate.status),
      );

      // Candidate A (Ethernet) — probe pends.
      final subA = gate.submit(
        _result(
          lanPath: LanPath.ethernet,
          ethernetEndpoint: '10.10.1.30',
          ethernetCredential: 'preview:eth',
        ),
      );
      expect(gate.status, LanConnectivityStatus.reconnecting);

      // Candidate B (STA) arrives before A resolves — supersede; still one
      // reconnecting state, no flash to a terminal in between.
      final subB = gate.submit(
        _result(
          lanPath: LanPath.wifiSta,
          previewEndpoint: '10.10.1.142',
          previewCredential: 'preview:sta',
          inSharedWifi: true,
          currentSsid: 'Field-House',
        ),
      );
      expect(gate.status, LanConnectivityStatus.reconnecting);

      // The STALE candidate-A probe now resolves TRUE — it must be dropped
      // (superseded), never finalizing connected for the abandoned Ethernet pick.
      probe.completers[0].complete(true);
      await subA;
      expect(gate.status, LanConnectivityStatus.reconnecting);

      // The live candidate-B probe resolves → the single terminal outcome.
      probe.completers[1].complete(true);
      await subB;
      expect(gate.status, LanConnectivityStatus.connected);
      expect(gate.path, LanPath.wifiSta);

      // Across the whole cascade the transient never flashed a terminal state
      // between candidates — the only terminal is the final connected.
      final terminals = states
          .where(
            (s) =>
                s == LanConnectivityStatus.connected ||
                s == LanConnectivityStatus.probeFailed ||
                s == LanConnectivityStatus.offline,
          )
          .toList();
      expect(terminals, [LanConnectivityStatus.connected]);
    },
  );
}

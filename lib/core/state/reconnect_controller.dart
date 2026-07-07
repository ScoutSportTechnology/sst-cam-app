// BLE auto-reconnect loop (U6) — service-layer, above the connect controller.
//
// Trigger: an UNEXPECTED drop only, defined as the connection-state EDGE
// `connected → disconnected`. A manual disconnect emits `disconnecting`
// first (both the real impl and the parity mock), so its final `disconnected`
// arrives on a `disconnecting → disconnected` edge and never arms the loop —
// the enum state IS the intent signal. A failed reconnect attempt's own
// `connecting → disconnected` emission likewise never re-arms the loop or
// resets the backoff.
//
// Every attempt is the full U1 handshake via [ConnectController.connect]
// (protocol gate → time push → snapshot → rehydrate → reconcile) — no
// shortcut path; that is what makes auto-reconnect safe. The controller's
// in-flight dedup guarantees a manual connect racing a loop attempt shares
// one handshake (lifecycle-correctness learning).
//
// Stop conditions:
//   success            → idle (the `connected` emission disarms the loop)
//   manual disconnect  → idle ([manualDisconnect]; loop never starts)
//   different device   → idle (activeCameraId changed — loop dies with the
//                        selection)
//   bluetooth off      → gaveUp(bluetoothOff); re-eligible only on the NEXT
//                        unexpected drop, not when the adapter comes back
//   protocol mismatch  → gaveUp(protocolMismatch); permanent — retrying
//                        cannot fix wire-contract skew. Distinct UI surface
//                        (see ReconnectFailureNotice) points at updating the
//                        app / camera firmware.
//
// Backoff: a few quick attempts, then a slower steady cadence, interval-
// capped (never a tight loop). The loop itself runs until a stop condition —
// the firmware keeps its side up, so patience is free. Curve specifics are a
// deliberate implementation-time tunable (plan: tune on metal) — see
// [ReconnectBackoff].
//
// WiFi coupling: while the loop is eligible (phase == reconnecting) the
// wifi_handoff controller suppresses its disconnect-teardown so the app
// REJOINS the firmware's still-up group instead of cycling it (group
// re-formation kills Argus capture mid-session). A transition to `gaveUp`
// is the handoff's cue to finally tear the group down.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_providers.dart';
import '../ble/ble_service.dart';
import '../models/device.dart';
import '../../features/camera/camera_state.dart' show activeCameraIdProvider;
import 'connect_controller.dart';

/// Backoff curve for reconnect attempts. Overridable in tests (and tunable on
/// metal) via [reconnectBackoffProvider].
class ReconnectBackoff {
  const ReconnectBackoff({
    this.quickAttempts = 3,
    this.quickDelay = const Duration(seconds: 2),
    this.steadyDelay = const Duration(seconds: 12),
  });

  /// How many leading attempts run at [quickDelay] before the cadence slows.
  final int quickAttempts;
  final Duration quickDelay;

  /// The capped steady cadence — the "no infinite tight loop" guarantee.
  final Duration steadyDelay;

  /// Delay before attempt number `attemptsSoFar + 1`.
  Duration delayFor(int attemptsSoFar) =>
      attemptsSoFar < quickAttempts ? quickDelay : steadyDelay;
}

final reconnectBackoffProvider = Provider<ReconnectBackoff>(
  (_) => const ReconnectBackoff(),
);

enum ReconnectPhase {
  /// No loop running: never armed, stopped by success, manual disconnect, or
  /// a different-device selection.
  idle,

  /// An unexpected drop armed the loop; attempts are firing on the backoff
  /// cadence. The UI shows an honest disconnected state with a subtle
  /// reconnecting indicator while this holds.
  reconnecting,

  /// The loop stopped without a connection — see [ReconnectState.giveUpReason].
  gaveUp,
}

enum ReconnectGiveUpReason { bluetoothOff, protocolMismatch }

class ReconnectState {
  const ReconnectState({
    required this.phase,
    this.deviceId,
    this.attempt = 0,
    this.giveUpReason,
  });

  const ReconnectState.idle()
    : phase = ReconnectPhase.idle,
      deviceId = null,
      attempt = 0,
      giveUpReason = null;

  final ReconnectPhase phase;

  /// The device the loop targets (== the last successfully connected camera:
  /// the connect controller sets activeCameraId and lastConnectedDeviceId
  /// together on every successful connect, and the loop only ever arms for
  /// the device that just held a connection).
  final String? deviceId;

  /// Attempts fired since the drop (0 while waiting for the first one).
  final int attempt;

  /// Why the loop gave up — set only when [phase] is [ReconnectPhase.gaveUp].
  final ReconnectGiveUpReason? giveUpReason;

  /// Whether the loop still claims [id] — the wifi_handoff controller keeps
  /// the WiFi Direct group alive while this holds (rejoin, never cycle).
  bool isReconnecting(String id) =>
      phase == ReconnectPhase.reconnecting && deviceId == id;
}

final reconnectControllerProvider =
    NotifierProvider<ReconnectController, ReconnectState>(
      ReconnectController.new,
    );

class ReconnectController extends Notifier<ReconnectState> {
  StreamSubscription<CameraConnectionState>? _connSub;
  Timer? _retryTimer;
  String? _watchedId;
  CameraConnectionState? _lastSeen;
  int _attempts = 0;
  bool _bluetoothOn = true;

  @override
  ReconnectState build() {
    ref.onDispose(() {
      _retryTimer?.cancel();
      _connSub?.cancel();
    });

    // Adapter off stops a running loop; coming back on does NOT resume it —
    // eligibility returns only with the next unexpected drop.
    ref.listen(bluetoothOnProvider, (_, next) {
      _onBluetooth(next.valueOrNull ?? true);
    });

    // Follow the active camera: its connection stream carries the drop edge;
    // selecting a different camera (or clearing it on manual disconnect)
    // kills any loop for the previous one.
    ref.listen(activeCameraIdProvider, (_, id) => _follow(id));
    _watchedId = ref.read(activeCameraIdProvider);
    _subscribe(_watchedId);

    return const ReconnectState.idle();
  }

  /// User-intent disconnect — the single path every manual-disconnect call
  /// site goes through. Disarms the loop, drops the link (the service emits
  /// `disconnecting` first, so the final `disconnected` never reads as an
  /// unexpected drop), and clears the active camera. The WiFi group teardown
  /// then proceeds normally in wifi_handoff via the camera-change branch.
  Future<void> manualDisconnect(String deviceId) async {
    _stopLoop();
    try {
      await ref.read(bleServiceProvider).disconnect(deviceId);
    } finally {
      ref.read(activeCameraIdProvider.notifier).state = null;
    }
  }

  void _onBluetooth(bool on) {
    _bluetoothOn = on;
    if (!on && state.phase == ReconnectPhase.reconnecting) {
      _giveUp(ReconnectGiveUpReason.bluetoothOff);
    }
  }

  void _follow(String? id) {
    if (id == _watchedId) return;
    _watchedId = id;
    // Different-device selection (or manual clear): the loop for the old
    // device stops — and any stale give-up surface is reset with it.
    _stopLoop();
    _subscribe(id);
  }

  void _subscribe(String? id) {
    _connSub?.cancel();
    _connSub = null;
    _lastSeen = null;
    if (id == null) return;
    // activeCameraId is set only by a successful connect, so the device is
    // `connected` at subscribe time; broadcast streams don't replay history,
    // so seed the edge tracker accordingly (the real impl's seeded stream
    // will confirm with a `connected` replay; the mock's plain broadcast
    // won't — both land on the same tracker value).
    _lastSeen = CameraConnectionState.connected;
    _connSub = ref
        .read(bleServiceProvider)
        .connectionStateStream(id)
        .listen((s) => _onConnState(id, s));
  }

  void _onConnState(String deviceId, CameraConnectionState s) {
    final prev = _lastSeen;
    _lastSeen = s;
    switch (s) {
      case CameraConnectionState.connected:
        // Success — whether a loop attempt or a manual connect won, the
        // loop's job is done (and any give-up surface is cleared).
        _stopLoop();
      case CameraConnectionState.disconnected:
        // Arm ONLY on the edge from `connected`. `disconnecting → disconnected`
        // is a manual disconnect; `connecting → disconnected` is a failed
        // attempt's own emission (never re-arms, never resets backoff).
        if (prev == CameraConnectionState.connected && _bluetoothOn) {
          _arm(deviceId);
        }
      case CameraConnectionState.connecting:
      case CameraConnectionState.reconciling:
      case CameraConnectionState.disconnecting:
        break;
    }
  }

  void _arm(String deviceId) {
    _attempts = 0;
    state = ReconnectState(
      phase: ReconnectPhase.reconnecting,
      deviceId: deviceId,
    );
    _scheduleNext(deviceId);
  }

  void _scheduleNext(String deviceId) {
    _retryTimer?.cancel();
    final delay = ref.read(reconnectBackoffProvider).delayFor(_attempts);
    _retryTimer = Timer(delay, () => _attempt(deviceId));
  }

  Future<void> _attempt(String deviceId) async {
    if (!state.isReconnecting(deviceId)) return;
    _attempts++;
    state = ReconnectState(
      phase: ReconnectPhase.reconnecting,
      deviceId: deviceId,
      attempt: _attempts,
    );
    try {
      // Full U1 handshake — shared entry point, in-flight dedup included.
      await ref.read(connectControllerProvider).connect(deviceId);
      _stopLoop(); // authoritative even if the connected emission lags
    } on BleProtocolVersionException {
      _giveUp(ReconnectGiveUpReason.protocolMismatch);
    } catch (_) {
      // Transient (link, handshake, timeout) — keep going on the cadence.
      // The connect controller already dropped the link and surfaced/typed
      // the failure; there is nothing to bubble from a background attempt.
      if (state.isReconnecting(deviceId)) _scheduleNext(deviceId);
    }
  }

  void _giveUp(ReconnectGiveUpReason reason) {
    _retryTimer?.cancel();
    _retryTimer = null;
    state = ReconnectState(
      phase: ReconnectPhase.gaveUp,
      deviceId: state.deviceId,
      attempt: _attempts,
      giveUpReason: reason,
    );
  }

  void _stopLoop() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _attempts = 0;
    if (state.phase != ReconnectPhase.idle) {
      state = const ReconnectState.idle();
    }
  }
}

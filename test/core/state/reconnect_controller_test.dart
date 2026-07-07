// U6 — BLE auto-reconnect (ReconnectController).
//
// Proves the loop against the parity mock: an UNEXPECTED drop (bare
// `connected → disconnected` edge) arms retries through the full U1
// handshake; a manual disconnect (`disconnecting` first) never does. Stop
// conditions: success, manual disconnect, different-device selection,
// bluetooth-off (re-eligible only on the next drop), protocol mismatch
// (permanent, distinct give-up reason). Backoff is interval-capped — a
// device that stays gone produces a patient cadence, never a tight loop.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/core/state/connect_controller.dart';
import 'package:sst_cam_app/core/state/persisted_match_store.dart';
import 'package:sst_cam_app/core/state/reconnect_controller.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';

const _kDeviceId = 'SST-CAM-001';
const _kOtherDeviceId = 'SST-CAM-002';

/// Fast test backoff: 2 quick attempts at 30 ms, then a 100 ms steady
/// cadence — same curve shape as production, compressed timescale.
const _kTestBackoff = ReconnectBackoff(
  quickAttempts: 2,
  quickDelay: Duration(milliseconds: 30),
  steadyDelay: Duration(milliseconds: 100),
);

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String? reason,
}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) {
      fail(reason ?? 'condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  late MockBleService mock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mock = MockBleService(
      scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
      connectionDelay: Duration.zero,
      failureRate: 0.0,
      randomSeed: 42,
    );
  });

  tearDown(() => mock.dispose());

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        bleServiceProvider.overrideWithValue(mock),
        persistedMatchStoreProvider.overrideWithValue(
          const NoPersistedMatchStore(),
        ),
        reconnectBackoffProvider.overrideWithValue(_kTestBackoff),
      ],
    );
    addTearDown(container.dispose);
    // Mount the loop (a lazy Notifier) for the container's lifetime — same
    // as the app shell does.
    container.listen(reconnectControllerProvider, (_, _) {});
    return container;
  }

  ReconnectState loopState(ProviderContainer c) =>
      c.read(reconnectControllerProvider);

  Future<void> connectManually(ProviderContainer c) =>
      c.read(connectControllerProvider).connect(_kDeviceId);

  group('Trigger — unexpected drop only', () {
    test('unexpected drop arms the loop; the attempt runs the FULL handshake '
        'and rehydrates exactly like a manual connect', () async {
      final container = makeContainer();

      CameraConnectionState? current;
      mock.connectionStateStream(_kDeviceId).listen((s) => current = s);

      await connectManually(container);
      expect(current, CameraConnectionState.connected);

      // Wipe the evidence a manual connect left so the loop must reproduce it.
      mock.receivedCommands.clear();
      container.read(sessionSnapshotProvider.notifier).state = null;

      mock.simulateUnexpectedDrop(_kDeviceId);
      await _waitFor(
        () => loopState(container).phase == ReconnectPhase.reconnecting,
        reason: 'a bare connected→disconnected edge must arm the loop',
      );

      await _waitFor(
        () => current == CameraConnectionState.connected,
        reason: 'the loop attempt should re-establish the connection',
      );

      // Full U1 handshake on the wire — no shortcut path.
      final types = mock.receivedCommands.map((c) => c.runtimeType).toList();
      expect(
        types,
        containsAllInOrder([SetDeviceTimeCommand, GetSessionSnapshotCommand]),
      );
      // Rehydrated like a manual connect: snapshot adopted, side effects ran.
      expect(container.read(sessionSnapshotProvider), isNotNull);
      expect(container.read(activeCameraIdProvider), _kDeviceId);
      // Success disarms the loop.
      await _waitFor(() => loopState(container).phase == ReconnectPhase.idle);
    });

    test('manual disconnect never starts the loop (and the mock mirrors the '
        'real impl: disconnecting precedes disconnected)', () async {
      final container = makeContainer();
      await connectManually(container);

      final states = <CameraConnectionState>[];
      mock.connectionStateStream(_kDeviceId).listen(states.add);
      mock.receivedCommands.clear();

      await container
          .read(reconnectControllerProvider.notifier)
          .manualDisconnect(_kDeviceId);

      // Parity: the app-initiated drop announces itself.
      expect(
        states,
        containsAllInOrder([
          CameraConnectionState.disconnecting,
          CameraConnectionState.disconnected,
        ]),
      );
      expect(container.read(activeCameraIdProvider), isNull);

      // Several backoff windows later: still idle, nothing on the wire.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(loopState(container).phase, ReconnectPhase.idle);
      expect(mock.receivedCommands, isEmpty);
    });

    test('a failed attempt\'s own disconnected emission never re-arms or '
        'resets the backoff; device stays gone → capped cadence, honest '
        'reconnecting state, no tight loop', () async {
      final container = makeContainer();
      await connectManually(container);

      mock.failureRate = 1.0; // camera is gone — every connect throws
      mock.simulateUnexpectedDrop(_kDeviceId);

      await Future<void>.delayed(const Duration(milliseconds: 650));
      final s = loopState(container);
      // Honest UI state: still disconnected, still visibly retrying.
      expect(s.phase, ReconnectPhase.reconnecting);
      expect(s.deviceId, _kDeviceId);
      // 650 ms at (2 × 30 ms quick + 100 ms steady) ≈ 2 + 5 attempts. If a
      // failed attempt's disconnected emission re-armed the loop (resetting
      // to the quick cadence) this would run 15+; a tight loop, far more.
      expect(s.attempt, greaterThanOrEqualTo(2));
      expect(s.attempt, lessThanOrEqualTo(10));
    });
  });

  group('Stop conditions', () {
    test('manual connect during backoff dedups to a single in-flight '
        'handshake (loop vs manual, lifecycle learning)', () async {
      final container = makeContainer();
      await connectManually(container);

      CameraConnectionState? current;
      mock.connectionStateStream(_kDeviceId).listen((s) => current = s);

      mock.receivedCommands.clear();
      mock.simulateUnexpectedDrop(_kDeviceId);

      // Wait until a loop attempt is in flight (attempt counter moves at
      // attempt start; the mock handshake then takes ~200 ms)...
      await _waitFor(() => loopState(container).attempt >= 1);
      // ...and race a manual connect against it.
      await connectManually(container);

      await _waitFor(() => current == CameraConnectionState.connected);
      await _waitFor(() => loopState(container).phase == ReconnectPhase.idle);
      expect(
        mock.receivedCommands.whereType<SetDeviceTimeCommand>().length,
        1,
        reason: 'loop attempt + manual connect must share ONE handshake',
      );
    });

    test('bluetooth off stops the loop; adapter back on does NOT resume it — '
        're-eligible only on the next unexpected drop', () async {
      final container = makeContainer();
      await connectManually(container);

      mock.failureRate = 1.0; // keep the loop failing so it stays armed
      mock.simulateUnexpectedDrop(_kDeviceId);
      await _waitFor(
        () => loopState(container).phase == ReconnectPhase.reconnecting,
      );

      mock.setBluetoothOn(false);
      await _waitFor(
        () =>
            loopState(container).phase == ReconnectPhase.gaveUp &&
            loopState(container).giveUpReason ==
                ReconnectGiveUpReason.bluetoothOff,
      );

      // Adapter comes back: the loop stays stopped.
      mock.setBluetoothOn(true);
      final attemptsAtStop = loopState(container).attempt;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(loopState(container).phase, ReconnectPhase.gaveUp);
      expect(loopState(container).attempt, attemptsAtStop);

      // Re-eligibility: a fresh manual connect + a NEW unexpected drop arm
      // the loop again.
      mock.failureRate = 0.0;
      await connectManually(container);
      expect(loopState(container).phase, ReconnectPhase.idle);
      mock.failureRate = 1.0;
      mock.simulateUnexpectedDrop(_kDeviceId);
      await _waitFor(
        () => loopState(container).phase == ReconnectPhase.reconnecting,
        reason: 'eligibility returns with the next unexpected drop',
      );
    });

    test('protocol mismatch during the loop is permanent: gives up with the '
        'distinct reason and stops attempting', () async {
      final container = makeContainer();
      await connectManually(container);

      // Firmware "updated" behind the app's back mid-session.
      mock.mockProtocolVersion = kAppProtocolVersion + 1;
      mock.simulateUnexpectedDrop(_kDeviceId);

      await _waitFor(
        () => loopState(container).phase == ReconnectPhase.gaveUp,
        reason: 'a version-skew attempt must stop the loop',
      );
      expect(
        loopState(container).giveUpReason,
        ReconnectGiveUpReason.protocolMismatch,
      );

      final attemptsAtStop = loopState(container).attempt;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(loopState(container).attempt, attemptsAtStop);
      expect(loopState(container).phase, ReconnectPhase.gaveUp);
    });

    test('selecting a different device stops the loop', () async {
      final container = makeContainer();
      await connectManually(container);

      mock.failureRate = 1.0;
      mock.simulateUnexpectedDrop(_kDeviceId);
      await _waitFor(
        () => loopState(container).phase == ReconnectPhase.reconnecting,
      );

      container.read(activeCameraIdProvider.notifier).state = _kOtherDeviceId;
      expect(loopState(container).phase, ReconnectPhase.idle);

      // No further attempts against the old device: its stream stays silent.
      final states = <CameraConnectionState>[];
      mock.connectionStateStream(_kDeviceId).listen(states.add);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(states, isNot(contains(CameraConnectionState.connecting)));
    });
  });
}

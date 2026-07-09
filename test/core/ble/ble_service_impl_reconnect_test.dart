// Regression: manual disconnect → reconnect within the SAME app process.
//
// Field bug (2026-07-06, real Jetson + phone): after a manual disconnect, the
// next connect brought the BLE link up ("connected to sst-cam-7967") but every
// handshake command then timed out ("Connect handshake timed out"); retrying
// never helped, while killing and reopening the app made the very same connect
// succeed against the same firmware process. That signature means app-process
// state retained across a manual disconnect poisoned the next connect.
//
// The MockBleService cannot see this class of bug — it stubs connect() at the
// BleService port. These tests drive the REAL BleServiceImpl over a fake
// FlutterBluePlusPlatform that models the platform semantics that matter:
//   - notify (CCCD) subscriptions do NOT survive a disconnect — the peripheral
//     only notifies the response characteristic while the CURRENT connection
//     has subscribed (the firmware answers on the same GATT session that
//     re-enabled notifications);
//   - platform "connect" on an already-connected device is a no-op (returns
//     changed=false), so a half-torn-down previous connection short-circuits
//     the next one at the platform layer;
//   - connection state changes are delivered as async events, exactly like
//     the FBP method-channel event stream.
//
// The regression sequence asserted here: connect → full handshake → manual
// disconnect → connect → full handshake — twice in a row.

import 'dart:async';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/ble/ble_service.dart';
import 'package:sst_cam_app/core/ble/ble_service_impl.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/core/state/connect_controller.dart';
import 'package:sst_cam_app/core/state/persisted_match_store.dart';
import 'package:sst_cam_app/core/state/reconnect_controller.dart';
import 'package:sst_cam_app/models/proto/bluetooth.pb.dart' as proto;

// UUIDs from proto/README.md — must match ble_service_impl.dart.
final _svcUuid = Guid('A1B2C3D400010000800000805F9B34FB');
final _cmdWriteUuid = Guid('A1B2C3D400110000800000805F9B34FB');
final _cmdResponseUuid = Guid('A1B2C3D400120000800000805F9B34FB');

/// Emulated firmware GATT peer behind the fake platform: decodes ChunkedPayload
/// command frames written to cmdWrite and answers on cmdResponse — but ONLY
/// while the current connection has notifications enabled, mirroring real CCCD
/// semantics (a notify subscription never survives a disconnect).
class _FakeFirmware {
  _FakeFirmware(this.platform);

  final _FakeBlePlatform platform;

  /// Wire-level command names received, in order (acks excluded).
  final List<String> received = [];

  final Map<String, Map<int, List<int>>> _partial = {};

  void onWrite(DeviceIdentifier remoteId, List<int> bytes) {
    final chunk = proto.ChunkedPayload.fromBuffer(bytes);
    if (chunk.totalChunks == 0) return; // app→fw ChunkAck — flow control only
    // Symmetric flow control (proto/README.md): the firmware acks every
    // received payload chunk. The app's ack-gated multi-frame write loop
    // stalls without this — exactly like the real peer.
    platform.notifyResponse(
      remoteId,
      proto.ChunkedPayload(
        correlationId: chunk.correlationId,
        chunkIndex: chunk.chunkIndex,
        totalChunks: 0,
      ).writeToBuffer(),
    );
    final byIndex = _partial.putIfAbsent(chunk.correlationId, () => {});
    byIndex[chunk.chunkIndex] = chunk.data;
    if (byIndex.length < chunk.totalChunks) return;
    final data = <int>[
      for (var i = 0; i < chunk.totalChunks; i++) ...byIndex[i]!,
    ];
    _partial.remove(chunk.correlationId);
    _handleCommand(remoteId, proto.Command.fromBuffer(data));
  }

  void _handleCommand(DeviceIdentifier remoteId, proto.Command cmd) {
    final resp = proto.CommandResponse(
      correlationId: cmd.correlationId,
      status: proto.ResponseStatus.OK,
    );
    switch (cmd.whichPayload()) {
      case proto.Command_Payload.getDeviceInfo:
        received.add('getDeviceInfo');
        resp.deviceInfo = proto.DeviceInfoResponse(
          deviceId: remoteId.str,
          name: 'sst-cam-test',
          firmwareVersion: '0.0.0-test',
          model: 'fake',
          protocolVersion: kAppProtocolVersion,
        );
      case proto.Command_Payload.setDeviceTime:
        received.add('setDeviceTime');
      case proto.Command_Payload.getSessionSnapshot:
        received.add('getSessionSnapshot');
        resp.sessionSnapshot = proto.SessionSnapshotResponse(
          sessionPhase: proto.SessionPhase.SESSION_IDLE,
          activeCameraIndex: 0,
          isRecording: false,
          isStreaming: false,
        );
      case proto.Command_Payload.getTelemetry:
        received.add('getTelemetry');
        resp.telemetry = proto.DeviceTelemetry(
          storageFreeBytes: Int64(1024),
          storageTotalBytes: Int64(2048),
          uptimeSeconds: Int64(1),
        );
      case proto.Command_Payload.getMatchState:
        received.add('getMatchState');
        resp.matchState = proto.MatchState();
      case proto.Command_Payload.setMatchState:
        received.add('setMatchState');
      default:
        received.add(cmd.whichPayload().name);
    }
    platform.notifyResponse(
      remoteId,
      proto.ChunkedPayload(
        correlationId: cmd.correlationId,
        chunkIndex: 0,
        totalChunks: 1,
        data: resp.writeToBuffer(),
      ).writeToBuffer(),
    );
  }
}

/// Fake [FlutterBluePlusPlatform] modelling the Android/BlueZ semantics the
/// reconnect path depends on. One instance per test FILE: FlutterBluePlus
/// wires its internal global listeners to the instance present at first use,
/// so tests must not swap instances (they use distinct device ids instead).
final class _FakeBlePlatform extends FlutterBluePlusPlatform {
  late final _FakeFirmware firmware = _FakeFirmware(this);

  final _connectionState =
      StreamController<BmConnectionStateResponse>.broadcast();
  final _characteristicReceived =
      StreamController<BmCharacteristicData>.broadcast();
  final _characteristicWritten =
      StreamController<BmCharacteristicData>.broadcast();
  final _descriptorWritten = StreamController<BmDescriptorData>.broadcast();
  final _discoveredServices =
      StreamController<BmDiscoverServicesResult>.broadcast();
  final _mtuChanged = StreamController<BmMtuChangedResponse>.broadcast();
  final _scanResponse = StreamController<BmScanResponse>.broadcast();

  /// Device ids currently ADVERTISING — delivered on every platform scan.
  /// The impl's connect() resolves the camera's live address by scanning
  /// before it dials (stale-remoteId / GATT 147 fix), so every test that
  /// connects must have its device id registered here (see `setUp`).
  final Set<DeviceIdentifier> advertised = {};

  /// Advertised name per id; defaults to a compliant `sst-cam-` name.
  final Map<DeviceIdentifier, String> advertisedNames = {};

  /// Devices whose GATT link is currently up.
  final Set<DeviceIdentifier> connected = {};

  /// Devices with an in-progress (stalled) connect attempt — see
  /// [stallConnect]. Mirrors the Android plugin's mCurrentlyConnectingDevices.
  final Set<DeviceIdentifier> connecting = {};

  /// Devices whose cmdResponse CCCD is subscribed ON THE CURRENT connection.
  final Set<DeviceIdentifier> notifying = {};

  /// When true, connect() starts an attempt that never completes (no
  /// connected event) until a disconnect cancels it — models a congested
  /// radio / unresponsive platform connect.
  bool stallConnect = false;

  /// Fails the next CCCD write once — models a transient post-link failure.
  bool failNextSetNotify = false;

  /// Counters for asserting the impl re-runs platform setup on reconnect.
  int connectCalls = 0;
  int discoverCalls = 0;
  int setNotifyCalls = 0;

  @override
  Stream<BmConnectionStateResponse> get onConnectionStateChanged =>
      _connectionState.stream;
  @override
  Stream<BmCharacteristicData> get onCharacteristicReceived =>
      _characteristicReceived.stream;
  @override
  Stream<BmCharacteristicData> get onCharacteristicWritten =>
      _characteristicWritten.stream;
  @override
  Stream<BmDescriptorData> get onDescriptorWritten => _descriptorWritten.stream;
  @override
  Stream<BmDiscoverServicesResult> get onDiscoveredServices =>
      _discoveredServices.stream;
  @override
  Stream<BmMtuChangedResponse> get onMtuChanged => _mtuChanged.stream;
  @override
  Stream<BmScanResponse> get onScanResponse => _scanResponse.stream;

  @override
  Future<bool> startScan(BmScanSettings request) async {
    scheduleMicrotask(() {
      if (advertised.isEmpty) return;
      _scanResponse.add(
        BmScanResponse(
          advertisements: [
            for (final id in advertised)
              BmScanAdvertisement(
                remoteId: id,
                platformName: null,
                advName: advertisedNames[id] ?? 'sst-cam-0001',
                connectable: true,
                txPowerLevel: null,
                appearance: null,
                manufacturerData: const {},
                serviceData: const {},
                serviceUuids: [_svcUuid],
                rssi: -50,
              ),
          ],
          success: true,
          errorCode: 0,
          errorString: '',
        ),
      );
    });
    return true;
  }

  @override
  Future<bool> stopScan(BmStopScanRequest request) async => true;

  void _emitConnectionState(DeviceIdentifier id, BmConnectionStateEnum state) {
    _connectionState.add(
      BmConnectionStateResponse(
        remoteId: id,
        connectionState: state,
        disconnectReasonCode: null,
        disconnectReasonString: null,
      ),
    );
  }

  @override
  Future<bool> connect(BmConnectRequest request) async {
    connectCalls++;
    if (connected.contains(request.remoteId)) return false; // no work to do
    if (connecting.contains(request.remoteId)) {
      return true; // already connecting
    }
    if (stallConnect) {
      connecting.add(request.remoteId);
      return true; // attempt started; connected event never arrives
    }
    connected.add(request.remoteId);
    scheduleMicrotask(
      () => _emitConnectionState(
        request.remoteId,
        BmConnectionStateEnum.connected,
      ),
    );
    return true;
  }

  @override
  Future<bool> disconnect(BmDisconnectRequest request) async {
    if (connecting.remove(request.remoteId)) {
      // Cancel an in-progress attempt (plugin: mCurrentlyConnectingDevices
      // path) — synthesizes the disconnected event the waiting connect sees.
      scheduleMicrotask(
        () => _emitConnectionState(
          request.remoteId,
          BmConnectionStateEnum.disconnected,
        ),
      );
      return true;
    }
    if (!connected.contains(request.remoteId)) return false;
    dropLink(request.remoteId);
    return true;
  }

  /// Drops the GATT link (used by [disconnect] and available to tests to
  /// simulate an unexpected drop). Notify subscriptions die with the link.
  void dropLink(DeviceIdentifier id) {
    connected.remove(id);
    notifying.remove(id);
    scheduleMicrotask(
      () => _emitConnectionState(id, BmConnectionStateEnum.disconnected),
    );
  }

  @override
  Future<bool> discoverServices(BmDiscoverServicesRequest request) async {
    discoverCalls++;
    final id = request.remoteId;
    BmCharacteristicProperties props({
      required bool write,
      required bool notify,
    }) => BmCharacteristicProperties(
      broadcast: false,
      read: false,
      writeWithoutResponse: write,
      write: false,
      notify: notify,
      indicate: false,
      authenticatedSignedWrites: false,
      extendedProperties: false,
      notifyEncryptionRequired: false,
      indicateEncryptionRequired: false,
    );
    BmBluetoothCharacteristic chr(Guid uuid, {required bool notify}) =>
        BmBluetoothCharacteristic(
          remoteId: id,
          primaryServiceUuid: null,
          serviceUuid: _svcUuid,
          characteristicUuid: uuid,
          instanceId: 0,
          descriptors: [],
          properties: props(write: !notify, notify: notify),
        );
    scheduleMicrotask(() {
      _discoveredServices.add(
        BmDiscoverServicesResult(
          remoteId: id,
          services: [
            BmBluetoothService(
              remoteId: id,
              primaryServiceUuid: null,
              serviceUuid: _svcUuid,
              characteristics: [
                chr(_cmdWriteUuid, notify: false),
                chr(_cmdResponseUuid, notify: true),
              ],
            ),
          ],
          success: true,
          errorCode: 0,
          errorString: '',
        ),
      );
    });
    return true;
  }

  @override
  Future<bool> setNotifyValue(BmSetNotifyValueRequest request) async {
    setNotifyCalls++;
    if (failNextSetNotify) {
      failNextSetNotify = false;
      scheduleMicrotask(() {
        _descriptorWritten.add(
          BmDescriptorData(
            remoteId: request.remoteId,
            primaryServiceUuid: null,
            serviceUuid: request.serviceUuid,
            characteristicUuid: request.characteristicUuid,
            instanceId: request.instanceId,
            descriptorUuid: Guid('00002902-0000-1000-8000-00805f9b34fb'),
            value: const [],
            success: false,
            errorCode: 133,
            errorString: 'simulated gatt failure',
          ),
        );
      });
      return true;
    }
    if (request.enable) {
      notifying.add(request.remoteId);
    } else {
      notifying.remove(request.remoteId);
    }
    scheduleMicrotask(() {
      _descriptorWritten.add(
        BmDescriptorData(
          remoteId: request.remoteId,
          primaryServiceUuid: null,
          serviceUuid: request.serviceUuid,
          characteristicUuid: request.characteristicUuid,
          instanceId: request.instanceId,
          descriptorUuid: Guid('00002902-0000-1000-8000-00805f9b34fb'),
          value: [request.enable ? 1 : 0, 0],
          success: true,
          errorCode: 0,
          errorString: '',
        ),
      );
    });
    return true; // has a CCCD
  }

  @override
  Future<bool> writeCharacteristic(BmWriteCharacteristicRequest request) async {
    final bytes = List<int>.from(request.value);
    scheduleMicrotask(() {
      // The platform reports the packet as sent (FBP awaits this even for
      // write-without-response), then the peripheral processes it.
      _characteristicWritten.add(
        BmCharacteristicData(
          remoteId: request.remoteId,
          primaryServiceUuid: null,
          serviceUuid: request.serviceUuid,
          characteristicUuid: request.characteristicUuid,
          instanceId: request.instanceId,
          value: bytes,
          success: true,
          errorCode: 0,
          errorString: '',
        ),
      );
      firmware.onWrite(request.remoteId, bytes);
    });
    return true;
  }

  @override
  Future<bool> requestMtu(BmMtuChangeRequest request) async {
    scheduleMicrotask(() {
      _mtuChanged.add(
        BmMtuChangedResponse(remoteId: request.remoteId, mtu: 512),
      );
    });
    return true;
  }

  /// Peripheral→central notification on the cmdResponse characteristic.
  /// Silently dropped unless the CURRENT connection subscribed — real GATT
  /// notify semantics, and the heart of this regression.
  void notifyResponse(DeviceIdentifier id, Uint8List bytes) {
    if (!connected.contains(id) || !notifying.contains(id)) return;
    _characteristicReceived.add(
      BmCharacteristicData(
        remoteId: id,
        primaryServiceUuid: null,
        serviceUuid: _svcUuid,
        characteristicUuid: _cmdResponseUuid,
        instanceId: 0,
        value: bytes,
        success: true,
        errorCode: 0,
        errorString: '',
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ONE platform instance for the whole file — FlutterBluePlus binds its
  // internal listeners to the first instance it sees (static init).
  final platform = _FakeBlePlatform();
  FlutterBluePlusPlatform.instance = platform;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    platform.firmware.received.clear();
    platform.connectCalls = 0;
    platform.discoverCalls = 0;
    platform.setNotifyCalls = 0;
    platform.stallConnect = false;
    platform.failNextSetNotify = false;
    platform.connecting.clear();
    // Every device id used in this file advertises by default — connect()
    // scan-resolves the live address before dialing, so an unadvertised id
    // fails fast with "Camera not found" (the rotation tests below override).
    platform.advertised
      ..clear()
      ..addAll([
        for (var i = 1; i <= 9; i++) DeviceIdentifier('AA:BB:CC:00:00:0$i'),
      ]);
    platform.advertisedNames.clear();
  });

  group('BleServiceImpl reconnect (real impl over fake platform)', () {
    test('connect → manual disconnect → connect: the full handshake round '
        'trip works twice in a row on the SAME service instance', () async {
      const deviceId = 'AA:BB:CC:00:00:01';
      final svc = BleServiceImpl(disconnectSettle: Duration.zero);
      addTearDown(svc.dispose);

      final states = <CameraConnectionState>[];
      svc.connectionStateStream(deviceId).listen(states.add);

      Future<void> fullCycle() async {
        await svc.connect(deviceId);

        // Handshake-shaped traffic over the real chunked protocol.
        final info = await svc.getDeviceInfo(deviceId);
        expect(info, isNotNull, reason: 'GetDeviceInfo must round-trip');
        expect(info!.protocolVersion, kAppProtocolVersion);

        final time = await svc.sendCommand<void>(
          deviceId,
          SetDeviceTimeCommand(epochMs: DateTime.now().millisecondsSinceEpoch),
        );
        expect(time.isOk, isTrue, reason: 'SetDeviceTime must round-trip');

        svc.completeHandshake(deviceId);
        await svc.disconnect(deviceId);
        // Let the async disconnected event settle before reconnecting.
        await Future<void>.delayed(Duration.zero);
      }

      // The regression: the 2nd and 3rd cycles reuse the persistent device
      // slot the 1st cycle created. On the field failure the reconnect's
      // commands never resolved (stale notify/session state) and timed out.
      await fullCycle();
      await fullCycle();
      await fullCycle();

      expect(
        platform.firmware.received.where((c) => c == 'getDeviceInfo').length,
        3,
      );
      // Every cycle re-ran platform-level setup — no short-circuit reuse of
      // the dead connection's services/subscription.
      expect(platform.connectCalls, 3);
      expect(platform.discoverCalls, 3);
      expect(platform.setNotifyCalls, 3);
      // Each cycle walked connecting → reconciling → connected →
      // disconnecting → disconnected on the SAME seeded stream.
      final onePass = [
        CameraConnectionState.connecting,
        CameraConnectionState.reconciling,
        CameraConnectionState.connected,
        CameraConnectionState.disconnecting,
        CameraConnectionState.disconnected,
      ];
      expect(states, containsAllInOrder([...onePass, ...onePass, ...onePass]));
    });

    test('unexpected link drop mid-session: reconnect still handshakes '
        'cleanly', () async {
      const deviceId = 'AA:BB:CC:00:00:02';
      final svc = BleServiceImpl(disconnectSettle: Duration.zero);
      addTearDown(svc.dispose);

      await svc.connect(deviceId);
      expect(await svc.getDeviceInfo(deviceId), isNotNull);
      svc.completeHandshake(deviceId);

      // Firmware/radio side drops the link without an app-side disconnect.
      platform.dropLink(DeviceIdentifier(deviceId));
      await Future<void>.delayed(Duration.zero);

      await svc.connect(deviceId);
      expect(
        await svc.getDeviceInfo(deviceId),
        isNotNull,
        reason: 'handshake after an unexpected drop must round-trip',
      );
    });
  });

  group(
    'ConnectController + manualDisconnect (full §9b over the real impl)',
    () {
      test('connect → manualDisconnect → connect succeeds with a full '
          'handshake, twice in a row', () async {
        const deviceId = 'AA:BB:CC:00:00:03';
        final svc = BleServiceImpl(disconnectSettle: Duration.zero);
        addTearDown(svc.dispose);
        final container = ProviderContainer(
          overrides: [
            bleServiceProvider.overrideWithValue(svc),
            persistedMatchStoreProvider.overrideWithValue(
              const NoPersistedMatchStore(),
            ),
          ],
        );
        addTearDown(container.dispose);

        CameraConnectionState? current;
        svc.connectionStateStream(deviceId).listen((s) => current = s);

        Future<void> cycle() async {
          await container.read(connectControllerProvider).connect(deviceId);
          // The seeded broadcast delivers async — let the emission land.
          await Future<void>.delayed(Duration.zero);
          expect(current, CameraConnectionState.connected);
          expect(container.read(sessionSnapshotProvider), isNotNull);

          await container
              .read(reconnectControllerProvider.notifier)
              .manualDisconnect(deviceId);
          await Future<void>.delayed(Duration.zero);
          expect(current, CameraConnectionState.disconnected);
        }

        await cycle();
        await cycle(); // the field-reported failure: 2nd cycle timed out
        await cycle();

        // Three complete handshakes reached the firmware.
        expect(
          platform.firmware.received
              .where((c) => c == 'getSessionSnapshot')
              .length,
          3,
        );
      });
    },
  );

  group('Field regression — wedged reconnect after manual disconnect', () {
    test('handshake-wall timeout on a stuck platform connect: cleanup CANCELS '
        'the attempt and the next retry converges (was: every retry timed '
        'out until app restart)', () async {
      const deviceId = 'AA:BB:CC:00:00:04';
      final svc = BleServiceImpl(disconnectSettle: Duration.zero);
      addTearDown(svc.dispose);
      final container = ProviderContainer(
        overrides: [
          bleServiceProvider.overrideWithValue(svc),
          persistedMatchStoreProvider.overrideWithValue(
            const NoPersistedMatchStore(),
          ),
          // Millisecond wall so the test exercises the exact field sequence:
          // the wall abandons a connect that is still in flight.
          connectControllerProvider.overrideWith(
            (ref) => ConnectController(
              ref,
              handshakeTimeout: const Duration(milliseconds: 500),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(connectControllerProvider);

      // Cycle 1 — clean connect + manual disconnect (the field precondition).
      await controller.connect(deviceId);
      await container
          .read(reconnectControllerProvider.notifier)
          .manualDisconnect(deviceId);
      await Future<void>.delayed(Duration.zero);

      // Cycle 2 — the platform connect never completes (congested radio).
      // The 500 ms wall abandons it; the controller's cleanup disconnect must
      // CANCEL the in-flight attempt (queue:false), not queue behind it.
      platform.stallConnect = true;
      await expectLater(
        controller.connect(deviceId),
        throwsA(isA<BleHandshakeException>()),
      );
      // The cleanup actually reached the platform: nothing left connecting.
      expect(platform.connecting, isEmpty);
      expect(platform.connected, isEmpty);

      // Cycle 3 — radio recovered: the retry must succeed with a FULL
      // handshake (on device this kept failing until the app was killed,
      // because the abandoned attempt still held FBP's global op mutex and
      // the cleanup disconnect was queued behind it).
      platform.stallConnect = false;
      await controller.connect(deviceId);
      expect(container.read(sessionSnapshotProvider), isNotNull);
      expect(
        platform.firmware.received
            .where((c) => c == 'getSessionSnapshot')
            .length,
        2,
        reason: 'cycle 1 and cycle 3 each completed a full handshake',
      );
    });

    test('post-link connect-step failure drops the platform link (no ghost '
        'GATT connection survives a failed handshake)', () async {
      const deviceId = 'AA:BB:CC:00:00:05';
      final svc = BleServiceImpl(disconnectSettle: Duration.zero);
      addTearDown(svc.dispose);

      platform.failNextSetNotify = true;
      await expectLater(
        svc.connect(deviceId),
        throwsA(isA<BleConnectionException>()),
      );
      await Future<void>.delayed(Duration.zero);
      // The failure path must have disconnected the platform side — the old
      // code left the GATT link up with no app-side handle to it (the
      // controller's cleanup disconnect no-oped on the torn-down slot).
      expect(
        platform.connected.contains(DeviceIdentifier(deviceId)),
        isFalse,
        reason: 'failed connect must not leak a live platform link',
      );

      // And a subsequent connect starts clean and handshakes fully.
      await svc.connect(deviceId);
      expect(await svc.getDeviceInfo(deviceId), isNotNull);
      await svc.disconnect(deviceId);
    });
  });

  group('Field regression — GATT 147 on immediate manual reconnect', () {
    // Metal (2026-07-07): the phone-side disconnect callback fires ~1 s
    // before the peripheral processes the LL teardown and re-asserts its
    // advertisement; a reconnect fired into that window died with android
    // error 147 (GATT_CONNECTION_TIMEOUT). The impl now settles the teardown
    // before the next platform connect to the same device.
    test('a reconnect right after a manual disconnect waits out the '
        'disconnect settle; a first connect is not delayed', () async {
      const deviceId = 'AA:BB:CC:00:00:06';
      const settle = Duration(milliseconds: 400);
      final svc = BleServiceImpl(disconnectSettle: settle);
      addTearDown(svc.dispose);

      // First connect on a fresh slot: no teardown observed → no delay.
      var sw = Stopwatch()..start();
      await svc.connect(deviceId);
      expect(
        sw.elapsedMilliseconds,
        lessThan(300),
        reason: 'a first connect must not pay the settle',
      );
      expect(await svc.getDeviceInfo(deviceId), isNotNull);

      await svc.disconnect(deviceId);
      await Future<void>.delayed(Duration.zero);

      // Immediate reconnect: held until the settle window has passed, then
      // handshakes normally.
      sw = Stopwatch()..start();
      await svc.connect(deviceId);
      expect(
        sw.elapsedMilliseconds,
        greaterThanOrEqualTo(350),
        reason: 'the reconnect must wait out the GATT teardown settle',
      );
      expect(await svc.getDeviceInfo(deviceId), isNotNull);
      await svc.disconnect(deviceId);
    });

    test('a reconnect AFTER the settle window pays no extra delay', () async {
      const deviceId = 'AA:BB:CC:00:00:07';
      const settle = Duration(milliseconds: 200);
      final svc = BleServiceImpl(disconnectSettle: settle);
      addTearDown(svc.dispose);

      await svc.connect(deviceId);
      await svc.disconnect(deviceId);
      // The user takes their time — the teardown has long settled.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final sw = Stopwatch()..start();
      await svc.connect(deviceId);
      expect(
        sw.elapsedMilliseconds,
        lessThan(150),
        reason: 'an already-settled teardown must not delay the connect',
      );
      expect(await svc.getDeviceInfo(deviceId), isNotNull);
      await svc.disconnect(deviceId);
    });
  });

  group('address resolution before connect (stale remoteId / GATT 147)', () {
    // Field bug (2026-07-08, real Jetson + phone): the camera's BT address is
    // NOT stable across reboots (Realtek RTL8822CE has no persistent public
    // MAC), so every stored-id path (one-tap banner, auto-reconnect, retry)
    // dialed a dead address blind and the Android stack failed with error 147
    // after its full 30 s wait. connect() must resolve the LIVE address by
    // scanning first.

    test('camera rebooted onto a new address: connect(staleId) rebinds to '
        'the sole advertising sst-cam and completes the handshake', () async {
      const staleId = 'AA:BB:CC:00:00:08'; // persisted before the reboot
      const liveId = 'AA:BB:CC:00:00:09'; // what the camera advertises NOW
      final svc = BleServiceImpl(
        disconnectSettle: Duration.zero,
        resolveRebindGrace: Duration.zero,
      );
      addTearDown(svc.dispose);

      platform.advertised
        ..clear()
        ..add(DeviceIdentifier(liveId));

      // The app-level identity stays the stale id — streams and commands are
      // keyed by it; the rebound address is a transport detail.
      await svc.connect(staleId);
      expect(platform.connected, contains(DeviceIdentifier(liveId)));
      expect(
        await svc.getDeviceInfo(staleId),
        isNotNull,
        reason: 'commands keyed by the requested id must ride the rebound link',
      );
      await svc.disconnect(staleId);
      await Future<void>.delayed(Duration.zero);
      expect(platform.connected, isNot(contains(DeviceIdentifier(liveId))));
    });

    test('camera not advertising at all: connect fails fast with a clear '
        'message instead of the 30 s platform timeout', () async {
      const deviceId = 'AA:BB:CC:00:00:08';
      final svc = BleServiceImpl(
        disconnectSettle: Duration.zero,
        resolveScanBudget: const Duration(milliseconds: 200),
      );
      addTearDown(svc.dispose);

      platform.advertised.clear();

      final sw = Stopwatch()..start();
      await expectLater(
        svc.connect(deviceId),
        throwsA(
          isA<BleConnectionException>().having(
            (e) => e.toString(),
            'message',
            contains('Camera not found'),
          ),
        ),
      );
      expect(
        sw.elapsedMilliseconds,
        lessThan(2000),
        reason: 'the failure must come from the scan budget, not GATT 147',
      );
      expect(platform.connectCalls, 0, reason: 'nothing to dial — no attempt');
    });

    test(
      'several unknown cameras in range: connect refuses to guess',
      () async {
        const staleId = 'AA:BB:CC:00:00:08';
        final svc = BleServiceImpl(
          disconnectSettle: Duration.zero,
          resolveScanBudget: const Duration(milliseconds: 300),
          resolveRebindGrace: Duration.zero,
        );
        addTearDown(svc.dispose);

        platform.advertised
          ..clear()
          ..addAll([
            DeviceIdentifier('AA:BB:CC:00:00:0A'),
            DeviceIdentifier('AA:BB:CC:00:00:0B'),
          ]);

        await expectLater(
          svc.connect(staleId),
          throwsA(
            isA<BleConnectionException>().having(
              (e) => e.toString(),
              'message',
              contains('Discover'),
            ),
          ),
        );
        expect(platform.connectCalls, 0);
      },
    );
  });
}

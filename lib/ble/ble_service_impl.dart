import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/command.dart';
import '../models/device.dart';
import '../models/match.dart';
import '../models/recording.dart';
import '../models/telemetry.dart';
import 'ble_service.dart';

// UUIDs defined in proto/README.md.
//
// When wiring proto encoding, regenerate Dart bindings from
// `proto/bluetooth.proto` (the schema was consolidated from six smaller
// files; see proto/README.md history note).
final _serviceUuid = Guid('A1B2C3D401000000800000805F9B34FB');
final _cmdWriteUuid = Guid('A1B2C3D401100000800000805F9B34FB');
final _cmdResponseUuid = Guid('A1B2C3D401200000800000805F9B34FB');

// Device name prefix — secondary filter after UUID filter
const _kNamePrefix = 'sst-cam-';

class BleServiceImpl implements BleService {
  final _discoveryController = StreamController<List<ScoutDevice>>.broadcast();
  final Map<String, _ConnectedDevice> _connected = {};
  bool _isScanning = false;

  @override
  bool get isScanning => _isScanning;

  @override
  Stream<List<ScoutDevice>> get discoveredDevices =>
      _discoveryController.stream;

  // ---------------------------------------------------------------------------
  // Discovery — filter by advertised service UUID (primary) + name prefix
  // ---------------------------------------------------------------------------

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_isScanning) return;
    _isScanning = true;

    final accumulated = <String, ScoutDevice>{};
    StreamSubscription<List<ScanResult>>? sub;

    sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.toLowerCase();
        if (!name.startsWith(_kNamePrefix)) continue;
        accumulated[r.device.remoteId.str] = ScoutDevice(
          id: r.device.remoteId.str,
          name: r.advertisementData.advName,
          firmwareVersion: '',
          model: '',
          protocolVersion: 0,
        );
      }
      _discoveryController.add(List.unmodifiable(accumulated.values.toList()));
    });

    try {
      // Primary filter: only devices advertising the SST-Cam service UUID.
      // This is set in the BLE advertising payload by the firmware.
      // The name-prefix check above is a secondary safeguard.
      await FlutterBluePlus.startScan(
        withServices: [_serviceUuid],
        timeout: timeout,
      );
    } finally {
      _isScanning = false;
      await sub.cancel();
    }
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _isScanning = false;
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  @override
  Future<void> connect(String deviceId) async {
    final device = BluetoothDevice(remoteId: DeviceIdentifier(deviceId));
    final conn = _ConnectedDevice(device);
    _connected[deviceId] = conn;

    conn._connController.add(CameraConnectionState.connecting);

    try {
      await device.connect(autoConnect: false);
      await device.requestMtu(512);

      final services = await device.discoverServices();
      final svc = services.where((s) => s.uuid == _serviceUuid).firstOrNull;

      if (svc == null) {
        await device.disconnect();
        throw BleConnectionException('SST-Cam service not found on $deviceId');
      }

      conn._cmdWrite = svc.characteristics
          .where((c) => c.uuid == _cmdWriteUuid)
          .firstOrNull;
      conn._cmdResponse = svc.characteristics
          .where((c) => c.uuid == _cmdResponseUuid)
          .firstOrNull;

      if (conn._cmdWrite == null || conn._cmdResponse == null) {
        await device.disconnect();
        throw BleConnectionException(
          'Required characteristics not found on $deviceId',
        );
      }

      await conn._cmdResponse!.setNotifyValue(true);
      conn._startResponseListener();
      conn._connController.add(CameraConnectionState.connected);

      // Listen for unexpected disconnection
      device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          conn._connController.add(CameraConnectionState.disconnected);
          conn.dispose();
          _connected.remove(deviceId);
        }
      });
    } catch (e) {
      conn._connController.add(CameraConnectionState.disconnected);
      _connected.remove(deviceId);
      if (e is BleConnectionException) rethrow;
      throw BleConnectionException('Connect failed: $e');
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final conn = _connected[deviceId];
    if (conn == null) return;
    conn._connController.add(CameraConnectionState.disconnecting);
    await conn.device.disconnect();
    conn._connController.add(CameraConnectionState.disconnected);
    conn.dispose();
    _connected.remove(deviceId);
  }

  @override
  Stream<CameraConnectionState> connectionStateStream(String deviceId) {
    return (_connected[deviceId]?._connController.stream) ??
        Stream.value(CameraConnectionState.disconnected);
  }

  // ---------------------------------------------------------------------------
  // Telemetry — app polls at ~1 Hz; stream exposed to UI
  // ---------------------------------------------------------------------------

  @override
  Stream<DeviceTelemetry> telemetryStream(String deviceId) {
    final conn = _connected[deviceId];
    if (conn == null) return const Stream.empty();
    conn._startTelemetryPolling(
      (cmd) => sendCommand<DeviceTelemetry>(deviceId, cmd),
    );
    return conn._telemetryController.stream;
  }

  // ---------------------------------------------------------------------------
  // Thumbnail — single poll
  // ---------------------------------------------------------------------------

  @override
  Future<ThumbnailResult> requestThumbnail(
    String deviceId, {
    int width = 160,
    int height = 90,
    int quality = 60,
  }) async {
    final resp = await sendCommand<ThumbnailResult>(
      deviceId,
      RequestThumbnailCommand(width: width, height: height, quality: quality),
    );
    if (!resp.isOk || resp.payload == null) {
      throw BleTimeoutException(
        'Thumbnail request failed: ${resp.errorMessage}',
      );
    }
    return resp.payload!;
  }

  // ---------------------------------------------------------------------------
  // Match state — app polls; stream exposed to UI
  // ---------------------------------------------------------------------------

  @override
  Stream<MatchState> matchStateStream(String deviceId) {
    final conn = _connected[deviceId];
    if (conn == null) return const Stream.empty();
    conn._startMatchStatePolling(
      (cmd) => sendCommand<MatchState>(deviceId, cmd),
    );
    return conn._matchStateController.stream;
  }

  // ---------------------------------------------------------------------------
  // Commands — write ChunkedPayload to cmdWrite; await response on cmdResponse
  // TODO: wire to firmware — proto encoding + BLE chunking not yet implemented
  // ---------------------------------------------------------------------------

  @override
  Future<BleCommandResponse<T>> sendCommand<T>(
    String deviceId,
    BleCommand command,
  ) async {
    throw UnimplementedError(
      'TODO: wire to firmware — proto encoding + BLE write not yet implemented',
    );
  }

  // ---------------------------------------------------------------------------
  // Session push (U9)
  // ---------------------------------------------------------------------------

  @override
  Future<void> pushSessionConfig(
    String deviceId,
    PushSessionConfig config,
  ) {
    throw UnimplementedError(
      'TODO: wire to firmware — pushSessionConfig not yet implemented',
    );
  }

  // ---------------------------------------------------------------------------
  // Recordings
  // ---------------------------------------------------------------------------

  @override
  Future<List<RecordingMetadata>> listRecordings(String deviceId) async {
    final resp = await sendCommand<List<RecordingMetadata>>(
      deviceId,
      ListRecordingsCommand(),
    );
    if (!resp.isOk || resp.payload == null) {
      throw BleTimeoutException('listRecordings failed: ${resp.errorMessage}');
    }
    return resp.payload!;
  }

  @override
  Future<DownloadToken> requestDownload(
    String deviceId,
    String recordingId,
  ) async {
    final resp = await sendCommand<DownloadToken>(
      deviceId,
      DownloadRequestCommand(recordingId: recordingId),
    );
    if (!resp.isOk || resp.payload == null) {
      throw BleTimeoutException('requestDownload failed: ${resp.errorMessage}');
    }
    return resp.payload!;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> dispose() async {
    for (final conn in _connected.values) {
      await conn.device.disconnect();
      conn.dispose();
    }
    _connected.clear();
    await _discoveryController.close();
  }
}

// ---------------------------------------------------------------------------
// Per-connection state
// ---------------------------------------------------------------------------

class _ConnectedDevice {
  _ConnectedDevice(this.device);

  final BluetoothDevice device;
  final _connController = StreamController<CameraConnectionState>.broadcast();
  final _telemetryController = StreamController<DeviceTelemetry>.broadcast();
  final _matchStateController = StreamController<MatchState>.broadcast();

  BluetoothCharacteristic? _cmdWrite;
  BluetoothCharacteristic? _cmdResponse;
  StreamSubscription<List<int>>? _responseSub;
  Timer? _telemetryTimer;
  Timer? _matchStateTimer;

  void _startResponseListener() {
    _responseSub = _cmdResponse?.onValueReceived.listen((_) {
      // TODO: wire to firmware — reassemble ChunkedPayload → proto CommandResponse → route
    });
  }

  void _startTelemetryPolling(
    Future<BleCommandResponse<DeviceTelemetry>> Function(BleCommand) send,
  ) {
    _telemetryTimer ??= Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final resp = await send(GetTelemetryCommand());
        if (resp.isOk && resp.payload != null) {
          _telemetryController.add(resp.payload!);
        }
      } catch (_) {}
    });
  }

  void _startMatchStatePolling(
    Future<BleCommandResponse<MatchState>> Function(BleCommand) send,
  ) {
    _matchStateTimer ??= Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final resp = await send(GetMatchStateCommand());
        if (resp.isOk && resp.payload != null) {
          _matchStateController.add(resp.payload!);
        }
      } catch (_) {}
    });
  }

  void dispose() {
    _telemetryTimer?.cancel();
    _matchStateTimer?.cancel();
    _responseSub?.cancel();
    _connController.close();
    _telemetryController.close();
    _matchStateController.close();
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../models/proto/bluetooth.pb.dart' as proto;
import '../models/command.dart';
import '../models/device.dart';
import '../models/match.dart';
import '../models/overlay_layout.dart';
import '../models/recording.dart';
import '../models/telemetry.dart';
import 'ble_protocol.dart';
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
  final _discoveryController = StreamController<List<SstDevice>>.broadcast();
  final Map<String, _ConnectedDevice> _connected = {};
  bool _isScanning = false;

  @override
  bool get isScanning => _isScanning;

  @override
  Stream<List<SstDevice>> get discoveredDevices => _discoveryController.stream;

  // ---------------------------------------------------------------------------
  // Discovery — filter by advertised service UUID (primary) + name prefix
  // ---------------------------------------------------------------------------

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_isScanning) return;
    _isScanning = true;

    final accumulated = <String, SstDevice>{};
    StreamSubscription<List<ScanResult>>? sub;

    sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.toLowerCase();
        if (!name.startsWith(_kNamePrefix)) continue;
        accumulated[r.device.remoteId.str] = SstDevice(
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
  // Commands — encode via BleProtocol → write ChunkedPayload to cmdWrite;
  // await ChunkedPayload response on cmdResponse → decode via BleProtocol.
  // ---------------------------------------------------------------------------

  @override
  Future<BleCommandResponse<T>> sendCommand<T>(
    String deviceId,
    BleCommand command,
  ) async {
    final conn = _connected[deviceId];
    if (conn == null || conn._cmdWrite == null) {
      return BleCommandResponse.error('Device $deviceId not connected');
    }

    final corrId = BleProtocol.newCorrelationId();
    final completer = Completer<List<int>>();
    conn._pendingRequests[corrId] = completer;

    try {
      final frames = BleProtocol.encodeCommandFrames(command, corrId);
      await conn._writeFrames(corrId, frames);

      final responseBytes = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          conn._pendingRequests.remove(corrId);
          throw BleTimeoutException(
            'Command ${command.runtimeType} timed out for $deviceId',
          );
        },
      );

      return BleProtocol.decodeResponse<T>(responseBytes, corrId);
    } on BleTimeoutException {
      return BleCommandResponse<T>.timeout();
    } catch (e) {
      return BleCommandResponse.error('sendCommand failed: $e');
    } finally {
      conn._pendingRequests.remove(corrId);
      conn._cleanupCorrelation(corrId);
    }
  }

  // ---------------------------------------------------------------------------
  // Session push (U9)
  // ---------------------------------------------------------------------------

  @override
  Future<void> pushSessionConfig(
    String deviceId,
    PushSessionConfig config,
  ) async {
    final conn = _connected[deviceId];
    if (conn == null || conn._cmdWrite == null) {
      throw BleConnectionException('Device $deviceId not connected');
    }

    // Fix 14: PushSessionConfig is not a BleCommand and never routes through
    // sendCommand/_toProtoCommand. We reuse the same completer/timeout/
    // correlation-id machinery here, encoding via the dedicated
    // BleProtocol.encodeSessionConfigFrames helper.
    final corrId = BleProtocol.newCorrelationId();
    final completer = Completer<List<int>>();
    conn._pendingRequests[corrId] = completer;

    try {
      final frames = BleProtocol.encodeSessionConfigFrames(config, corrId);
      await conn._writeFrames(corrId, frames);

      final responseBytes = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          conn._pendingRequests.remove(corrId);
          throw BleTimeoutException(
            'pushSessionConfig timed out for $deviceId',
          );
        },
      );

      final resp = BleProtocol.decodeSessionConfigResponse(
        responseBytes,
        corrId,
      );
      if (!resp.isOk) {
        throw BleConnectionException(
          'pushSessionConfig failed: ${resp.errorMessage}',
        );
      }
    } finally {
      conn._pendingRequests.remove(corrId);
      conn._cleanupCorrelation(corrId);
    }
  }

  @override
  Future<void> pushOverlayLayout(String deviceId, OverlayLayout layout) async {
    final resp = await sendCommand<void>(
      deviceId,
      PushOverlayLayoutCommand(layout: layout),
    );
    if (!resp.isOk) {
      throw BleConnectionException(
        'pushOverlayLayout failed: ${resp.errorMessage}',
      );
    }
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
  final _pendingRequests = <String, Completer<List<int>>>{};

  BluetoothCharacteristic? _cmdWrite;
  BluetoothCharacteristic? _cmdResponse;
  StreamSubscription<List<int>>? _responseSub;
  Timer? _telemetryTimer;
  Timer? _matchStateTimer;

  // Inbound response reassembly — index-addressed (NOT arrival-order), one
  // ChunkReassembler per correlation_id. Completes once every index [0, total)
  // is present.
  final _reassemblers = <String, ChunkReassembler>{};

  // Outbound chunk flow-control — completers awaiting an inbound ChunkAck for a
  // given correlation_id + chunk_index (see [_writeFrames]).
  final _pendingAcks = <String, Map<int, Completer<void>>>{};

  /// Writes [frames] (one or more ChunkedPayload frames sharing [corrId]) to the
  /// command-write characteristic. The single-frame fast path writes once and
  /// returns. For multi-frame commands the write loop is ack-gated: after each
  /// frame it awaits the inbound [proto.ChunkAck] for that `chunk_index` before
  /// sending the next, so a missing/late ack stalls (and the caller's overall
  /// timeout fires) rather than racing ahead.
  Future<void> _writeFrames(String corrId, List<Uint8List> frames) async {
    final write = _cmdWrite;
    if (write == null) {
      throw const BleConnectionException('command-write characteristic absent');
    }
    if (frames.length == 1) {
      await write.write(frames.first, withoutResponse: false);
      return;
    }
    for (var i = 0; i < frames.length; i++) {
      final ackCompleter = Completer<void>();
      (_pendingAcks[corrId] ??= {})[i] = ackCompleter;
      await write.write(frames[i], withoutResponse: false);
      try {
        await ackCompleter.future.timeout(const Duration(seconds: 10));
      } finally {
        _pendingAcks[corrId]?.remove(i);
        if (_pendingAcks[corrId]?.isEmpty ?? false) {
          _pendingAcks.remove(corrId);
        }
      }
    }
  }

  /// Clears any reassembly / ack-flow state for [corrId]. Called when a request
  /// completes or times out so buffers do not leak.
  void _cleanupCorrelation(String corrId) {
    _reassemblers.remove(corrId);
    _pendingAcks.remove(corrId);
  }

  void _startResponseListener() {
    _responseSub = _cmdResponse?.onValueReceived.listen((rawBytes) {
      try {
        final chunk = proto.ChunkedPayload.fromBuffer(rawBytes);
        final corrId = chunk.correlationId;
        final total = chunk.totalChunks;

        // Disambiguate an inbound ChunkAck (outbound flow-control) from an
        // inbound ChunkedPayload response. Convention (mirrors firmware):
        // total_chunks == 0 marks an ack frame; a real payload has total >= 1.
        if (total == 0) {
          _pendingAcks[corrId]?.remove(chunk.chunkIndex)?.complete();
          return;
        }

        if (total == 1) {
          // Single-chunk fast path: deliver immediately.
          _pendingRequests.remove(corrId)?.complete(rawBytes);
          return;
        }

        // Multi-chunk: ack this chunk, then place its data at chunk_index
        // (index-addressed — ignores arrival order; duplicates overwrite).
        _sendAck(corrId, chunk.chunkIndex);

        final reassembler = _reassemblers.putIfAbsent(
          corrId,
          ChunkReassembler.new,
        );
        final assembled = reassembler.add(chunk);
        if (assembled != null) {
          // Re-wrap reassembled data in a single ChunkedPayload so
          // decodeResponse() can strip the envelope uniformly.
          final full = proto.ChunkedPayload(
            correlationId: corrId,
            chunkIndex: 0,
            totalChunks: 1,
            data: assembled,
          ).writeToBuffer();
          _reassemblers.remove(corrId);
          _pendingRequests.remove(corrId)?.complete(full);
        }
      } catch (_) {
        // Malformed chunk — silently drop; the pending completer will
        // eventually time out and surface as BleResponseStatus.timeout.
      }
    });
  }

  /// Writes a ChunkAck for ([corrId], [chunkIndex]) back to the camera.
  /// Best-effort — failures are swallowed; the camera's own retransmit/timeout
  /// handling covers a dropped ack.
  void _sendAck(String corrId, int chunkIndex) {
    final write = _cmdWrite;
    if (write == null) return;
    unawaited(
      write
          .write(
            BleProtocol.encodeChunkAck(corrId, chunkIndex),
            withoutResponse: true,
          )
          .catchError((_) {}),
    );
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

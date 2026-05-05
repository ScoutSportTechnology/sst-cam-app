import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../env.dart';
import '../models/command.dart';
import '../models/device.dart';
import '../models/match.dart';
import '../models/recording.dart';
import '../models/sport_preset.dart';
import '../models/streaming.dart';
import '../models/team.dart';
import '../models/telemetry.dart';
import '../models/user.dart';
import 'ble_service.dart';
import 'dev_data_store.dart';

// UUIDs defined in proto/README.md.
//
// When wiring proto encoding (Phase 7), regenerate Dart bindings from
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
  // TODO (Phase 7): implement proto encoding + chunking
  // ---------------------------------------------------------------------------

  @override
  Future<BleCommandResponse<T>> sendCommand<T>(
    String deviceId,
    BleCommand command,
  ) async {
    throw UnimplementedError(
      'Phase 7: proto encoding + BLE write not yet implemented',
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
  // Teams / roster — Phase 7 wires these to proto Command/CommandResponse.
  // ---------------------------------------------------------------------------

  @override
  Future<List<TeamRecord>> listTeams(String deviceId) async {
    throw UnimplementedError('Phase 7: listTeams not yet wired to firmware');
  }

  @override
  Future<List<TeamMatch>> listTeamMatches(
    String deviceId,
    String teamId,
  ) async {
    throw UnimplementedError(
      'Phase 7: listTeamMatches not yet wired to firmware',
    );
  }

  @override
  Future<TeamRecord> createTeam(String deviceId, TeamDraft draft) async {
    throw UnimplementedError('Phase 7: createTeam not yet wired to firmware');
  }

  @override
  Future<TeamRecord> updateTeam(String deviceId, TeamDraft draft) async {
    throw UnimplementedError('Phase 7: updateTeam not yet wired to firmware');
  }

  @override
  Future<void> deleteTeam(String deviceId, String teamId) async {
    throw UnimplementedError('Phase 7: deleteTeam not yet wired to firmware');
  }

  @override
  Future<TeamRecord> setTeamHidden(
    String deviceId,
    String teamId, {
    required bool hidden,
  }) async {
    throw UnimplementedError(
      'Phase 7: setTeamHidden not yet wired to firmware',
    );
  }

  @override
  Future<Player> addPlayer(
    String deviceId,
    String teamId,
    PlayerDraft draft,
  ) async {
    throw UnimplementedError('Phase 7: addPlayer not yet wired to firmware');
  }

  @override
  Future<Player> updatePlayer(
    String deviceId,
    String teamId,
    int currentNumber,
    PlayerDraft draft,
  ) async {
    throw UnimplementedError('Phase 7: updatePlayer not yet wired to firmware');
  }

  @override
  Future<void> removePlayer(String deviceId, String teamId, int number) async {
    throw UnimplementedError('Phase 7: removePlayer not yet wired to firmware');
  }

  @override
  Future<TeamMatch> addTeamMatch(
    String deviceId,
    String teamId,
    TeamMatchDraft draft,
  ) async {
    throw UnimplementedError('Phase 7: addTeamMatch not yet wired to firmware');
  }

  @override
  Future<void> removeTeamMatch(
    String deviceId,
    String teamId,
    String matchId,
  ) async {
    throw UnimplementedError(
      'Phase 7: removeTeamMatch not yet wired to firmware',
    );
  }

  // ---------------------------------------------------------------------------
  // Sport setups (presets) — Phase 7 wires these to proto Command/Response.
  // ---------------------------------------------------------------------------

  @override
  Future<List<SportPreset>> listSportPresets(String deviceId) async {
    throw UnimplementedError(
      'Phase 7: listSportPresets not yet wired to firmware',
    );
  }

  @override
  Future<SportPreset> createSportPreset(
    String deviceId,
    SportPresetDraft draft,
  ) async {
    throw UnimplementedError(
      'Phase 7: createSportPreset not yet wired to firmware',
    );
  }

  @override
  Future<SportPreset> updateSportPreset(
    String deviceId,
    SportPresetDraft draft,
  ) async {
    throw UnimplementedError(
      'Phase 7: updateSportPreset not yet wired to firmware',
    );
  }

  @override
  Future<void> deleteSportPreset(String deviceId, String presetId) async {
    throw UnimplementedError(
      'Phase 7: deleteSportPreset not yet wired to firmware',
    );
  }

  // ---------------------------------------------------------------------------
  // Users (Phase 7 pending). In dev-mock builds, delegated to DevDataStore so
  // the new Settings flows are exercisable. In devDevice / prod builds, the
  // methods throw — firmware integration replaces this gate one method at a
  // time when the proto schema lands.
  // ---------------------------------------------------------------------------

  @override
  Future<List<UserRecord>> listUsers(String deviceId) async {
    if (kAppEnv.isMock) {
      return DevDataStore.instance.listUsers();
    }
    throw StateError('Phase 7: listUsers not yet wired to firmware');
  }

  @override
  Future<UserRecord> createUser(String deviceId, UserDraft draft) async {
    if (kAppEnv.isMock) {
      return DevDataStore.instance.createUser(draft);
    }
    throw StateError('Phase 7: createUser not yet wired to firmware');
  }

  @override
  Future<UserRecord> updateUser(String deviceId, UserDraft draft) async {
    if (kAppEnv.isMock) {
      return DevDataStore.instance.updateUser(draft);
    }
    throw StateError('Phase 7: updateUser not yet wired to firmware');
  }

  @override
  Future<void> deleteUser(String deviceId, String userId) async {
    if (kAppEnv.isMock) {
      DevDataStore.instance.deleteUser(userId);
      return;
    }
    throw StateError('Phase 7: deleteUser not yet wired to firmware');
  }

  @override
  Future<String?> getActiveUser(String deviceId) async {
    if (kAppEnv.isMock) {
      return DevDataStore.instance.getActiveUser();
    }
    throw StateError('Phase 7: getActiveUser not yet wired to firmware');
  }

  @override
  Future<void> setActiveUser(String deviceId, String userId) async {
    if (kAppEnv.isMock) {
      DevDataStore.instance.setActiveUser(userId);
      return;
    }
    throw StateError('Phase 7: setActiveUser not yet wired to firmware');
  }

  // ---------------------------------------------------------------------------
  // Streaming destinations (Phase 7 pending). In dev-mock builds, delegated to
  // DevDataStore so the new Settings flows are exercisable. In devDevice /
  // prod builds, the methods throw — firmware integration replaces this gate
  // one method at a time when the proto schema lands.
  // ---------------------------------------------------------------------------

  @override
  Future<List<StreamingDestination>> listStreamingDestinations(
    String deviceId,
    String userId,
  ) async {
    if (kAppEnv.isMock) {
      return DevDataStore.instance.listStreamingDestinations(userId);
    }
    throw StateError(
      'Phase 7: listStreamingDestinations not yet wired to firmware',
    );
  }

  @override
  Future<StreamingDestination> createStreamingDestination(
    String deviceId,
    String userId,
    StreamingDestinationDraft draft,
  ) async {
    if (kAppEnv.isMock) {
      return DevDataStore.instance.createStreamingDestination(userId, draft);
    }
    throw StateError(
      'Phase 7: createStreamingDestination not yet wired to firmware',
    );
  }

  @override
  Future<StreamingDestination> updateStreamingDestination(
    String deviceId,
    String userId,
    StreamingDestinationDraft draft,
  ) async {
    if (kAppEnv.isMock) {
      return DevDataStore.instance.updateStreamingDestination(userId, draft);
    }
    throw StateError(
      'Phase 7: updateStreamingDestination not yet wired to firmware',
    );
  }

  @override
  Future<void> deleteStreamingDestination(
    String deviceId,
    String userId,
    String destinationId,
  ) async {
    if (kAppEnv.isMock) {
      DevDataStore.instance.deleteStreamingDestination(userId, destinationId);
      return;
    }
    throw StateError(
      'Phase 7: deleteStreamingDestination not yet wired to firmware',
    );
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
      // TODO (Phase 7): reassemble ChunkedPayload → proto CommandResponse → route
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

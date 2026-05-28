import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/command.dart';
import '../../core/models/device.dart';
import '../../core/models/match.dart';
import '../../core/models/recording.dart';
import '../../core/models/telemetry.dart';
import '../../core/ble/ble_service.dart';
import '../../models/proto/bluetooth.pb.dart' as proto;
import '../mock_video_fetcher.dart';

// Minimal 1×1 white JPEG
const _kPlaceholderJpeg = [
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
  0x4A,
  0x46,
  0x49,
  0x46,
  0x00,
  0x01,
  0x01,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0xFF,
  0xDB,
  0x00,
  0x43,
  0x00,
  0x08,
  0x06,
  0x06,
  0x07,
  0x06,
  0x05,
  0x08,
  0x07,
  0x07,
  0x07,
  0x09,
  0x09,
  0x08,
  0x0A,
  0x0C,
  0x14,
  0x0D,
  0x0C,
  0x0B,
  0x0B,
  0x0C,
  0x19,
  0x12,
  0x13,
  0x0F,
  0x14,
  0x1D,
  0x1A,
  0x1F,
  0x1E,
  0x1D,
  0x1A,
  0x1C,
  0x1C,
  0x20,
  0x24,
  0x2E,
  0x27,
  0x20,
  0x22,
  0x2C,
  0x23,
  0x1C,
  0x1C,
  0x28,
  0x37,
  0x29,
  0x2C,
  0x30,
  0x31,
  0x34,
  0x34,
  0x34,
  0x1F,
  0x27,
  0x39,
  0x3D,
  0x38,
  0x32,
  0x3C,
  0x2E,
  0x33,
  0x34,
  0x32,
  0xFF,
  0xC0,
  0x00,
  0x0B,
  0x08,
  0x00,
  0x01,
  0x00,
  0x01,
  0x01,
  0x01,
  0x11,
  0x00,
  0xFF,
  0xC4,
  0x00,
  0x1F,
  0x00,
  0x00,
  0x01,
  0x05,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x01,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x01,
  0x02,
  0x03,
  0x04,
  0x05,
  0x06,
  0x07,
  0x08,
  0x09,
  0x0A,
  0x0B,
  0xFF,
  0xDA,
  0x00,
  0x08,
  0x01,
  0x01,
  0x00,
  0x00,
  0x3F,
  0x00,
  0xFB,
  0x26,
  0xA2,
  0x8A,
  0xFF,
  0xD9,
];

class _DeviceState {
  _DeviceState(this.device)
    : connController = StreamController<CameraConnectionState>.broadcast(
        sync: true,
      ),
      telemetryController = StreamController<DeviceTelemetry>.broadcast(),
      matchStateController = StreamController<MatchState>.broadcast();

  final SstDevice device;
  final StreamController<CameraConnectionState> connController;
  final StreamController<DeviceTelemetry> telemetryController;
  final StreamController<MatchState> matchStateController;

  CameraConnectionState connectionState = CameraConnectionState.disconnected;
  Timer? telemetryTimer;
  int telemetryTick = 0;

  void dispose() {
    telemetryTimer?.cancel();
    connController.close();
    telemetryController.close();
    matchStateController.close();
  }
}

/// Baseline telemetry values loaded from `telemetry.json`. The mock applies
/// its sinusoidal drift and slow storage growth on top of these in code.
class _TelemetryBaseline {
  const _TelemetryBaseline({
    required this.storageTotalBytes,
    required this.storageUsedFraction,
    required this.tempCelsius,
    required this.wifiSsid,
    required this.wifiSignalDbm,
    required this.cpuUsedPct,
    required this.ramUsedPct,
    required this.internetReachable,
    required this.isRecording,
    required this.isStreaming,
  });

  final int storageTotalBytes;
  final double storageUsedFraction;
  final double tempCelsius;
  final String wifiSsid;
  final int wifiSignalDbm;
  final double cpuUsedPct;
  final double ramUsedPct;
  final bool internetReachable;
  final bool isRecording;
  final bool isStreaming;

  static const fallback = _TelemetryBaseline(
    storageTotalBytes: 256 * 1024 * 1024 * 1024,
    storageUsedFraction: 0.35,
    tempCelsius: 48.0,
    wifiSsid: 'StadiumNet-5G',
    wifiSignalDbm: -65,
    cpuUsedPct: 0.30,
    ramUsedPct: 0.45,
    internetReachable: true,
    isRecording: false,
    isStreaming: false,
  );

  factory _TelemetryBaseline.fromJson(Map<String, dynamic> j) =>
      _TelemetryBaseline(
        storageTotalBytes: j['storageTotalBytes'] as int,
        storageUsedFraction: (j['storageUsedFraction'] as num).toDouble(),
        tempCelsius: (j['tempCelsius'] as num).toDouble(),
        wifiSsid: j['wifiSsid'] as String,
        wifiSignalDbm: j['wifiSignalDbm'] as int,
        cpuUsedPct: (j['cpuUsedPct'] as num).toDouble(),
        ramUsedPct: (j['ramUsedPct'] as num).toDouble(),
        internetReachable: j['internetReachable'] as bool,
        isRecording: j['isRecording'] as bool,
        isStreaming: j['isStreaming'] as bool,
      );
}

/// Test double for [BleService]. Simulates realistic device behaviour:
/// progressive discovery, sinusoidal telemetry drift, and configurable
/// failure injection for error-path testing.
class MockBleService implements BleService {
  MockBleService({
    this.advertiseDevices = true,
    this.downloadBaseUrl = 'http://localhost:8080',
    this.scanDeviceAppearDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
    ],
    this.connectionDelay = const Duration(milliseconds: 800),
    this.failureRate = 0.1,
    int? randomSeed,
  }) : _rng = Random(randomSeed);

  /// When false, startScan() emits an empty list and completes without
  /// scheduling any fake devices. Camera emulation is effectively disabled.
  final bool advertiseDevices;

  /// Base URL for the download token's `httpUrl` (`<base>/recordings/<id>`).
  final String downloadBaseUrl;
  final List<Duration> scanDeviceAppearDelays;
  final Duration connectionDelay;

  /// Probability [0.0, 1.0] that connect throws [BleConnectionException].
  final double failureRate;

  final Random _rng;
  final _discoveryController = StreamController<List<SstDevice>>.broadcast();
  final Map<String, _DeviceState> _devices = {};
  bool _isScanning = false;
  Timer? _scanTimer;
  final List<SstDevice> _discovered = [];

  /// In-code device list used only when `devices.json` cannot be loaded
  /// (e.g. unit tests without an asset bundle). Mirrors the fixture contents.
  static const _fallbackDevices = [
    SstDevice(
      id: 'SST-CAM-001',
      name: 'sst-cam-0001',
      firmwareVersion: '0.1.0',
      model: 'Jetson Orin NX',
      protocolVersion: 1,
      batteryPercent: 82,
      rssi: -58,
    ),
    SstDevice(
      id: 'SST-CAM-002',
      name: 'sst-cam-0002',
      firmwareVersion: '0.1.0',
      model: 'Jetson Orin NX',
      protocolVersion: 1,
      batteryPercent: 45,
      rssi: -71,
    ),
  ];

  /// Discoverable cameras, loaded from `devices.json` on first scan/connect.
  /// Starts as the in-code fallback so sync stream accessors always have data.
  List<SstDevice> _deviceCatalog = _fallbackDevices;

  /// Telemetry baseline, loaded from `telemetry.json` lazily. Drift is applied
  /// on top of this in [_makeTelemetry] / [_makeProtoTelemetry].
  _TelemetryBaseline _baseline = _TelemetryBaseline.fallback;

  Future<void>? _catalogLoadFuture;

  /// Loads `devices.json` + `telemetry.json` once; concurrent callers share the
  /// same [Future]. Falls back to the in-code values if the bundle is absent.
  Future<void> _ensureCatalogLoaded() =>
      _catalogLoadFuture ??= _doLoadCatalog();

  Future<void> _doLoadCatalog() async {
    await Future.wait([_loadDevices(), _loadTelemetryBaseline()]);
  }

  Future<void> _loadDevices() async {
    try {
      final rows =
          (await _loadJsonAsset('lib/mock/emulator/fixtures/devices.json')
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();
      _deviceCatalog = rows
          .map(
            (r) => SstDevice(
              id: r['id'] as String,
              name: r['name'] as String,
              firmwareVersion: r['firmwareVersion'] as String,
              model: r['model'] as String,
              protocolVersion: r['protocolVersion'] as int,
              batteryPercent: r['batteryPercent'] as int,
              rssi: r['rssi'] as int,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('MockBleService: devices.json unavailable — $e');
      _deviceCatalog = _fallbackDevices;
    }
  }

  Future<void> _loadTelemetryBaseline() async {
    try {
      final json =
          await _loadJsonAsset('lib/mock/emulator/fixtures/telemetry.json')
              as Map<String, dynamic>;
      _baseline = _TelemetryBaseline.fromJson(json);
    } catch (e) {
      debugPrint('MockBleService: telemetry.json unavailable — $e');
      _baseline = _TelemetryBaseline.fallback;
    }
  }

  /// Loads a JSON asset, stripping whole-line `//` comments (JSON has none).
  Future<dynamic> _loadJsonAsset(String path) async {
    final raw = await rootBundle.loadString(path);
    final stripped = raw
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    return jsonDecode(stripped);
  }

  static final _fallbackRecordings = [
    RecordingMetadata(
      id: 'rec-001',
      durationSeconds: 5400,
      sizeBytes: 4 * 1024 * 1024 * 1024,
      startedAt: DateTime.now().subtract(const Duration(days: 1)),
      sport: 'Soccer',
      teams: 'Reds vs Blues',
    ),
    RecordingMetadata(
      id: 'rec-002',
      durationSeconds: 2700,
      sizeBytes: 2 * 1024 * 1024 * 1024,
      startedAt: DateTime.now().subtract(const Duration(days: 3)),
      sport: 'Soccer',
      teams: 'Eagles vs Lions',
    ),
  ];

  List<RecordingMetadata> _recordings = _fallbackRecordings;
  Future<void>? _loadFuture;

  /// Loads recordings from the fixture JSON on the first call; subsequent
  /// calls share the same [Future] so concurrent callers never double-load.
  /// Falls back to [_fallbackRecordings] if the asset bundle is unavailable
  /// (e.g. in unit tests without widget bindings).
  Future<void> _ensureRecordingsLoaded() => _loadFuture ??= _doLoadRecordings();

  Future<void> _doLoadRecordings() async {
    try {
      final rows =
          (await _loadJsonAsset('lib/mock/emulator/fixtures/recordings.json')
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();
      _recordings = rows
          .map(
            (r) => RecordingMetadata(
              id: r['id'] as String,
              durationSeconds: r['durationSeconds'] as int,
              sizeBytes: r['sizeBytes'] as int,
              startedAt: DateTime.parse(r['startedAt'] as String),
              sport: r['sport'] as String,
              teams: r['teams'] as String,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('MockBleService: recordings.json unavailable — $e');
      _recordings = _fallbackRecordings;
    }
  }

  @override
  bool get isScanning => _isScanning;

  @override
  Stream<List<SstDevice>> get discoveredDevices async* {
    // Emit current snapshot immediately so callers get the initial empty state
    // before any scan has started. Subsequent updates come from the controller.
    yield List.unmodifiable(_discovered);
    yield* _discoveryController.stream;
  }

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_isScanning) return;
    _isScanning = true;
    _discovered.clear();
    _discoveryController.add([]);

    if (!advertiseDevices) {
      _scanTimer = Timer(timeout, stopScan);
      return;
    }

    await _ensureCatalogLoaded();
    if (!_isScanning) return;

    for (var i = 0; i < _deviceCatalog.length; i++) {
      final delay = i < scanDeviceAppearDelays.length
          ? scanDeviceAppearDelays[i]
          : scanDeviceAppearDelays.last;
      Future.delayed(delay, () {
        if (!_isScanning) return;
        _discovered.add(_deviceCatalog[i]);
        _discoveryController.add(List.unmodifiable(_discovered));
      });
    }

    _scanTimer = Timer(timeout, stopScan);
  }

  @override
  Future<void> stopScan() async {
    _isScanning = false;
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  @override
  Future<void> connect(String deviceId) async {
    await _ensureCatalogLoaded();
    final device = _deviceCatalog.where((d) => d.id == deviceId).firstOrNull;
    if (device == null) {
      throw BleConnectionException('Device $deviceId not found');
    }

    _deviceState(
      deviceId,
      device,
    ).connController.add(CameraConnectionState.connecting);

    await Future.delayed(connectionDelay);

    if (_rng.nextDouble() < failureRate) {
      _deviceState(
        deviceId,
        device,
      ).connController.add(CameraConnectionState.disconnected);
      throw BleConnectionException(
        'Simulated connection failure for $deviceId',
      );
    }

    final state = _deviceState(deviceId, device);
    state.connectionState = CameraConnectionState.connected;
    state.connController.add(CameraConnectionState.connected);
    _startTelemetry(deviceId);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final state = _devices[deviceId];
    if (state == null) return;
    state.telemetryTimer?.cancel();
    state.connectionState = CameraConnectionState.disconnected;
    state.connController.add(CameraConnectionState.disconnected);
  }

  @override
  Stream<CameraConnectionState> connectionStateStream(String deviceId) {
    final device =
        _deviceCatalog.where((d) => d.id == deviceId).firstOrNull ??
        _deviceCatalog.first;
    return _deviceState(deviceId, device).connController.stream;
  }

  @override
  Stream<DeviceTelemetry> telemetryStream(String deviceId) {
    final device =
        _deviceCatalog.where((d) => d.id == deviceId).firstOrNull ??
        _deviceCatalog.first;
    return _deviceState(deviceId, device).telemetryController.stream;
  }

  void _startTelemetry(String deviceId) {
    final state = _devices[deviceId];
    if (state == null) return;
    state.telemetryTimer?.cancel();
    state.telemetryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_devices[deviceId]?.connectionState !=
          CameraConnectionState.connected) {
        return;
      }
      final t = state.telemetryTick++;
      state.telemetryController.add(_makeTelemetry(t));
    });
  }

  DeviceTelemetry _makeTelemetry(int tick) {
    final b = _baseline;
    final used =
        (b.storageTotalBytes * b.storageUsedFraction + tick * 1024 * 1024)
            .toInt();
    return DeviceTelemetry(
      storageFreeBytes: b.storageTotalBytes - used,
      storageTotalBytes: b.storageTotalBytes,
      wifiState: WifiState.connected,
      wifiSsid: b.wifiSsid,
      wifiSignalDbm: (b.wifiSignalDbm + (sin(tick * 0.4) * 8)).round(),
      internetReachable: b.internetReachable,
      tempCelsius: b.tempCelsius + sin(tick * 0.1) * 6,
      ramUsedPct: (b.ramUsedPct + sin(tick * 0.2) * 0.1).clamp(0.0, 1.0),
      cpuUsedPct: (b.cpuUsedPct + sin(tick * 0.15) * 0.2).clamp(0.0, 1.0),
      uptimeSeconds: tick,
      isRecording: b.isRecording,
      isStreaming: b.isStreaming,
    );
  }

  @override
  Future<ThumbnailResult> requestThumbnail(
    String deviceId, {
    int width = 160,
    int height = 90,
    int quality = 60,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    return ThumbnailResult(
      jpegBytes: Uint8List.fromList(_kPlaceholderJpeg),
      capturedAt: DateTime.now(),
    );
  }

  static const _uuid = Uuid();

  @override
  Future<BleCommandResponse<T>> sendCommand<T>(
    String deviceId,
    BleCommand command,
  ) async {
    await Future.delayed(const Duration(milliseconds: 80));
    await _ensureCatalogLoaded();
    if (command is ListRecordingsCommand) await _ensureRecordingsLoaded();

    final correlationId = _uuid.v4();

    // --- encode command → proto bytes → decode (round-trip validation) ---
    final protoCmd = _encodeCommand(command, correlationId);
    final cmdChunk = proto.ChunkedPayload(
      correlationId: correlationId,
      chunkIndex: 0,
      totalChunks: 1,
      data: protoCmd.writeToBuffer(),
    );
    // Deserialize back — proves field mappings are correct
    final cmdBytes = cmdChunk.writeToBuffer();
    final decodedChunk = proto.ChunkedPayload.fromBuffer(cmdBytes);
    final _ = proto.Command.fromBuffer(decodedChunk.data);

    // --- build response → encode → decode ---
    final protoResp = _buildResponse(command, correlationId);
    final respChunk = proto.ChunkedPayload(
      correlationId: correlationId,
      chunkIndex: 0,
      totalChunks: 1,
      data: protoResp.writeToBuffer(),
    );
    final respBytes = respChunk.writeToBuffer();
    final decodedRespChunk = proto.ChunkedPayload.fromBuffer(respBytes);
    final decodedResp = proto.CommandResponse.fromBuffer(decodedRespChunk.data);

    if (decodedResp.status != proto.ResponseStatus.OK) {
      return BleCommandResponse.error(decodedResp.errorMessage);
    }

    return _mapResponse<T>(command, decodedResp);
  }

  proto.Command _encodeCommand(BleCommand cmd, String correlationId) =>
      switch (cmd) {
        GetDeviceInfoCommand() => proto.Command(
          correlationId: correlationId,
          getDeviceInfo: proto.GetDeviceInfoCommand(),
        ),
        GetTelemetryCommand() => proto.Command(
          correlationId: correlationId,
          getTelemetry: proto.GetTelemetryCommand(),
        ),
        GetMatchStateCommand() => proto.Command(
          correlationId: correlationId,
          getMatchState: proto.GetMatchStateCommand(),
        ),
        ListRecordingsCommand() => proto.Command(
          correlationId: correlationId,
          listRecordings: proto.ListRecordingsCommand(),
        ),
        DownloadRequestCommand(:final recordingId) => proto.Command(
          correlationId: correlationId,
          downloadRequest: proto.DownloadRequestCommand(
            recordingId: recordingId,
          ),
        ),
        RequestThumbnailCommand(:final width, :final height, :final quality) =>
          proto.Command(
            correlationId: correlationId,
            thumbnail: proto.ThumbnailRequest(
              width: width,
              height: height,
              quality: quality,
            ),
          ),
      };

  proto.CommandResponse _buildResponse(BleCommand cmd, String correlationId) {
    return switch (cmd) {
      GetDeviceInfoCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
        deviceInfo: proto.DeviceInfoResponse(deviceId: 'mock-device-uuid'),
      ),
      GetTelemetryCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
        telemetry: _makeProtoTelemetry(0),
      ),
      GetMatchStateCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
        matchState: proto.MatchState(
          status: proto.MatchStatus.MATCH_NOT_STARTED,
        ),
      ),
      ListRecordingsCommand() => _buildRecordingListResponse(correlationId),
      DownloadRequestCommand(:final recordingId) => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
        downloadToken: proto.DownloadTokenResponse(
          recordingId: recordingId,
          httpUrl: joinBaseUrl(downloadBaseUrl, 'recordings/$recordingId'),
          authToken: 'mock-token-${DateTime.now().millisecondsSinceEpoch}',
          expiresAt: Int64(
            DateTime.now()
                    .add(const Duration(minutes: 15))
                    .millisecondsSinceEpoch ~/
                1000,
          ),
        ),
      ),
      RequestThumbnailCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
        thumbnail: proto.ThumbnailResponse(
          jpegBytes: _kPlaceholderJpeg,
          captureTimestamp: Int64(DateTime.now().millisecondsSinceEpoch),
        ),
      ),
    };
  }

  proto.CommandResponse _buildRecordingListResponse(String correlationId) {
    final protoRecs = _recordings
        .map(
          (r) => proto.RecordingMetadata(
            id: r.id,
            durationS: Int64(r.durationSeconds),
            sizeBytes: Int64(r.sizeBytes),
            startedAt: Int64(r.startedAt.millisecondsSinceEpoch ~/ 1000),
            sport: r.sport,
            teams: r.teams,
          ),
        )
        .toList();
    return proto.CommandResponse(
      correlationId: correlationId,
      status: proto.ResponseStatus.OK,
      recordingList: proto.RecordingListResponse(recordings: protoRecs),
    );
  }

  BleCommandResponse<T> _mapResponse<T>(
    BleCommand cmd,
    proto.CommandResponse resp,
  ) {
    return switch (cmd) {
      GetDeviceInfoCommand() => BleCommandResponse.ok(
        DeviceInfoResponse(deviceId: resp.deviceInfo.deviceId) as T?,
      ),
      GetTelemetryCommand() => BleCommandResponse.ok(
        _dartTelemetry(resp.telemetry) as T?,
      ),
      GetMatchStateCommand() => BleCommandResponse.ok(
        _dartMatchState(resp.matchState) as T?,
      ),
      ListRecordingsCommand() => BleCommandResponse.ok(
        resp.recordingList.recordings
                .map(
                  (r) => RecordingMetadata(
                    id: r.id,
                    durationSeconds: r.durationS.toInt(),
                    sizeBytes: r.sizeBytes.toInt(),
                    startedAt: DateTime.fromMillisecondsSinceEpoch(
                      r.startedAt.toInt() * 1000,
                    ),
                    sport: r.sport,
                    teams: r.teams,
                  ),
                )
                .toList()
            as T?,
      ),
      DownloadRequestCommand() => BleCommandResponse.ok(
        DownloadToken(
              recordingId: resp.downloadToken.recordingId,
              httpUrl: resp.downloadToken.httpUrl,
              authToken: resp.downloadToken.authToken,
              expiresAt: DateTime.fromMillisecondsSinceEpoch(
                resp.downloadToken.expiresAt.toInt() * 1000,
              ),
            )
            as T?,
      ),
      RequestThumbnailCommand() => BleCommandResponse.ok(
        ThumbnailResult(
              jpegBytes: Uint8List.fromList(resp.thumbnail.jpegBytes),
              capturedAt: DateTime.fromMillisecondsSinceEpoch(
                resp.thumbnail.captureTimestamp.toInt(),
              ),
            )
            as T?,
      ),
    };
  }

  proto.DeviceTelemetry _makeProtoTelemetry(int tick) {
    final b = _baseline;
    final usedBytes =
        (b.storageTotalBytes * b.storageUsedFraction + tick * 1024 * 1024)
            .toInt();
    final freeBytes = b.storageTotalBytes - usedBytes;
    return proto.DeviceTelemetry(
      storageFreeBytes: Int64(freeBytes),
      storageTotalBytes: Int64(b.storageTotalBytes),
      wifiState: proto.WifiState.WIFI_CONNECTED,
      wifiSsid: b.wifiSsid,
      wifiSignalDbm: (b.wifiSignalDbm + (sin(tick * 0.4) * 8)).round(),
      internetReachable: b.internetReachable,
      tempCelsius: b.tempCelsius + sin(tick * 0.1) * 6,
      ramUsedPct: (b.ramUsedPct + sin(tick * 0.2) * 0.1).clamp(0.0, 1.0),
      cpuUsedPct: (b.cpuUsedPct + sin(tick * 0.15) * 0.2).clamp(0.0, 1.0),
      uptimeSeconds: Int64(tick),
      isRecording: b.isRecording,
      isStreaming: b.isStreaming,
    );
  }

  DeviceTelemetry _dartTelemetry(proto.DeviceTelemetry p) => DeviceTelemetry(
    storageFreeBytes: p.storageFreeBytes.toInt(),
    storageTotalBytes: p.storageTotalBytes.toInt(),
    wifiState: _dartWifiState(p.wifiState),
    wifiSsid: p.wifiSsid.isEmpty ? null : p.wifiSsid,
    wifiSignalDbm: p.wifiSignalDbm,
    internetReachable: p.internetReachable,
    tempCelsius: p.tempCelsius,
    ramUsedPct: p.ramUsedPct,
    cpuUsedPct: p.cpuUsedPct,
    uptimeSeconds: p.uptimeSeconds.toInt(),
    isRecording: p.isRecording,
    isStreaming: p.isStreaming,
  );

  WifiState _dartWifiState(proto.WifiState s) => switch (s) {
    proto.WifiState.WIFI_DISABLED => WifiState.disabled,
    proto.WifiState.WIFI_DISCONNECTED => WifiState.disconnected,
    proto.WifiState.WIFI_CONNECTED => WifiState.connected,
    _ => WifiState.unknown,
  };

  MatchState _dartMatchState(proto.MatchState s) => MatchState(
    status: switch (s.status) {
      proto.MatchStatus.MATCH_NOT_STARTED => MatchStatus.notStarted,
      proto.MatchStatus.MATCH_ACTIVE => MatchStatus.active,
      proto.MatchStatus.MATCH_PAUSED => MatchStatus.paused,
      proto.MatchStatus.MATCH_HALF_TIME => MatchStatus.halfTime,
      proto.MatchStatus.MATCH_FINISHED => MatchStatus.finished,
      _ => MatchStatus.unknown,
    },
    currentPeriod: s.currentPeriod,
    timeRemainingSeconds: s.timeRemainingS,
    scoreA: s.scoreA,
    scoreB: s.scoreB,
    teamAId: s.teamAId,
    teamBId: s.teamBId,
    updatedAt: s.hasUpdatedAt()
        ? DateTime.fromMillisecondsSinceEpoch(s.updatedAt.toInt() * 1000)
        : DateTime.now(),
  );

  @override
  Stream<MatchState> matchStateStream(String deviceId) {
    final device =
        _deviceCatalog.where((d) => d.id == deviceId).firstOrNull ??
        _deviceCatalog.first;
    return _deviceState(deviceId, device).matchStateController.stream;
  }

  @override
  Future<List<RecordingMetadata>> listRecordings(String deviceId) async {
    await _ensureRecordingsLoaded();
    await Future.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_recordings);
  }

  @override
  Future<DownloadToken> requestDownload(
    String deviceId,
    String recordingId,
  ) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return DownloadToken(
      recordingId: recordingId,
      httpUrl: joinBaseUrl(downloadBaseUrl, 'recordings/$recordingId'),
      authToken: 'mock-token-${DateTime.now().millisecondsSinceEpoch}',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
  }

  // ---------------------------------------------------------------------------
  // Session push (U9)
  // ---------------------------------------------------------------------------

  /// The last config pushed via [pushSessionConfig]. Test code can inspect
  /// this after a "Start match" tap to verify the correct values were sent.
  PushSessionConfig? lastPushedConfig;

  /// Whether [pushSessionConfig] should return an error on the next call.
  /// Reset to false after each call. Useful for error-path tests.
  bool failNextPushSessionConfig = false;

  @override
  Future<void> pushSessionConfig(
    String deviceId,
    PushSessionConfig config,
  ) async {
    await Future.delayed(const Duration(milliseconds: 80));
    if (failNextPushSessionConfig) {
      failNextPushSessionConfig = false;
      throw const BleTimeoutException('Simulated pushSessionConfig failure');
    }
    lastPushedConfig = config;
  }

  @override
  Future<void> dispose() async {
    await stopScan();
    for (final s in _devices.values) {
      s.dispose();
    }
    _devices.clear();
    await _discoveryController.close();
  }

  _DeviceState _deviceState(String id, SstDevice device) {
    return _devices.putIfAbsent(id, () => _DeviceState(device));
  }
}

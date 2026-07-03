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
import '../../core/models/export_job.dart';
import '../../core/models/network_config.dart';
import '../../core/models/overlay_layout.dart';
import '../../core/models/preview_layout.dart';
import '../../core/models/recording.dart';
import '../../core/models/telemetry.dart';
import '../../core/models/video_mode.dart';
import '../../core/models/wifi.dart';
import '../../core/ble/ble_service.dart';
import '../../models/proto/bluetooth.pb.dart' as proto;
import '../mock_video_fetcher.dart';

/// The record/stream modes the mock camera advertises — mirrors the firmware's
/// kSupportedVideoModes so the setup quality pickers exercise a real shape.
/// (1080p60 is deliberately excluded — the Orin Nano's software encoder can't
/// sustain it; see firmware video-quality.hpp.)
const _kMockSupportedModes = <VideoMode>[
  VideoMode(width: 1920, height: 1080, fps: 30),
  VideoMode(width: 1280, height: 720, fps: 60),
  VideoMode(width: 1280, height: 720, fps: 30),
];

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
  Future<DeviceInfoResponse> getDeviceInfo(String deviceId) async =>
      DeviceInfoResponse(
        deviceId: deviceId,
        name: 'SST Cam (mock)',
        firmwareVersion: '0.1.0',
        model: 'v1',
        protocolVersion: kAppProtocolVersion,
        supportedModes: _kMockSupportedModes,
      );

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
      isRawCapturing: isRawCapturingActive,
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

    // Mirror BleProtocol._statusToResponse so the emulated firmware surfaces the
    // same distinct statuses as the real impl — collapsing UNSUPPORTED/TIMEOUT
    // into a generic error here would hide divergence (e.g. raw PAUSE/RESUME,
    // which firmware answers UNSUPPORTED).
    switch (decodedResp.status) {
      case proto.ResponseStatus.OK:
        return _mapResponse<T>(command, decodedResp);
      case proto.ResponseStatus.TIMEOUT:
        return BleCommandResponse<T>.timeout();
      case proto.ResponseStatus.UNSUPPORTED:
        return BleCommandResponse<T>(
          status: BleResponseStatus.unsupported,
          errorMessage: decodedResp.errorMessage.isNotEmpty
              ? decodedResp.errorMessage
              : 'Command not supported by firmware',
        );
      default:
        return BleCommandResponse<T>.error(
          decodedResp.errorMessage.isNotEmpty
              ? decodedResp.errorMessage
              : 'Command failed with status ${decodedResp.status}',
        );
    }
  }

  proto.Command _encodeCommand(
    BleCommand cmd,
    String correlationId,
  ) => switch (cmd) {
    GetDeviceInfoCommand() => proto.Command(
      correlationId: correlationId,
      getDeviceInfo: proto.GetDeviceInfoCommand(),
    ),
    RebootCommand() => proto.Command(
      correlationId: correlationId,
      reboot: proto.RebootCommand(),
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
      downloadRequest: proto.DownloadRequestCommand(recordingId: recordingId),
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
    RecordingControlCommand(:final action, :final captureGroupId) =>
      proto.Command(
        correlationId: correlationId,
        recordingControl: proto.RecordingControlCommand(
          action: switch (action) {
            RecordingControlAction.start =>
              proto.RecordingAction.RECORDING_START,
            RecordingControlAction.stop => proto.RecordingAction.RECORDING_STOP,
            RecordingControlAction.pause =>
              proto.RecordingAction.RECORDING_PAUSE,
            RecordingControlAction.resume =>
              proto.RecordingAction.RECORDING_RESUME,
          },
          // Mirror the real encoder (mock must not drift): the training-proxy
          // pairing key rides the record command.
          captureGroupId: captureGroupId,
        ),
      ),
    RawCaptureControlCommand(:final action, :final captureGroupId) =>
      proto.Command(
        correlationId: correlationId,
        rawCapture: proto.RawCaptureControlCommand(
          action: switch (action) {
            RecordingControlAction.start =>
              proto.RecordingAction.RECORDING_START,
            RecordingControlAction.stop => proto.RecordingAction.RECORDING_STOP,
            RecordingControlAction.pause =>
              proto.RecordingAction.RECORDING_PAUSE,
            RecordingControlAction.resume =>
              proto.RecordingAction.RECORDING_RESUME,
          },
          captureGroupId: captureGroupId,
        ),
      ),
    StreamingControlCommand(:final action, :final rtmpUrl) => proto.Command(
      correlationId: correlationId,
      streamingControl: proto.StreamingControlCommand(
        action: switch (action) {
          StreamingControlAction.start => proto.StreamingAction.STREAMING_START,
          StreamingControlAction.stop => proto.StreamingAction.STREAMING_STOP,
        },
        destination: rtmpUrl ?? '',
      ),
    ),
    MatchControlCommand(:final action, :final period) => proto.Command(
      correlationId: correlationId,
      matchControl: proto.MatchControlCommand(
        action: switch (action) {
          BleMatchControlAction.kickoff =>
            proto.MatchControlAction.MATCH_KICKOFF,
          BleMatchControlAction.periodEnd =>
            proto.MatchControlAction.MATCH_PERIOD_END,
          BleMatchControlAction.periodStart =>
            proto.MatchControlAction.MATCH_PERIOD_START,
          BleMatchControlAction.finalWhistle =>
            proto.MatchControlAction.MATCH_FINAL_WHISTLE,
          BleMatchControlAction.clockPause =>
            proto.MatchControlAction.MATCH_CLOCK_PAUSE,
          BleMatchControlAction.clockResume =>
            proto.MatchControlAction.MATCH_CLOCK_RESUME,
        },
        period: period,
      ),
    ),
    ScoreUpdateCommand(:final teamId, :final delta) => proto.Command(
      correlationId: correlationId,
      scoreUpdate: proto.ScoreUpdateCommand(teamId: teamId, delta: delta),
    ),
    BannerEventCommand(
      :final templateId,
      :final params,
      :final durationSeconds,
      :final playerId,
    ) =>
      proto.Command(
        correlationId: correlationId,
        bannerEvent: proto.BannerEventCommand(
          templateId: templateId,
          params: params,
          durationS: durationSeconds,
          playerId: playerId ?? '',
        ),
      ),
    PushOverlayLayoutCommand(:final layout) => proto.Command(
      correlationId: correlationId,
      pushOverlayLayout: proto.PushOverlayLayoutCommand(
        layout: _dartLayoutToProto(layout),
      ),
    ),
    SetPreviewLayoutCommand(:final layout) => proto.Command(
      correlationId: correlationId,
      setPreviewLayout: proto.SetPreviewLayoutCommand(
        layout: layout == PreviewLayout.sideBySide
            ? proto.PreviewLayout.PREVIEW_LAYOUT_SIDE_BY_SIDE
            : proto.PreviewLayout.PREVIEW_LAYOUT_SINGLE,
      ),
    ),
    ExportOverlayedCommand(:final recordingId) => proto.Command(
      correlationId: correlationId,
      exportOverlayed: proto.ExportOverlayedCommand(recordingId: recordingId),
    ),
    PollExportCommand(:final jobId) => proto.Command(
      correlationId: correlationId,
      pollExport: proto.PollExportCommand(jobId: jobId),
    ),
    StartWifiDirectCommand() => proto.Command(
      correlationId: correlationId,
      startWifiDirect: proto.StartWifiDirectCommand(),
    ),
    StopWifiDirectCommand() => proto.Command(
      correlationId: correlationId,
      stopWifiDirect: proto.StopWifiDirectCommand(),
    ),
    // Uplink config uses the dedicated set/getNetworkConfig methods, not the
    // generic sendCommand round-trip the emulator's encode path serves.
    SetNetworkConfigCommand() ||
    GetNetworkConfigCommand() => throw UnsupportedError(
      'network config uses the direct set/getNetworkConfig path',
    ),
  };

  proto.CommandResponse _buildResponse(BleCommand cmd, String correlationId) {
    // Apply side effects for stateful commands before building the response.
    switch (cmd) {
      case RecordingControlCommand(:final action, :final quality):
        isRecordingActive =
            action == RecordingControlAction.start ||
            action == RecordingControlAction.resume;
        lastRecordingAction = action;
        if (action == RecordingControlAction.start) {
          lastRecordingQuality = quality;
        }
      case RawCaptureControlCommand(:final action, :final captureGroupId):
        isRawCapturingActive = action == RecordingControlAction.start;
        if (action == RecordingControlAction.start) {
          lastRawCaptureGroupId = captureGroupId;
        }
      case StreamingControlCommand(:final action, :final quality):
        isStreamingActive = action == StreamingControlAction.start;
        if (action == StreamingControlAction.start) {
          lastStreamingQuality = quality;
        }
      case MatchControlCommand(:final action):
        lastMatchControlAction = action;
      case BannerEventCommand():
        lastBannerEvent = cmd;
      case PushOverlayLayoutCommand(:final layout):
        lastPushedOverlayLayout = layout;
      case SetPreviewLayoutCommand(:final layout):
        lastPreviewLayout = layout;
      case ExportOverlayedCommand(:final recordingId):
        lastExportRecordingId = recordingId;
      default:
        break;
    }

    return switch (cmd) {
      GetDeviceInfoCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
        deviceInfo: proto.DeviceInfoResponse(
          deviceId: 'mock-device-uuid',
          // Must match the app's expected version or decodeResponse rejects the
          // session as a version skew (see kAppProtocolVersion).
          protocolVersion: kAppProtocolVersion,
          // Mirror the firmware's advertised record/stream modes so the setup
          // quality pickers are exercised against a real contract shape.
          supportedModes: _kMockSupportedModes
              .map(
                (m) => proto.VideoQuality(
                  width: m.width,
                  height: m.height,
                  fps: m.fps,
                ),
              )
              .toList(),
        ),
      ),
      // Mock acks the reboot (obviously without rebooting anything).
      RebootCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
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
      RecordingControlCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
      ),
      RawCaptureControlCommand(:final action) => proto.CommandResponse(
        correlationId: correlationId,
        // Mirror firmware: pause/resume are unsupported for raw capture.
        status:
            (action == RecordingControlAction.pause ||
                action == RecordingControlAction.resume)
            ? proto.ResponseStatus.UNSUPPORTED
            : proto.ResponseStatus.OK,
      ),
      StreamingControlCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
      ),
      MatchControlCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
      ),
      ScoreUpdateCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
      ),
      BannerEventCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
      ),
      PushOverlayLayoutCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
      ),
      SetPreviewLayoutCommand(:final layout) => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
        previewLayout: proto.PreviewLayoutResponse(
          layout: layout == PreviewLayout.sideBySide
              ? proto.PreviewLayout.PREVIEW_LAYOUT_SIDE_BY_SIDE
              : proto.PreviewLayout.PREVIEW_LAYOUT_SINGLE,
          width: layout == PreviewLayout.sideBySide ? 2560 : 1280,
          height: 720,
        ),
      ),
      ExportOverlayedCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
        exportJob: proto.ExportJobResponse(
          jobId: 'export-1',
          state: proto.ExportJobState.EXPORT_JOB_PENDING,
        ),
      ),
      PollExportCommand(:final jobId) => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
        exportJob: proto.ExportJobResponse(
          jobId: jobId,
          state: proto.ExportJobState.EXPORT_JOB_READY,
          token: proto.DownloadTokenResponse(
            recordingId: lastExportRecordingId ?? '',
            httpUrl: joinBaseUrl(
              downloadBaseUrl,
              'recordings/${lastExportRecordingId ?? ''}',
            ),
            authToken: 'mock-export-token',
            expiresAt: Int64(
              DateTime.now()
                      .add(const Duration(minutes: 15))
                      .millisecondsSinceEpoch ~/
                  1000,
            ),
          ),
        ),
      ),
      StartWifiDirectCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
        wifiDirectGroup: proto.WifiDirectGroupResponse(
          ssid: 'DIRECT-mock-sst-cam',
          psk: 'dev-psk',
          groupOwnerIp: '192.168.49.1',
          previewPort: 8554,
          downloadPort: 8080,
          role: 'GO',
        ),
      ),
      StopWifiDirectCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
      ),
      SetNetworkConfigCommand() ||
      GetNetworkConfigCommand() => throw UnsupportedError(
        'network config uses the direct set/getNetworkConfig path',
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

    // Model real firmware: a raw dual-capture session leaves two per-camera
    // files stamped with the app-minted capture_group_id (proto RecordingMetadata
    // 8–10, joint invariant). Surface them so the app's stop() → list → pair →
    // download path exercises the real happy path against the emulated firmware.
    // Without this the mock diverges from firmware and every raw download dead-
    // ends on "incomplete". lastRawCaptureGroupId persists past STOP (set only on
    // START), so the pair stays listed for download.
    final rawGroup = lastRawCaptureGroupId;
    if (rawGroup != null) {
      final startedAt = Int64(DateTime.now().millisecondsSinceEpoch ~/ 1000);
      for (var cam = 0; cam < 2; cam++) {
        protoRecs.add(
          proto.RecordingMetadata(
            id: 'raw__${rawGroup}__cam$cam',
            durationS: Int64(0),
            sizeBytes: Int64(60 * 1024 * 1024),
            startedAt: startedAt,
            sport: '',
            teams: '',
            isRaw: true,
            cameraIndex: cam,
            captureGroupId: rawGroup,
          ),
        );
      }
    }

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
      RebootCommand() => BleCommandResponse.ok(null as T?),
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
                    isRaw: r.isRaw,
                    cameraIndex: r.hasCameraIndex() ? r.cameraIndex : null,
                    captureGroupId: r.hasCaptureGroupId()
                        ? r.captureGroupId
                        : null,
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
      RecordingControlCommand() => BleCommandResponse.ok(null as T?),
      RawCaptureControlCommand() => BleCommandResponse.ok(null as T?),
      StreamingControlCommand() => BleCommandResponse.ok(null as T?),
      MatchControlCommand() => BleCommandResponse.ok(null as T?),
      ScoreUpdateCommand() => BleCommandResponse.ok(null as T?),
      BannerEventCommand() => BleCommandResponse.ok(null as T?),
      PushOverlayLayoutCommand() => BleCommandResponse.ok(null as T?),
      SetPreviewLayoutCommand() => BleCommandResponse.ok(
        PreviewLayoutResult(
              layout:
                  resp.previewLayout.layout ==
                      proto.PreviewLayout.PREVIEW_LAYOUT_SIDE_BY_SIDE
                  ? PreviewLayout.sideBySide
                  : PreviewLayout.single,
              width: resp.previewLayout.width,
              height: resp.previewLayout.height,
            )
            as T?,
      ),
      ExportOverlayedCommand() => BleCommandResponse.ok(
        _dartExportJob(resp.exportJob) as T?,
      ),
      PollExportCommand() => BleCommandResponse.ok(
        _dartExportJob(resp.exportJob) as T?,
      ),
      StartWifiDirectCommand() => BleCommandResponse.ok(
        WifiDirectGroup(
              ssid: resp.wifiDirectGroup.ssid,
              psk: resp.wifiDirectGroup.psk,
              groupOwnerIp: resp.wifiDirectGroup.groupOwnerIp,
              previewPort: resp.wifiDirectGroup.previewPort,
              downloadPort: resp.wifiDirectGroup.downloadPort,
              role: resp.wifiDirectGroup.role,
            )
            as T?,
      ),
      StopWifiDirectCommand() => BleCommandResponse.ok(null as T?),
      SetNetworkConfigCommand() ||
      GetNetworkConfigCommand() => throw UnsupportedError(
        'network config uses the direct set/getNetworkConfig path',
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
      isRawCapturing: isRawCapturingActive,
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
    isRawCapturing: p.isRawCapturing,
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
        ? DateTime.fromMillisecondsSinceEpoch(s.updatedAt.toInt())
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
  // Session config push
  // ---------------------------------------------------------------------------

  /// The last config pushed via [pushSessionConfig]. Test code can inspect
  /// this after a "Start match" tap to verify the correct values were sent.
  PushSessionConfig? lastPushedConfig;

  /// Whether [pushSessionConfig] should return an error on the next call.
  /// Reset to false after each call. Useful for error-path tests.
  bool failNextPushSessionConfig = false;

  // ---------------------------------------------------------------------------
  // Overlay layout push
  // ---------------------------------------------------------------------------

  /// The last layout pushed via [pushOverlayLayout] or via
  /// [sendCommand] with [PushOverlayLayoutCommand].
  OverlayLayout? lastPushedOverlayLayout;

  /// When true the next [pushOverlayLayout] call throws [BleTimeoutException].
  bool failNextPushOverlayLayout = false;

  /// The last layout requested via [setPreviewLayout] (#6 A6b).
  PreviewLayout lastPreviewLayout = PreviewLayout.single;

  /// When true the next [setPreviewLayout] call throws [BleTimeoutException].
  bool failNextSetPreviewLayout = false;

  /// The recording id from the last [requestOverlayExport] (#6 A6c).
  String? lastExportRecordingId;

  /// When true the next [requestOverlayExport] throws (simulates the
  /// LIVE_SESSION_ACTIVE rejection — firmware refuses a burn mid-session).
  bool failNextOverlayExport = false;

  // ---------------------------------------------------------------------------
  // Control command side-effect fields
  // ---------------------------------------------------------------------------

  /// Tracks the last recording action applied via [RecordingControlCommand].
  RecordingControlAction? lastRecordingAction;

  /// Record quality carried on the last recording START (U12); null if none.
  VideoMode? lastRecordingQuality;

  /// Stream quality carried on the last streaming START (U12); null if none.
  VideoMode? lastStreamingQuality;

  /// True when recording is active (toggled by [RecordingControlCommand]).
  bool isRecordingActive = false;

  /// True when raw dual-camera capture is active (toggled by
  /// [RawCaptureControlCommand]); surfaced via telemetry `isRawCapturing`.
  bool isRawCapturingActive = false;

  /// The app-minted capture group id from the last raw-capture start.
  String? lastRawCaptureGroupId;

  /// True when streaming is active (toggled by [StreamingControlCommand]).
  bool isStreamingActive = false;

  /// Tracks the last match control action applied via [MatchControlCommand].
  BleMatchControlAction? lastMatchControlAction;

  /// The last banner event received via [BannerEventCommand].
  BannerEventCommand? lastBannerEvent;

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
  Future<void> pushOverlayLayout(String deviceId, OverlayLayout layout) async {
    await Future.delayed(const Duration(milliseconds: 80));
    if (failNextPushOverlayLayout) {
      failNextPushOverlayLayout = false;
      throw const BleTimeoutException('Simulated pushOverlayLayout failure');
    }
    lastPushedOverlayLayout = layout;
  }

  @override
  Future<PreviewLayoutResult> setPreviewLayout(
    String deviceId,
    PreviewLayout layout,
  ) async {
    await Future.delayed(const Duration(milliseconds: 80));
    if (failNextSetPreviewLayout) {
      failNextSetPreviewLayout = false;
      throw const BleTimeoutException('Simulated setPreviewLayout failure');
    }
    lastPreviewLayout = layout;
    // Emulated geometry: single = one 16:9 sensor (1280×720); side-by-side
    // composites both cams horizontally into one 32:9 frame (2560×720).
    return switch (layout) {
      PreviewLayout.single => const PreviewLayoutResult(
        layout: PreviewLayout.single,
        width: 1280,
        height: 720,
      ),
      PreviewLayout.sideBySide => const PreviewLayoutResult(
        layout: PreviewLayout.sideBySide,
        width: 2560,
        height: 720,
      ),
    };
  }

  @override
  Future<ExportJob> requestOverlayExport(
    String deviceId,
    String recordingId,
  ) async {
    await Future.delayed(const Duration(milliseconds: 80));
    if (failNextOverlayExport) {
      failNextOverlayExport = false;
      throw const BleConnectionException(
        'overlay export request failed: LIVE_SESSION_ACTIVE',
      );
    }
    lastExportRecordingId = recordingId;
    return const ExportJob(jobId: 'export-1', state: ExportJobState.pending);
  }

  @override
  Future<ExportJob> pollOverlayExport(String deviceId, String jobId) async {
    await Future.delayed(const Duration(milliseconds: 80));
    // The emulated firmware can't really burn an L2, so the job is ready on the
    // first poll, with a token that points at the same recording over the mock
    // download server (the overlay would be baked in on real hardware).
    final rid = lastExportRecordingId ?? '';
    return ExportJob(
      jobId: jobId,
      state: ExportJobState.ready,
      token: DownloadToken(
        recordingId: rid,
        httpUrl: joinBaseUrl(downloadBaseUrl, 'recordings/$rid'),
        authToken: 'mock-export-token',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      ),
    );
  }

  NetworkConfig _uplinkConfig = const NetworkConfig();

  @override
  Future<NetworkConfigResult> setNetworkConfig(
    String deviceId,
    NetworkConfig config,
  ) async {
    await Future.delayed(const Duration(milliseconds: 60));
    _uplinkConfig = config;
    return _uplinkStatus(config);
  }

  @override
  Future<NetworkConfigResult> getNetworkConfig(String deviceId) async {
    await Future.delayed(const Duration(milliseconds: 40));
    return _uplinkStatus(_uplinkConfig);
  }

  // Emulated firmware status: ethernet reports "up" with a stock address when
  // enabled; wifi-STA is gated unavailable (single radio = WiFi-Direct GO),
  // matching the real firmware's NmcliUplinkConfigurator.
  NetworkConfigResult _uplinkStatus(NetworkConfig config) =>
      NetworkConfigResult(
        config: config,
        ethernetUp: config.ethernet.enabled,
        ethernetAddress: config.ethernet.enabled
            ? (config.ethernet.ip.dhcp
                  ? '10.10.1.30/24'
                  : config.ethernet.ip.address)
            : '',
        wifiUp: false,
        wifiStatus: config.wifi.enabled
            ? 'unavailable: single radio is dedicated to the WiFi-Direct GO'
            : '',
      );

  // Maps a proto ExportJobResponse to the dart ExportJob (used by the
  // sendCommand round-trip path; the public methods above bypass this).
  ExportJob _dartExportJob(proto.ExportJobResponse job) => ExportJob(
    jobId: job.jobId,
    state: switch (job.state) {
      proto.ExportJobState.EXPORT_JOB_PENDING => ExportJobState.pending,
      proto.ExportJobState.EXPORT_JOB_RUNNING => ExportJobState.running,
      proto.ExportJobState.EXPORT_JOB_READY => ExportJobState.ready,
      proto.ExportJobState.EXPORT_JOB_FAILED => ExportJobState.failed,
      _ => ExportJobState.unknown,
    },
    token: job.hasToken()
        ? DownloadToken(
            recordingId: job.token.recordingId,
            httpUrl: job.token.httpUrl,
            authToken: job.token.authToken,
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              job.token.expiresAt.toInt() * 1000,
            ),
          )
        : null,
  );

  // ---------------------------------------------------------------------------
  // Overlay layout → proto helpers (duplicated from BleProtocol for
  // self-containment; round-trip validated via _encodeCommand/_buildResponse)
  // ---------------------------------------------------------------------------

  proto.OverlayLayout _dartLayoutToProto(OverlayLayout layout) {
    return proto.OverlayLayout(
      canvasWidth: layout.canvasWidth,
      canvasHeight: layout.canvasHeight,
      elements: layout.elements.map(_dartElementToProto).toList(),
      templates: layout.templates
          .map(
            (t) => proto.OverlayTemplate(
              eventType: t.eventType,
              durationMs: t.durationMs,
              elements: t.elements.map(_dartElementToProto).toList(),
            ),
          )
          .toList(),
    );
  }

  proto.OverlayElement _dartElementToProto(OverlayElement el) {
    return proto.OverlayElement(
      id: el.id,
      shape: _dartShapeToProto(el.shape),
      bounds: proto.OverlayRect(
        x1: el.bounds.x1,
        y1: el.bounds.y1,
        z: el.bounds.z,
        x2: el.bounds.x2,
        y2: el.bounds.y2,
      ),
      style: proto.OverlayStyle(
        fillColor: el.style.fillColor ?? '',
        textColor: el.style.textColor ?? '',
        opacity: el.style.opacity,
        cornerRadius: el.style.cornerRadius,
        fontFamily: el.style.fontFamily ?? '',
        fontSize: el.style.fontSize,
        textAlign: _dartTextAlignToProto(el.style.textAlign),
        fontWeight: _dartFontWeightToProto(el.style.fontWeight),
        staticText: el.style.staticText ?? '',
      ),
      binding: _dartBindingToProto(el.binding),
      visible: el.visible,
    );
  }

  proto.OverlayShape _dartShapeToProto(OverlayShape s) => switch (s) {
    OverlayShape.rect => proto.OverlayShape.SHAPE_RECT,
    OverlayShape.text => proto.OverlayShape.SHAPE_TEXT,
    OverlayShape.circle => proto.OverlayShape.SHAPE_CIRCLE,
  };

  proto.OverlayBinding _dartBindingToProto(OverlayBinding b) => switch (b) {
    OverlayBinding.static => proto.OverlayBinding.BINDING_STATIC,
    OverlayBinding.scoreA => proto.OverlayBinding.BINDING_SCORE_A,
    OverlayBinding.scoreB => proto.OverlayBinding.BINDING_SCORE_B,
    OverlayBinding.scoreVs => proto.OverlayBinding.BINDING_SCORE_VS,
    OverlayBinding.teamAName => proto.OverlayBinding.BINDING_TEAM_A_NAME,
    OverlayBinding.teamBName => proto.OverlayBinding.BINDING_TEAM_B_NAME,
    OverlayBinding.matchClock => proto.OverlayBinding.BINDING_MATCH_CLOCK,
    OverlayBinding.periodLabel => proto.OverlayBinding.BINDING_PERIOD_LABEL,
  };

  proto.TextAlign _dartTextAlignToProto(OverlayTextAlign a) => switch (a) {
    OverlayTextAlign.left => proto.TextAlign.TEXT_ALIGN_LEFT,
    OverlayTextAlign.center => proto.TextAlign.TEXT_ALIGN_CENTER,
    OverlayTextAlign.right => proto.TextAlign.TEXT_ALIGN_RIGHT,
  };

  proto.FontWeight _dartFontWeightToProto(OverlayFontWeight w) => switch (w) {
    OverlayFontWeight.normal => proto.FontWeight.FONT_WEIGHT_NORMAL,
    OverlayFontWeight.bold => proto.FontWeight.FONT_WEIGHT_BOLD,
  };

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

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
import '../../core/models/session_snapshot.dart';
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
  Timer? matchStateTimer;
  int telemetryTick = 0;

  void dispose() {
    telemetryTimer?.cancel();
    matchStateTimer?.cancel();
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
    cpuUsedPct: 30, // 0–100 percent, matching the firmware wire contract
    ramUsedPct: 45,
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
/// progressive discovery, sinusoidal telemetry drift, configurable failure
/// injection for error-path testing, and — per the state-health cycle (U7) —
/// full firmware session semantics: sessions survive disconnects with a
/// ticking match clock, the auto-stop safety net, an observable FINALIZING
/// window, camera-failure finalize, boot-orphan reboots, and idempotent
/// StartWifiDirect. Every behaviour mirrors a documented wire contract
/// (proto §9/§9b/§10) or firmware plan unit — see the doc comments on the
/// individual seams.
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
  /// Mutable so tests can flip a healthy camera into an unreachable one
  /// mid-test (U6: "device stays gone" while the reconnect loop runs).
  double failureRate;

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

  bool _bluetoothOn = true;
  final _bluetoothController = StreamController<bool>.broadcast();

  @override
  Stream<bool> get bluetoothOn async* {
    yield _bluetoothOn;
    yield* _bluetoothController.stream;
  }

  /// Test seam: flip the emulated adapter. U6 uses this to prove the
  /// reconnect loop stops on bluetooth-off and stays stopped when the
  /// adapter comes back (re-eligible only on the next unexpected drop).
  @visibleForTesting
  void setBluetoothOn(bool on) {
    _bluetoothOn = on;
    _bluetoothController.add(on);
  }

  @override
  Future<void> requestBluetoothOn() async {}

  @override
  bool get isScanning => _isScanning;

  /// The protocol_version the emulated firmware reports. Defaults to the
  /// app's own version (handshake passes); tests set a different value to
  /// exercise the version-skew refusal path.
  int mockProtocolVersion = kAppProtocolVersion;

  @override
  Future<DeviceInfoResponse> getDeviceInfo(String deviceId) async =>
      DeviceInfoResponse(
        deviceId: deviceId,
        name: 'SST Cam (mock)',
        firmwareVersion: '0.1.0',
        model: 'v1',
        protocolVersion: mockProtocolVersion,
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

    // Firmware parity (firmware plan U1): OnConnect cancels the unsupervised
    // auto-stop timer — a reconnect at timeout−ε deterministically wins over
    // the pending stop, so a supervised session never auto-finalizes.
    _autoStopTimer?.cancel();
    _autoStopTimer = null;

    // Mirror the real service (state-health cycle): connect resolves at
    // `reconciling` — the wire link is up but the §9b handshake has not run.
    // The connect controller drives the handshake commands over sendCommand
    // and then calls [completeHandshake]; telemetry starts only there.
    final state = _deviceState(deviceId, device);
    state.connectionState = CameraConnectionState.reconciling;
    state.connController.add(CameraConnectionState.reconciling);
  }

  @override
  void completeHandshake(String deviceId) {
    final state = _devices[deviceId];
    // Same guard as the real impl: only a device sitting in `reconciling`
    // can complete — a raced disconnect must not resurrect `connected`.
    if (state == null ||
        state.connectionState != CameraConnectionState.reconciling) {
      return;
    }
    state.connectionState = CameraConnectionState.connected;
    state.connController.add(CameraConnectionState.connected);
    // Pollers/telemetry start only after the handshake — parity with the
    // real service, and what keeps a match-state poll from ever landing
    // mid-handshake.
    _startTelemetry(deviceId);
    _startMatchStatePoll(deviceId);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final state = _devices[deviceId];
    if (state == null) return;
    state.telemetryTimer?.cancel();
    state.matchStateTimer?.cancel();
    // Parity with the real impl: an app-initiated disconnect announces
    // itself with `disconnecting` BEFORE `disconnected`. The U6 reconnect
    // loop keys off exactly this — only a bare `connected → disconnected`
    // edge (an unexpected drop, see [simulateUnexpectedDrop]) arms it.
    state.connectionState = CameraConnectionState.disconnecting;
    state.connController.add(CameraConnectionState.disconnecting);
    state.connectionState = CameraConnectionState.disconnected;
    state.connController.add(CameraConnectionState.disconnected);
    // Firmware parity (firmware plan U1): OnDisconnect no longer finalizes or
    // tears down WiFi when a session is active — it arms the auto-stop timer.
    _armAutoStop();
  }

  /// Test seam: the link dies WITHOUT an app-initiated disconnect (camera
  /// power-cut, radio drop) — `disconnected` with no `disconnecting` first.
  /// This is the edge that arms the U6 auto-reconnect loop.
  @visibleForTesting
  void simulateUnexpectedDrop(String deviceId) {
    final state = _devices[deviceId];
    if (state == null) return;
    state.telemetryTimer?.cancel();
    state.matchStateTimer?.cancel();
    state.connectionState = CameraConnectionState.disconnected;
    state.connController.add(CameraConnectionState.disconnected);
    // Same firmware OnDisconnect path as [disconnect]: the session (and its
    // WiFi group) survives; only the auto-stop safety net is armed.
    _armAutoStop();
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

  /// 2 s match-state poll parity (state-health cycle): emits
  /// [snapshotMatchState] while connected — the app's drift-correction
  /// consumer runs against the same cadence as the real service, and each
  /// sample carries the TICKING clock (U7): elapsed advances in real time
  /// exactly like the firmware's LiveMatch loop.
  void _startMatchStatePoll(String deviceId) {
    final state = _devices[deviceId];
    if (state == null) return;
    state.matchStateTimer?.cancel();
    state.matchStateTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_devices[deviceId]?.connectionState !=
          CameraConnectionState.connected) {
        return;
      }
      final ms = snapshotMatchState;
      if (ms != null) state.matchStateController.add(ms);
    });
  }

  /// Test seam: push a match-state sample into the poll stream NOW (as if a
  /// 2 s poll had just returned) without waiting for the timer.
  @visibleForTesting
  void emitMatchState(String deviceId, MatchState ms) {
    final device =
        _deviceCatalog.where((d) => d.id == deviceId).firstOrNull ??
        _deviceCatalog.first;
    _deviceState(deviceId, device).matchStateController.add(ms);
  }

  /// Test seam: push a telemetry sample into the stream NOW.
  @visibleForTesting
  void emitTelemetry(String deviceId, DeviceTelemetry t) {
    final device =
        _deviceCatalog.where((d) => d.id == deviceId).firstOrNull ??
        _deviceCatalog.first;
    _deviceState(deviceId, device).telemetryController.add(t);
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
      ramUsedPct: (b.ramUsedPct + sin(tick * 0.2) * 10).clamp(0.0, 100.0),
      cpuUsedPct: (b.cpuUsedPct + sin(tick * 0.15) * 20).clamp(0.0, 100.0),
      uptimeSeconds: tick,
      // Live activity flags mirror the emulator's actual state (parity with
      // firmware telemetry) — the fixture baseline only sets the floor.
      isRecording: b.isRecording || isRecordingActive,
      isStreaming: b.isStreaming || isStreamingActive,
      isRawCapturing: isRawCapturingActive,
      // Per-camera health rides every telemetry sample (parity with firmware
      // plan U3) — the app's health gate folds this with the snapshot.
      camera0Health: mockCamera0Health,
      camera1Health: mockCamera1Health,
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
    receivedCommands.add(command);
    await Future.delayed(const Duration(milliseconds: 80));
    // Load fixtures only for the commands whose response needs them. An
    // unconditional await here would couple EVERY command (including the
    // connect-handshake ones) to rootBundle asset I/O, which a widget test
    // from an earlier fake-async zone can leave poisoned as a
    // never-completing cached future — the handshake would hang forever.
    if (command is GetTelemetryCommand) await _ensureCatalogLoaded();
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
      case proto.ResponseStatus.DEVICE_INOPERABLE:
        // Typed health-gate refusal — callers key off the status (U3), never
        // the free-form message. Mirrors BleProtocol._statusToResponse.
        return BleCommandResponse<T>.deviceInoperable(
          decodedResp.errorMessage.isNotEmpty
              ? decodedResp.errorMessage
              : 'Camera is not operational',
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
    GetSessionSnapshotCommand() => proto.Command(
      correlationId: correlationId,
      getSessionSnapshot: proto.GetSessionSnapshotCommand(),
    ),
    SetMatchStateCommand(
      :final scoreA,
      :final scoreB,
      :final currentPeriod,
      :final elapsedSeconds,
      :final clockRunning,
      :final status,
    ) =>
      proto.Command(
        correlationId: correlationId,
        // proto3 optional throughout — null fields stay unset (mirror the
        // real encoder: partial absolute set is legal).
        setMatchState: proto.SetMatchStateCommand(
          scoreA: scoreA,
          scoreB: scoreB,
          currentPeriod: currentPeriod,
          elapsedSeconds: elapsedSeconds,
          clockRunning: clockRunning,
          status: status == null ? null : _dartMatchStatusToProto(status),
        ),
      ),
    SetDeviceTimeCommand(:final epochMs) => proto.Command(
      correlationId: correlationId,
      setDeviceTime: proto.SetDeviceTimeCommand(epochMs: Int64(epochMs)),
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
    SetCameraCalibrationCommand(
      :final rGain,
      :final gGain,
      :final bGain,
      :final enabled,
    ) =>
      proto.Command(
        correlationId: correlationId,
        setCameraCalibration: proto.SetCameraCalibrationCommand(
          rGain: rGain,
          gGain: gGain,
          bGain: bGain,
          enabled: enabled,
        ),
      ),
    AutoWhiteBalanceCommand() => proto.Command(
      correlationId: correlationId,
      autoWhiteBalance: proto.AutoWhiteBalanceCommand(),
    ),
    CameraFocusCommand(:final mode, :final position, :final cameraIndex) =>
      proto.Command(
        correlationId: correlationId,
        cameraFocus: proto.CameraFocusControlCommand(
          mode: mode == CameraFocusMode.auto
              ? proto.CameraFocusMode.FOCUS_MODE_AUTO
              : proto.CameraFocusMode.FOCUS_MODE_MANUAL,
          focusPosition: position,
          cameraIndex: cameraIndex,
        ),
      ),
    SetActiveCameraCommand(:final cameraIndex) => proto.Command(
      correlationId: correlationId,
      setActiveCamera: proto.SetActiveCameraCommand(cameraIndex: cameraIndex),
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
    // Health enforcement parity (firmware plan U3): start-class capture
    // commands are refused with DEVICE_INOPERABLE while any camera is DOWN —
    // the wire backstop behind the app-side gate. Stops/pauses, downloads and
    // WiFi commands are never health-gated. Refused BEFORE side effects so a
    // rejected start never flips the mock's activity flags.
    if ((mockCamera0Health == CameraHealth.down ||
            mockCamera1Health == CameraHealth.down) &&
        _isCaptureStart(cmd)) {
      return proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.DEVICE_INOPERABLE,
        errorMessage: 'camera down — capture unavailable',
      );
    }

    // Apply side effects for stateful commands before building the response.
    // Stop-class commands that end the last running activity route through
    // [_finalize] with SESSION_END_APP_STOP — the normal app-commanded stop
    // is one of the firmware's four finalize triggers (fw plan U1), so a
    // subsequent idle snapshot carries a LastSessionSummary exactly like the
    // real peer's.
    final wasSessionActive = _sessionActive;
    switch (cmd) {
      case RecordingControlCommand(:final action, :final quality):
        isRecordingActive =
            action == RecordingControlAction.start ||
            action == RecordingControlAction.resume;
        lastRecordingAction = action;
        if (action == RecordingControlAction.start) {
          lastRecordingQuality = quality;
          // Monotonic elapsed anchor (fw plan U1) + the session now owns a file.
          _recordingStartedAt = nowProvider();
          _sessionHadFile = true;
        }
        if (action == RecordingControlAction.stop) {
          _recordingStartedAt = null;
          if (wasSessionActive && !_sessionActive) {
            _finalize(SessionEndReason.appStop);
          }
        }
      case RawCaptureControlCommand(:final action, :final captureGroupId):
        isRawCapturingActive = action == RecordingControlAction.start;
        if (action == RecordingControlAction.start) {
          lastRawCaptureGroupId = captureGroupId;
          _sessionHadFile = true;
        }
        if (action == RecordingControlAction.stop &&
            wasSessionActive &&
            !_sessionActive) {
          _finalize(SessionEndReason.appStop);
        }
      case StreamingControlCommand(:final action, :final quality):
        isStreamingActive = action == StreamingControlAction.start;
        if (action == StreamingControlAction.start) {
          lastStreamingQuality = quality;
        }
        if (action == StreamingControlAction.stop &&
            wasSessionActive &&
            !_sessionActive) {
          _finalize(SessionEndReason.appStop);
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
      case SetActiveCameraCommand(:final cameraIndex):
        // Session-scoped selection — reported back in the session snapshot
        // (the app adopts it on reconnect instead of force-resetting).
        lastActiveCamera = cameraIndex;
      case SetMatchStateCommand():
        lastSetMatchState = cmd;
        // Absolute overwrite applied to the emulated LiveMatch (fw plan U2):
        // GetMatchState / snapshot / the 2 s poll agree with the push.
        _applySetMatchState(cmd);
      case SetDeviceTimeCommand(:final epochMs):
        lastSetDeviceTimeEpochMs = epochMs;
      case StartWifiDirectCommand():
        // Idempotent (proto §10): forming only when the group is down; a
        // rejoin's redundant Start returns the existing credentials without
        // re-formation — [wifiGroupFormationCount] is the proof.
        if (!mockWifiGroupUp) {
          mockWifiGroupUp = true;
          wifiGroupFormationCount++;
        }
      case StopWifiDirectCommand():
        mockWifiGroupUp = false;
      default:
        break;
    }

    return switch (cmd) {
      GetDeviceInfoCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
        deviceInfo: proto.DeviceInfoResponse(
          deviceId: 'mock-device-uuid',
          // Must match the app's expected version or the connect controller
          // refuses the session as a version skew (see kAppProtocolVersion);
          // tests override [mockProtocolVersion] to exercise the refusal.
          protocolVersion: mockProtocolVersion,
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
        matchState: snapshotMatchState != null
            ? _dartMatchStateToProto(snapshotMatchState!)
            : proto.MatchState(status: proto.MatchStatus.MATCH_NOT_STARTED),
      ),
      GetSessionSnapshotCommand() => _buildSessionSnapshotResponse(
        correlationId,
      ),
      SetMatchStateCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
      ),
      SetDeviceTimeCommand(:final epochMs) => proto.CommandResponse(
        correlationId: correlationId,
        // Mirror firmware: implausible values (pre-2020 epoch) are rejected
        // and the clock is left untouched.
        status: epochMs >= DateTime(2020).millisecondsSinceEpoch
            ? proto.ResponseStatus.OK
            : proto.ResponseStatus.ERROR,
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
      SetCameraCalibrationCommand(
        :final rGain,
        :final gGain,
        :final bGain,
        :final enabled,
      ) =>
        proto.CommandResponse(
          correlationId: correlationId,
          status: proto.ResponseStatus.OK,
          cameraCalibration: proto.CameraCalibrationResponse(
            rGain: rGain,
            gGain: gGain,
            bGain: bGain,
            enabled: enabled,
          ),
        ),
      AutoWhiteBalanceCommand() => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
        // Emulated grey-world result: a plausible magenta-neutralizing gain set.
        cameraCalibration: proto.CameraCalibrationResponse(
          rGain: 0.6,
          gGain: 1.0,
          bGain: 0.62,
          enabled: true,
        ),
      ),
      CameraFocusCommand(:final mode, :final position) => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
        // U9 parity: echo the EFFECTIVE mode (injection knobs emulate a fixed
        // lens or a firmware that applies a different mode than requested).
        cameraFocus: proto.CameraFocusResponse(
          mode: _effectiveFocusMode(mode) == CameraFocusMode.auto
              ? proto.CameraFocusMode.FOCUS_MODE_AUTO
              : proto.CameraFocusMode.FOCUS_MODE_MANUAL,
          focusPosition: position,
          autofocusAvailable: focusAutofocusAvailable,
        ),
      ),
      SetActiveCameraCommand(:final cameraIndex) => proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.OK,
        activeCamera: proto.ActiveCameraResponse(cameraIndex: cameraIndex),
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
      GetSessionSnapshotCommand() => BleCommandResponse.ok(
        _dartSessionSnapshot(resp.sessionSnapshot) as T?,
      ),
      SetMatchStateCommand() => BleCommandResponse.ok(null as T?),
      SetDeviceTimeCommand() => BleCommandResponse.ok(null as T?),
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
      SetCameraCalibrationCommand() => BleCommandResponse.ok(
        CameraCalibrationResult(
              rGain: resp.cameraCalibration.rGain,
              gGain: resp.cameraCalibration.gGain,
              bGain: resp.cameraCalibration.bGain,
              enabled: resp.cameraCalibration.enabled,
            )
            as T?,
      ),
      AutoWhiteBalanceCommand() => BleCommandResponse.ok(
        CameraCalibrationResult(
              rGain: resp.cameraCalibration.rGain,
              gGain: resp.cameraCalibration.gGain,
              bGain: resp.cameraCalibration.bGain,
              enabled: resp.cameraCalibration.enabled,
            )
            as T?,
      ),
      CameraFocusCommand() => BleCommandResponse.ok(
        CameraFocusResult(
              mode:
                  resp.cameraFocus.mode == proto.CameraFocusMode.FOCUS_MODE_AUTO
                  ? CameraFocusMode.auto
                  : CameraFocusMode.manual,
              position: resp.cameraFocus.hasFocusPosition()
                  ? resp.cameraFocus.focusPosition
                  : null,
              autofocusAvailable: resp.cameraFocus.autofocusAvailable,
            )
            as T?,
      ),
      SetActiveCameraCommand() => BleCommandResponse.ok(null as T?),
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
      ramUsedPct: (b.ramUsedPct + sin(tick * 0.2) * 10).clamp(0.0, 100.0),
      cpuUsedPct: (b.cpuUsedPct + sin(tick * 0.15) * 20).clamp(0.0, 100.0),
      uptimeSeconds: Int64(tick),
      // Live activity flags mirror the emulator's actual state, exactly like
      // the dart-side [_makeTelemetry] — firmware sets both wire paths from
      // the same live sources (DeviceTelemetry 11/12/14). A baseline-only
      // value here would report not-recording mid-session (the field-14 class
      // of drift from the mock-parity learning).
      isRecording: b.isRecording || isRecordingActive,
      isStreaming: b.isStreaming || isStreamingActive,
      isRawCapturing: isRawCapturingActive,
      camera0Health: _dartCameraHealthToProto(mockCamera0Health),
      camera1Health: _dartCameraHealthToProto(mockCamera1Health),
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
    camera0Health: p.hasCamera0Health()
        ? _protoCameraHealth(p.camera0Health)
        : null,
    camera1Health: p.hasCamera1Health()
        ? _protoCameraHealth(p.camera1Health)
        : null,
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
    elapsedSeconds: s.hasElapsedSeconds() ? s.elapsedSeconds : null,
    clockRunning: s.hasClockRunning() ? s.clockRunning : null,
    matchUuid: s.hasMatchUuid() ? s.matchUuid : null,
  );

  proto.MatchState _dartMatchStateToProto(MatchState s) => proto.MatchState(
    status: _dartMatchStatusToProto(s.status),
    currentPeriod: s.currentPeriod,
    timeRemainingS: s.timeRemainingSeconds,
    scoreA: s.scoreA,
    scoreB: s.scoreB,
    teamAId: s.teamAId,
    teamBId: s.teamBId,
    updatedAt: Int64(s.updatedAt.millisecondsSinceEpoch),
    // proto3 optional — stay unset when the dart model carries null.
    elapsedSeconds: s.elapsedSeconds,
    clockRunning: s.clockRunning,
    matchUuid: s.matchUuid,
  );

  proto.MatchStatus _dartMatchStatusToProto(MatchStatus s) => switch (s) {
    MatchStatus.notStarted => proto.MatchStatus.MATCH_NOT_STARTED,
    MatchStatus.active => proto.MatchStatus.MATCH_ACTIVE,
    MatchStatus.paused => proto.MatchStatus.MATCH_PAUSED,
    MatchStatus.halfTime => proto.MatchStatus.MATCH_HALF_TIME,
    MatchStatus.finished => proto.MatchStatus.MATCH_FINISHED,
    MatchStatus.unknown => proto.MatchStatus.MATCH_STATUS_UNKNOWN,
  };

  // --- Session-snapshot enum/message conversions (§9b) ---

  proto.SessionPhase _dartSessionPhaseToProto(SessionPhase p) => switch (p) {
    SessionPhase.idle => proto.SessionPhase.SESSION_IDLE,
    SessionPhase.configured => proto.SessionPhase.SESSION_CONFIGURED,
    SessionPhase.ready => proto.SessionPhase.SESSION_READY,
    SessionPhase.recording => proto.SessionPhase.SESSION_RECORDING,
    SessionPhase.finalizing => proto.SessionPhase.SESSION_FINALIZING,
    SessionPhase.unknown => proto.SessionPhase.SESSION_PHASE_UNKNOWN,
  };

  SessionPhase _protoSessionPhase(proto.SessionPhase p) => switch (p) {
    proto.SessionPhase.SESSION_IDLE => SessionPhase.idle,
    proto.SessionPhase.SESSION_CONFIGURED => SessionPhase.configured,
    proto.SessionPhase.SESSION_READY => SessionPhase.ready,
    proto.SessionPhase.SESSION_RECORDING => SessionPhase.recording,
    proto.SessionPhase.SESSION_FINALIZING => SessionPhase.finalizing,
    _ => SessionPhase.unknown,
  };

  proto.CameraHealth _dartCameraHealthToProto(CameraHealth h) => switch (h) {
    CameraHealth.ok => proto.CameraHealth.CAMERA_HEALTH_OK,
    CameraHealth.recovering => proto.CameraHealth.CAMERA_HEALTH_RECOVERING,
    CameraHealth.down => proto.CameraHealth.CAMERA_HEALTH_DOWN,
    CameraHealth.unknown => proto.CameraHealth.CAMERA_HEALTH_UNKNOWN,
  };

  CameraHealth _protoCameraHealth(proto.CameraHealth h) => switch (h) {
    proto.CameraHealth.CAMERA_HEALTH_OK => CameraHealth.ok,
    proto.CameraHealth.CAMERA_HEALTH_RECOVERING => CameraHealth.recovering,
    proto.CameraHealth.CAMERA_HEALTH_DOWN => CameraHealth.down,
    _ => CameraHealth.unknown,
  };

  proto.SessionEndReason _dartEndReasonToProto(SessionEndReason r) =>
      switch (r) {
        SessionEndReason.appStop => proto.SessionEndReason.SESSION_END_APP_STOP,
        SessionEndReason.autoStop =>
          proto.SessionEndReason.SESSION_END_AUTO_STOP,
        SessionEndReason.cameraFailure =>
          proto.SessionEndReason.SESSION_END_CAMERA_FAILURE,
        SessionEndReason.reboot => proto.SessionEndReason.SESSION_END_REBOOT,
        SessionEndReason.unknown => proto.SessionEndReason.SESSION_END_UNKNOWN,
      };

  SessionEndReason _protoEndReason(proto.SessionEndReason r) => switch (r) {
    proto.SessionEndReason.SESSION_END_APP_STOP => SessionEndReason.appStop,
    proto.SessionEndReason.SESSION_END_AUTO_STOP => SessionEndReason.autoStop,
    proto.SessionEndReason.SESSION_END_CAMERA_FAILURE =>
      SessionEndReason.cameraFailure,
    proto.SessionEndReason.SESSION_END_REBOOT => SessionEndReason.reboot,
    _ => SessionEndReason.unknown,
  };

  SessionSnapshot _dartSessionSnapshot(
    proto.SessionSnapshotResponse s,
  ) => SessionSnapshot(
    sessionPhase: _protoSessionPhase(s.sessionPhase),
    activeCameraIndex: s.hasActiveCameraIndex() ? s.activeCameraIndex : null,
    previewLayout: s.hasPreviewLayout()
        ? (s.previewLayout == proto.PreviewLayout.PREVIEW_LAYOUT_SIDE_BY_SIDE
              ? PreviewLayout.sideBySide
              : PreviewLayout.single)
        : null,
    isRecording: s.hasIsRecording() ? s.isRecording : null,
    isStreaming: s.hasIsStreaming() ? s.isStreaming : null,
    isRawCapturing: s.hasIsRawCapturing() ? s.isRawCapturing : null,
    recordingElapsedSeconds: s.hasRecordingElapsedSeconds()
        ? s.recordingElapsedSeconds
        : null,
    matchState: s.hasMatchState() ? _dartMatchState(s.matchState) : null,
    camera0Health: s.hasCamera0Health()
        ? _protoCameraHealth(s.camera0Health)
        : null,
    camera1Health: s.hasCamera1Health()
        ? _protoCameraHealth(s.camera1Health)
        : null,
    lastSession: s.hasLastSession()
        ? LastSessionSummary(
            matchUuid: s.lastSession.matchUuid,
            endReason: _protoEndReason(s.lastSession.endReason),
            endClockSeconds: s.lastSession.hasEndClockSeconds()
                ? s.lastSession.endClockSeconds
                : null,
            fileValid: s.lastSession.hasFileValid()
                ? s.lastSession.fileValid
                : null,
          )
        : null,
    wifiGroupUp: s.hasWifiGroupUp() ? s.wifiGroupUp : null,
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

  /// Every config pushed via [pushSessionConfig], in arrival order — the
  /// session-config counterpart of [receivedCommands] (PushSessionConfig is
  /// not a BleCommand, so it never lands there). Tests assert the U5
  /// mid-session auto-stop re-push off this log.
  final List<PushSessionConfig> pushedConfigs = [];

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
  ({double r, double g, double b, bool enabled})? lastCameraCalibration;

  /// When true the next [setPreviewLayout] call throws [BleTimeoutException].
  bool failNextSetPreviewLayout = false;

  /// The recording id from the last [requestOverlayExport] (#6 A6c).
  String? lastExportRecordingId;

  /// When true the next [requestOverlayExport] throws (simulates the
  /// LIVE_SESSION_ACTIVE rejection — firmware refuses a burn mid-session).
  bool failNextOverlayExport = false;

  // ---------------------------------------------------------------------------
  // Session snapshot / connect handshake (state-health cycle, §9b + U7)
  //
  // U7 parity scope: the emulated firmware carries FULL session semantics —
  // a session survives mock disconnects with a match clock that keeps ticking
  // (proto §9b: "the firmware clock is authority — it is the only clock that
  // ran"), the unsupervised auto-stop timer (compressed timescale via
  // [autoStopMinuteUnit]), an observable FINALIZING window
  // ([finalizeDuration]), the camera-failure finalize hook (firmware plan
  // U3), the boot-orphan path ([simulateReboot], firmware plan U1), and
  // idempotent StartWifiDirect (proto §10). Extend these seams rather than
  // adding a parallel path.
  // ---------------------------------------------------------------------------

  /// Every command received via [sendCommand], in arrival order. Tests assert
  /// handshake ordering ("no time push after a failed protocol gate") and
  /// absence ("no poller command while reconciling") off this log.
  final List<BleCommand> receivedCommands = [];

  /// Overrides the derived session phase (default: finalizing during a
  /// finalize window, recording when a recording is active, configured after
  /// a session-config push, else idle).
  SessionPhase? mockSessionPhase;

  /// Injectable clock seam. Defaults to the real wall clock so mock sessions
  /// advance in real elapsed time (drift-reconciliation tests exercise real
  /// gaps); tests that need deterministic seconds swap in a controlled now.
  DateTime Function() nowProvider = DateTime.now;

  /// Compressed-timescale seam: the length of one firmware "minute" for the
  /// auto-stop timer (proto §9 `auto_stop_minutes`). Production default is a
  /// real minute; tests shrink it so a 30-minute safety net fires in
  /// milliseconds without changing the wire-visible unit.
  Duration autoStopMinuteUnit = const Duration(minutes: 1);

  /// How long the emulated finalize (recording EOS, stream stop, summary
  /// write) takes. FINALIZING is a real observable state (proto §9b
  /// SessionPhase): inject a non-zero window to read a snapshot mid-finalize.
  /// Zero (default) completes synchronously — never a torn intermediate.
  Duration finalizeDuration = Duration.zero;

  /// Number of ACTUAL WiFi-Direct group formations. StartWifiDirect while the
  /// group is already up returns the EXISTING credentials without re-forming
  /// (proto §10: re-formation disrupts CSI/Argus capture and MUST NOT happen
  /// mid-session) — rejoin tests assert this counter stays flat.
  int wifiGroupFormationCount = 0;

  /// The firmware LiveMatch equivalent: base match state as of
  /// [_matchClockAnchor]. Read through [snapshotMatchState] (ticking view).
  MatchState? _liveMatch;
  DateTime? _matchClockAnchor;

  /// When the running recording started ([nowProvider] time base) — drives
  /// the snapshot's monotonic `recording_elapsed_seconds` (proto §9b).
  DateTime? _recordingStartedAt;

  /// Session-config axis (proto SESSION_CONFIGURED). Set by
  /// [pushSessionConfig]; cleared when a finalize or reboot returns the
  /// session to idle. Kept separate from [lastPushedConfig], which is a
  /// test-inspection log and never resets.
  bool _sessionConfigured = false;

  /// Whether the current session wrote a file (recording/raw start seen) —
  /// feeds LastSessionSummary.file_valid on finalize.
  bool _sessionHadFile = false;

  /// Finalize claimed exactly once (firmware plan U1: CAS to `finalizing`
  /// under the session mutex; losers return immediately).
  bool _finalizing = false;
  Timer? _finalizeTimer;
  Timer? _autoStopTimer;
  final Map<int, Timer> _healthScriptTimers = {};

  bool get _sessionActive =>
      isRecordingActive || isRawCapturingActive || isStreamingActive;

  /// The match state reported in the session snapshot, by GetMatchState AND
  /// by the 2 s poll. Null = no session config was ever pushed (snapshot
  /// omits match_state). While `clockRunning == true` the returned
  /// `elapsedSeconds` TICKS in real elapsed time from the moment of the last
  /// set/SetMatchState — including while "disconnected" (§9b: a session
  /// outlives the BLE connection and its clock is the only one that ran).
  MatchState? get snapshotMatchState {
    final m = _liveMatch;
    if (m == null) return null;
    final anchor = _matchClockAnchor;
    final base = m.elapsedSeconds;
    if (m.clockRunning != true || base == null || anchor == null) return m;
    return _withElapsed(m, base + nowProvider().difference(anchor).inSeconds);
  }

  set snapshotMatchState(MatchState? m) {
    _liveMatch = m;
    _matchClockAnchor = m == null ? null : nowProvider();
  }

  static MatchState _withElapsed(MatchState m, int elapsedSeconds) =>
      MatchState(
        status: m.status,
        currentPeriod: m.currentPeriod,
        timeRemainingSeconds: m.timeRemainingSeconds,
        scoreA: m.scoreA,
        scoreB: m.scoreB,
        teamAId: m.teamAId,
        teamBId: m.teamBId,
        updatedAt: m.updatedAt,
        elapsedSeconds: elapsedSeconds,
        clockRunning: m.clockRunning,
        matchUuid: m.matchUuid,
      );

  /// Override for the snapshot's monotonic recording elapsed; when null (the
  /// default) it derives from the recording-start anchor and keeps advancing
  /// across disconnects, like the firmware's monotonic tracking (fw plan U1).
  int? snapshotRecordingElapsedSeconds;

  int? get _recordingElapsedSeconds =>
      snapshotRecordingElapsedSeconds ??
      (isRecordingActive && _recordingStartedAt != null
          ? nowProvider().difference(_recordingStartedAt!).inSeconds
          : null);

  /// Injectable per-camera health. Rides the session snapshot AND every
  /// telemetry sample; while either camera is [CameraHealth.down],
  /// start-class capture commands are refused with DEVICE_INOPERABLE
  /// (firmware parity). Setting DOWN while a recording/raw capture runs
  /// triggers the firmware plan U3 hook: the session finalizes cleanly with
  /// end-reason camera-failure.
  CameraHealth get mockCamera0Health => _camera0Health;
  set mockCamera0Health(CameraHealth h) {
    _camera0Health = h;
    _onCameraHealthChanged();
  }

  CameraHealth get mockCamera1Health => _camera1Health;
  set mockCamera1Health(CameraHealth h) {
    _camera1Health = h;
    _onCameraHealthChanged();
  }

  CameraHealth _camera0Health = CameraHealth.ok;
  CameraHealth _camera1Health = CameraHealth.ok;

  void _onCameraHealthChanged() {
    // Firmware plan U3 session hook: recording + any camera DOWN →
    // hold-then-finalize with end-reason camera failure (the mock skips the
    // watchdog hold window). Streaming-only sessions ride out camera loss.
    if ((_camera0Health == CameraHealth.down ||
            _camera1Health == CameraHealth.down) &&
        (isRecordingActive || isRawCapturingActive)) {
      _finalize(SessionEndReason.cameraFailure);
    }
  }

  /// Scripts camera [cameraIndex] (0/1) through [sequence], one step per
  /// [interval] — the firmware plan U3 transition seam for flap tests
  /// (e.g. RECOVERING → DOWN → OK as the watchdog loses then recovers a
  /// sensor). Each step goes through the health setter, so a scripted DOWN
  /// mid-recording exercises the camera-failure finalize exactly like a
  /// direct injection.
  @visibleForTesting
  void scheduleCameraHealthSequence(
    int cameraIndex,
    List<CameraHealth> sequence, {
    Duration interval = const Duration(milliseconds: 20),
  }) {
    _healthScriptTimers.remove(cameraIndex)?.cancel();
    if (sequence.isEmpty) return;
    var i = 0;
    _healthScriptTimers[cameraIndex] = Timer.periodic(interval, (t) {
      final h = sequence[i++];
      if (cameraIndex == 0) {
        mockCamera0Health = h;
      } else {
        mockCamera1Health = h;
      }
      if (i >= sequence.length) {
        t.cancel();
        _healthScriptTimers.remove(cameraIndex);
      }
    });
  }

  /// Arms the unsupervised auto-stop safety net (proto §9
  /// `auto_stop_minutes`, firmware plan U1): minutes come from the last
  /// pushed session config (absent ⇒ firmware default 30), scaled by
  /// [autoStopMinuteUnit]. Armed only while a session is active — connect
  /// cancels it; firing finalizes with end-reason auto-stop AND tears the
  /// WiFi group down.
  void _armAutoStop() {
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    if (!_sessionActive) return;
    final minutes =
        lastPushedConfig?.autoStopMinutes ?? kDefaultAutoStopMinutes;
    _autoStopTimer = Timer(autoStopMinuteUnit * minutes, () {
      _autoStopTimer = null;
      if (_sessionActive) {
        _finalize(SessionEndReason.autoStop);
      } else {
        // Already stopped by a command race — idempotent, single summary
        // (fw plan U1); only the idle group teardown remains.
        mockWifiGroupUp = false;
      }
    });
  }

  /// The single finalize path (firmware plan U1): claimed exactly once, all
  /// four triggers route here — app stop, auto-stop, camera failure (boot
  /// orphans go through [simulateReboot], which writes the summary directly
  /// because a crashed firmware never ran finalize). Activity stops
  /// immediately (EOS); the phase reports FINALIZING for [finalizeDuration];
  /// completion mints the LastSessionSummary and returns the session to idle.
  void _finalize(SessionEndReason reason) {
    if (_finalizing) return; // CAS parity: losers return immediately
    _finalizing = true;
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    final endClock = snapshotMatchState?.elapsedSeconds;
    final hadFile = _sessionHadFile;
    final matchUuid =
        _liveMatch?.matchUuid ?? lastPushedConfig?.matchUuid ?? '';
    isRecordingActive = false;
    isRawCapturingActive = false;
    isStreamingActive = false;
    _recordingStartedAt = null;
    snapshotRecordingElapsedSeconds = null;
    _freezeMatchClock();
    void complete() {
      _finalizing = false;
      _finalizeTimer = null;
      _sessionConfigured = false;
      _sessionHadFile = false;
      mockLastSessionSummary = LastSessionSummary(
        matchUuid: matchUuid,
        endReason: reason,
        endClockSeconds: endClock,
        // The finalize was clean, so the MP4 is playable (moov written) when
        // the session wrote one; a file-less (streaming-only) session leaves
        // the optional absent. Orphans (file_valid=false) exist only on the
        // reboot path.
        fileValid: hadFile ? true : null,
      );
      // Auto-stop is the unsupervised path: it also tears the group down
      // (fw plan U1). App-commanded stops leave the group to the app.
      if (reason == SessionEndReason.autoStop) mockWifiGroupUp = false;
    }

    if (finalizeDuration == Duration.zero) {
      complete();
    } else {
      _finalizeTimer = Timer(finalizeDuration, complete);
    }
  }

  /// Stops the ticking clock at its current value (finalize freezes the
  /// LiveMatch clock; the summary's end clock was captured just before).
  void _freezeMatchClock() {
    final m = snapshotMatchState;
    if (m == null) return;
    _liveMatch = MatchState(
      status: m.status,
      currentPeriod: m.currentPeriod,
      timeRemainingSeconds: m.timeRemainingSeconds,
      scoreA: m.scoreA,
      scoreB: m.scoreB,
      teamAId: m.teamAId,
      teamBId: m.teamBId,
      updatedAt: m.updatedAt,
      elapsedSeconds: m.elapsedSeconds,
      clockRunning: m.clockRunning == null ? null : false,
      matchUuid: m.matchUuid,
    );
    _matchClockAnchor = nowProvider();
  }

  /// Applies the absolute match-state overwrite (proto §9b SetMatchState):
  /// present fields overwrite, ABSENT FIELDS ARE LEFT UNTOUCHED (partial set
  /// is legal) — so a subsequent GetMatchState/snapshot agrees with what the
  /// app pushed, exactly like the firmware's LiveMatch mutation (fw plan U2).
  /// The base is the ticking view, so an absent elapsed_seconds keeps the
  /// firmware clock running without a jump.
  void _applySetMatchState(SetMatchStateCommand cmd) {
    final base = snapshotMatchState ?? MatchState.idle();
    _liveMatch = MatchState(
      status: cmd.status ?? base.status,
      currentPeriod: cmd.currentPeriod ?? base.currentPeriod,
      timeRemainingSeconds: base.timeRemainingSeconds,
      scoreA: cmd.scoreA ?? base.scoreA,
      scoreB: cmd.scoreB ?? base.scoreB,
      teamAId: base.teamAId,
      teamBId: base.teamBId,
      updatedAt: nowProvider(),
      elapsedSeconds: cmd.elapsedSeconds ?? base.elapsedSeconds,
      clockRunning: cmd.clockRunning ?? base.clockRunning,
      matchUuid: base.matchUuid,
    );
    _matchClockAnchor = nowProvider();
  }

  /// Test seam (firmware plan U1 boot-orphan path): the camera loses power
  /// and reboots. The link dies bare (no `disconnecting` first), ALL
  /// in-memory session state is lost, and — when a recording/raw capture was
  /// orphaned — the boot-time scan records a LastSessionSummary with
  /// SESSION_END_REBOOT and file_valid=false (crash artifact, moov never
  /// written). The next connect's snapshot looks like a first-ever connect
  /// (idle, default selections) plus that summary; a streaming-only session
  /// leaves no orphan and therefore no summary.
  @visibleForTesting
  void simulateReboot(String deviceId) {
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    _finalizeTimer?.cancel();
    _finalizeTimer = null;
    for (final t in _healthScriptTimers.values) {
      t.cancel();
    }
    _healthScriptTimers.clear();
    final orphanedFile = isRecordingActive || isRawCapturingActive;
    mockLastSessionSummary = orphanedFile
        ? LastSessionSummary(
            matchUuid:
                _liveMatch?.matchUuid ?? lastPushedConfig?.matchUuid ?? '',
            endReason: SessionEndReason.reboot,
            fileValid: false,
          )
        : null;
    _finalizing = false;
    isRecordingActive = false;
    isRawCapturingActive = false;
    isStreamingActive = false;
    _recordingStartedAt = null;
    snapshotRecordingElapsedSeconds = null;
    _sessionConfigured = false;
    _sessionHadFile = false;
    _liveMatch = null;
    _matchClockAnchor = null;
    mockSessionPhase = null;
    // Fresh boot: default selections, group down, cameras re-primed OK.
    lastActiveCamera = 0;
    lastPreviewLayout = PreviewLayout.single;
    mockWifiGroupUp = false;
    _camera0Health = CameraHealth.ok;
    _camera1Health = CameraHealth.ok;
    simulateUnexpectedDrop(deviceId);
  }

  /// Whether [cmd] is a start-class capture command — the set the firmware
  /// health-gates (proto: "start-class commands are refused with
  /// DEVICE_INOPERABLE"). Resume counts: it re-opens the capture path.
  static bool _isCaptureStart(BleCommand cmd) => switch (cmd) {
    RecordingControlCommand(:final action) =>
      action == RecordingControlAction.start ||
          action == RecordingControlAction.resume,
    RawCaptureControlCommand(:final action) =>
      action == RecordingControlAction.start,
    StreamingControlCommand(:final action) =>
      action == StreamingControlAction.start,
    _ => false,
  };

  /// How the previous session ended; reported only when the phase is idle.
  LastSessionSummary? mockLastSessionSummary;

  /// Whether the emulated WiFi-Direct group is currently up.
  bool mockWifiGroupUp = false;

  /// When true the next GetSessionSnapshot answers TIMEOUT (handshake-failure
  /// path: the connect controller must fail typed and drop the link).
  bool failNextSessionSnapshot = false;

  /// The last absolute match-state overwrite received (reconcile push).
  SetMatchStateCommand? lastSetMatchState;

  /// The last device wall-clock push received (epoch ms), null before any.
  int? lastSetDeviceTimeEpochMs;

  proto.CommandResponse _buildSessionSnapshotResponse(String correlationId) {
    if (failNextSessionSnapshot) {
      failNextSessionSnapshot = false;
      return proto.CommandResponse(
        correlationId: correlationId,
        status: proto.ResponseStatus.TIMEOUT,
      );
    }
    final phase =
        mockSessionPhase ??
        (_finalizing
            ? SessionPhase.finalizing
            : isRecordingActive
            ? SessionPhase.recording
            : _sessionConfigured
            ? SessionPhase.configured
            : SessionPhase.idle);
    final match = snapshotMatchState;
    final lastSession = mockLastSessionSummary;
    final snapshot = proto.SessionSnapshotResponse(
      sessionPhase: _dartSessionPhaseToProto(phase),
      activeCameraIndex: lastActiveCamera,
      previewLayout: lastPreviewLayout == PreviewLayout.sideBySide
          ? proto.PreviewLayout.PREVIEW_LAYOUT_SIDE_BY_SIDE
          : proto.PreviewLayout.PREVIEW_LAYOUT_SINGLE,
      isRecording: isRecordingActive,
      isStreaming: isStreamingActive,
      isRawCapturing: isRawCapturingActive,
      recordingElapsedSeconds: _recordingElapsedSeconds,
      matchState: match == null ? null : _dartMatchStateToProto(match),
      camera0Health: _dartCameraHealthToProto(mockCamera0Health),
      camera1Health: _dartCameraHealthToProto(mockCamera1Health),
      lastSession: lastSession == null
          ? null
          : proto.LastSessionSummary(
              matchUuid: lastSession.matchUuid,
              endReason: _dartEndReasonToProto(lastSession.endReason),
              endClockSeconds: lastSession.endClockSeconds,
              fileValid: lastSession.fileValid,
            ),
      wifiGroupUp: mockWifiGroupUp,
    );
    return proto.CommandResponse(
      correlationId: correlationId,
      status: proto.ResponseStatus.OK,
      sessionSnapshot: snapshot,
    );
  }

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
    pushedConfigs.add(config);
    // Session-config axis: the snapshot now reports SESSION_CONFIGURED until
    // recording starts or a finalize/reboot returns the session to idle.
    _sessionConfigured = true;
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
  Future<void> setCameraCalibration(
    String deviceId, {
    required double rGain,
    required double gGain,
    required double bGain,
    bool enabled = true,
    double saturation = 1.0,
    double contrast = 1.0,
    double brightness = 0.0,
  }) async {
    await Future.delayed(const Duration(milliseconds: 20));
    lastCameraCalibration = (r: rGain, g: gGain, b: bGain, enabled: enabled);
  }
  // saturation/contrast/brightness are accepted by the interface below; the mock
  // only tracks the WB gains for assertions.

  @override
  Future<CameraCalibrationResult?> autoWhiteBalance(String deviceId) async {
    await Future.delayed(const Duration(milliseconds: 40));
    const result = CameraCalibrationResult(
      rGain: 0.6,
      gGain: 1.0,
      bGain: 0.62,
      enabled: true,
    );
    lastCameraCalibration = (
      r: result.rGain,
      g: result.gGain,
      b: result.bGain,
      enabled: result.enabled,
    );
    return result;
  }

  ({CameraFocusMode mode, int? position, int? cameraIndex})? lastFocus;
  int lastActiveCamera = 0;

  /// U9 AF-echo injection knobs. [focusAutofocusAvailable] false emulates a
  /// fixed lens (no VCM motor): the echo forces MANUAL and flags AF as
  /// unavailable. [focusEffectiveModeOverride] non-null makes the echo report
  /// that mode regardless of the request (firmware policy divergence, e.g. AF
  /// refused while recording).
  bool focusAutofocusAvailable = true;
  CameraFocusMode? focusEffectiveModeOverride;

  /// The EFFECTIVE mode the emulated firmware applies for a [requested] mode —
  /// shared by the wire-path response builder and the direct port method so
  /// both echoes agree.
  CameraFocusMode _effectiveFocusMode(CameraFocusMode requested) =>
      focusEffectiveModeOverride ??
      (focusAutofocusAvailable ? requested : CameraFocusMode.manual);

  @override
  Future<CameraFocusResult?> setCameraFocus(
    String deviceId, {
    required CameraFocusMode mode,
    int? position,
    int? cameraIndex,
  }) async {
    await Future.delayed(const Duration(milliseconds: 20));
    lastFocus = (mode: mode, position: position, cameraIndex: cameraIndex);
    return CameraFocusResult(
      mode: _effectiveFocusMode(mode),
      position: position,
      autofocusAvailable: focusAutofocusAvailable,
    );
  }

  @override
  Future<void> setActiveCamera(String deviceId, int cameraIndex) async {
    await Future.delayed(const Duration(milliseconds: 20));
    lastActiveCamera = cameraIndex;
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
    _autoStopTimer?.cancel();
    _finalizeTimer?.cancel();
    for (final t in _healthScriptTimers.values) {
      t.cancel();
    }
    _healthScriptTimers.clear();
    for (final s in _devices.values) {
      s.dispose();
    }
    _devices.clear();
    await _discoveryController.close();
    await _bluetoothController.close();
  }

  _DeviceState _deviceState(String id, SstDevice device) {
    return _devices.putIfAbsent(id, () => _DeviceState(device));
  }
}

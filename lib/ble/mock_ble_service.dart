import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../models/command.dart';
import '../models/device.dart';
import '../models/match.dart';
import '../models/recording.dart';
import '../models/telemetry.dart';
import 'ble_service.dart';

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
    : connController = StreamController<CameraConnectionState>.broadcast(),
      telemetryController = StreamController<DeviceTelemetry>.broadcast(),
      matchStateController = StreamController<MatchState>.broadcast();

  final ScoutDevice device;
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

/// Test double for [BleService]. Simulates realistic device behaviour:
/// progressive discovery, sinusoidal telemetry drift, and configurable
/// failure injection for error-path testing.
class MockBleService implements BleService {
  MockBleService({
    this.scanDeviceAppearDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
    ],
    this.connectionDelay = const Duration(milliseconds: 800),
    this.failureRate = 0.1,
    int? randomSeed,
  }) : _rng = Random(randomSeed);

  final List<Duration> scanDeviceAppearDelays;
  final Duration connectionDelay;

  /// Probability [0.0, 1.0] that connect throws [BleConnectionException].
  final double failureRate;

  final Random _rng;
  final _discoveryController = StreamController<List<ScoutDevice>>.broadcast();
  final Map<String, _DeviceState> _devices = {};
  bool _isScanning = false;
  Timer? _scanTimer;
  final List<ScoutDevice> _discovered = [];

  static final _fakeDevices = [
    const ScoutDevice(
      id: 'SST-CAM-001',
      name: 'sst-cam-0001',
      firmwareVersion: '0.1.0',
      model: 'Jetson Orin NX',
      protocolVersion: 1,
    ),
    const ScoutDevice(
      id: 'SST-CAM-002',
      name: 'sst-cam-0002',
      firmwareVersion: '0.1.0',
      model: 'Jetson Orin NX',
      protocolVersion: 1,
    ),
  ];

  static final _fakeRecordings = [
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
      sport: 'Basketball',
      teams: 'Eagles vs Lions',
    ),
    RecordingMetadata(
      id: 'rec-003',
      durationSeconds: 900,
      sizeBytes: 800 * 1024 * 1024,
      startedAt: DateTime.now().subtract(const Duration(days: 7)),
      sport: 'Soccer',
      teams: 'City FC vs Rovers',
    ),
  ];

  @override
  bool get isScanning => _isScanning;

  @override
  Stream<List<ScoutDevice>> get discoveredDevices =>
      _discoveryController.stream;

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_isScanning) return;
    _isScanning = true;
    _discovered.clear();
    _discoveryController.add([]);

    for (var i = 0; i < _fakeDevices.length; i++) {
      final delay = i < scanDeviceAppearDelays.length
          ? scanDeviceAppearDelays[i]
          : scanDeviceAppearDelays.last;
      Future.delayed(delay, () {
        if (!_isScanning) return;
        _discovered.add(_fakeDevices[i]);
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
    final device = _fakeDevices.where((d) => d.id == deviceId).firstOrNull;
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
        _fakeDevices.where((d) => d.id == deviceId).firstOrNull ??
        _fakeDevices.first;
    return _deviceState(deviceId, device).connController.stream;
  }

  @override
  Stream<DeviceTelemetry> telemetryStream(String deviceId) {
    final device =
        _fakeDevices.where((d) => d.id == deviceId).firstOrNull ??
        _fakeDevices.first;
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
    const totalBytes = 256 * 1024 * 1024 * 1024;
    final used = (totalBytes * 0.35 + tick * 1024 * 1024).toInt();
    return DeviceTelemetry(
      storageFreeBytes: totalBytes - used,
      storageTotalBytes: totalBytes,
      wifiState: WifiState.connected,
      wifiSsid: 'StadiumNet-5G',
      wifiSignalDbm: (-65 + (sin(tick * 0.4) * 8)).round(),
      internetReachable: true,
      tempCelsius: 48.0 + sin(tick * 0.1) * 6,
      ramUsedPct: (0.45 + sin(tick * 0.2) * 0.1).clamp(0.0, 1.0),
      cpuUsedPct: (0.30 + sin(tick * 0.15) * 0.2).clamp(0.0, 1.0),
      uptimeSeconds: tick,
      isRecording: false,
      isStreaming: false,
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

  @override
  Future<BleCommandResponse<T>> sendCommand<T>(
    String deviceId,
    BleCommand command,
  ) async {
    await Future.delayed(const Duration(milliseconds: 80));

    return switch (command) {
      GetTelemetryCommand() => BleCommandResponse.ok(_makeTelemetry(0) as T?),
      GetMatchStateCommand() => BleCommandResponse.ok(MatchState.idle() as T?),
      ListRecordingsCommand() => BleCommandResponse.ok(_fakeRecordings as T?),
      DownloadRequestCommand(:final recordingId) => BleCommandResponse.ok(
        DownloadToken(
              recordingId: recordingId,
              httpUrl: 'http://192.168.1.42:8080/recordings/$recordingId.mp4',
              authToken: 'mock-token-${DateTime.now().millisecondsSinceEpoch}',
              expiresAt: DateTime.now().add(const Duration(minutes: 15)),
            )
            as T?,
      ),
      _ => BleCommandResponse.ok(),
    };
  }

  @override
  Stream<MatchState> matchStateStream(String deviceId) {
    final device =
        _fakeDevices.where((d) => d.id == deviceId).firstOrNull ??
        _fakeDevices.first;
    return _deviceState(deviceId, device).matchStateController.stream;
  }

  @override
  Future<List<RecordingMetadata>> listRecordings(String deviceId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(_fakeRecordings);
  }

  @override
  Future<DownloadToken> requestDownload(
    String deviceId,
    String recordingId,
  ) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return DownloadToken(
      recordingId: recordingId,
      httpUrl: 'http://192.168.1.42:8080/recordings/$recordingId.mp4',
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
  Future<BleCommandResponse<void>> pushSessionConfig(
    String deviceId,
    PushSessionConfig config,
  ) async {
    await Future.delayed(const Duration(milliseconds: 80));
    if (failNextPushSessionConfig) {
      failNextPushSessionConfig = false;
      return BleCommandResponse.error('Simulated pushSessionConfig failure');
    }
    lastPushedConfig = config;
    return BleCommandResponse.ok();
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

  _DeviceState _deviceState(String id, ScoutDevice device) {
    return _devices.putIfAbsent(id, () => _DeviceState(device));
  }
}

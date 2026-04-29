import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../models/command.dart';
import '../models/device.dart';
import '../models/match.dart';
import '../models/recording.dart';
import '../models/team.dart';
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
///
/// Uses `package:scout_camera` imports so it exercises the same contracts
/// as the production [BleServiceImpl].
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

  // ---------------------------------------------------------------------------
  // Team store — process-global so the wireframe persists across hot reloads
  // and "preview" (no active connection) deviceIds. The contract still passes
  // deviceId; in a real firmware impl each camera would own a separate store.
  // ---------------------------------------------------------------------------
  static const _seedRoster = <Player>[
    Player(number: 7, name: 'A. Patel', position: 'Forward', captain: true),
    Player(number: 10, name: 'B. Okafor', position: 'Mid'),
    Player(number: 4, name: 'C. Nguyen', position: 'Defender'),
    Player(number: 1, name: 'D. Reyes', position: 'Keeper'),
    Player(number: 11, name: 'E. Mahmoud', position: 'Forward'),
    Player(number: 8, name: 'F. Lopez', position: 'Mid'),
    Player(number: 5, name: 'G. Singh', position: 'Defender'),
  ];

  static final List<TeamRecord> _teams = [
    const TeamRecord(
      id: 'nr-u14',
      name: 'Northside Rovers U14',
      shortName: 'NR U14',
      initials: 'NR',
      sport: 'Soccer',
      roster: _seedRoster,
      played: 6,
      wins: 3,
      draws: 1,
      losses: 2,
      goalsFor: 13,
      goalsAgainst: 9,
      cleanSheets: 2,
      cards: 7,
      lastMatchDate: 'Mar 12',
    ),
    const TeamRecord(
      id: 'nr-u12',
      name: 'Northside Rovers U12',
      shortName: 'NR U12',
      initials: 'NR',
      sport: 'Soccer',
      roster: [],
      played: 4,
      wins: 2,
      draws: 1,
      losses: 1,
      goalsFor: 8,
      goalsAgainst: 6,
      cleanSheets: 1,
      cards: 3,
      lastMatchDate: 'Mar 09',
    ),
    const TeamRecord(
      id: 'efc-r',
      name: 'Eastfield FC Reserves',
      shortName: 'EFC R',
      initials: 'EF',
      sport: 'Soccer',
      roster: [],
      played: 5,
      wins: 1,
      draws: 1,
      losses: 3,
      goalsFor: 6,
      goalsAgainst: 11,
      cleanSheets: 0,
      cards: 8,
      lastMatchDate: 'Feb 28',
    ),
    const TeamRecord(
      id: 'rd-utd',
      name: 'Riverdale United',
      shortName: 'RD Utd',
      initials: 'RU',
      sport: 'Soccer',
      roster: [],
      played: 3,
      wins: 2,
      draws: 0,
      losses: 1,
      goalsFor: 7,
      goalsAgainst: 4,
      cleanSheets: 1,
      cards: 2,
      lastMatchDate: 'Feb 14',
    ),
  ];

  static final Map<String, List<TeamMatch>> _teamMatches = {
    'nr-u14': const [
      TeamMatch(
        id: 'nr-u14-m1',
        opponent: 'vs Eastfield FC',
        date: 'Mar 12',
        result: 'W 3–1',
        clips: 2,
        sizeMb: 380,
      ),
      TeamMatch(
        id: 'nr-u14-m2',
        opponent: 'vs Riverdale Utd',
        date: 'Mar 05',
        result: 'L 0–2',
        clips: 2,
        sizeMb: 180,
      ),
      TeamMatch(
        id: 'nr-u14-m3',
        opponent: 'vs Lakeside',
        date: 'Feb 26',
        result: 'D 1–1',
        clips: 2,
        sizeMb: 540,
      ),
      TeamMatch(
        id: 'nr-u14-m4',
        opponent: 'vs Brookfield',
        date: 'Feb 19',
        result: 'W 2–0',
        clips: 2,
        sizeMb: 220,
      ),
      TeamMatch(
        id: 'nr-u14-m5',
        opponent: 'vs Hillcrest',
        date: 'Feb 12',
        result: 'L 1–3',
        clips: 2,
        sizeMb: 410,
      ),
      TeamMatch(
        id: 'nr-u14-m6',
        opponent: 'vs Glenview',
        date: 'Feb 05',
        result: 'W 4–2',
        clips: 2,
        sizeMb: 620,
      ),
    ],
  };

  int _teamIdCounter = 0;

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
  // Teams / roster — in-memory store, deviceId-agnostic in the mock.
  // ---------------------------------------------------------------------------

  @override
  Future<List<TeamRecord>> listTeams(String deviceId) async {
    await Future.delayed(const Duration(milliseconds: 80));
    return List.unmodifiable(_teams);
  }

  @override
  Future<List<TeamMatch>> listTeamMatches(
    String deviceId,
    String teamId,
  ) async {
    await Future.delayed(const Duration(milliseconds: 80));
    return List.unmodifiable(_teamMatches[teamId] ?? const []);
  }

  @override
  Future<TeamRecord> createTeam(String deviceId, TeamDraft draft) async {
    await Future.delayed(const Duration(milliseconds: 120));
    final id =
        'team-${++_teamIdCounter}-${DateTime.now().millisecondsSinceEpoch}';
    final record = TeamRecord(
      id: id,
      name: draft.name,
      shortName: draft.shortName,
      initials: draft.initials,
      sport: draft.sport,
      roster: const [],
      played: 0,
      wins: 0,
      draws: 0,
      losses: 0,
      goalsFor: 0,
      goalsAgainst: 0,
      cleanSheets: 0,
      cards: 0,
      lastMatchDate: '—',
    );
    _teams.add(record);
    return record;
  }

  @override
  Future<TeamRecord> updateTeam(String deviceId, TeamDraft draft) async {
    await Future.delayed(const Duration(milliseconds: 100));
    final i = _teams.indexWhere((t) => t.id == draft.id);
    if (i == -1) throw StateError('Team ${draft.id} not found');
    final updated = _teams[i].copyWith(
      name: draft.name,
      shortName: draft.shortName,
      initials: draft.initials,
      sport: draft.sport,
    );
    _teams[i] = updated;
    return updated;
  }

  @override
  Future<void> deleteTeam(String deviceId, String teamId) async {
    await Future.delayed(const Duration(milliseconds: 100));
    _teams.removeWhere((t) => t.id == teamId);
    _teamMatches.remove(teamId);
  }

  @override
  Future<TeamRecord> setTeamHidden(
    String deviceId,
    String teamId, {
    required bool hidden,
  }) async {
    await Future.delayed(const Duration(milliseconds: 80));
    final i = _teams.indexWhere((t) => t.id == teamId);
    if (i == -1) throw StateError('Team $teamId not found');
    final updated = _teams[i].copyWith(hidden: hidden);
    _teams[i] = updated;
    return updated;
  }

  @override
  Future<Player> addPlayer(
    String deviceId,
    String teamId,
    PlayerDraft draft,
  ) async {
    await Future.delayed(const Duration(milliseconds: 100));
    final i = _teams.indexWhere((t) => t.id == teamId);
    if (i == -1) throw StateError('Team $teamId not found');
    final team = _teams[i];
    if (team.roster.any((p) => p.number == draft.number)) {
      throw StateError('Jersey #${draft.number} already taken on this team');
    }
    final player = Player(
      number: draft.number,
      name: draft.name,
      position: draft.position,
      captain: draft.captain,
    );
    final newRoster = List<Player>.from(team.roster)
      ..add(player)
      ..sort((a, b) => a.number.compareTo(b.number));
    // Captain is exclusive — clear any other captain when promoting one.
    final cleaned = draft.captain
        ? newRoster
              .map(
                (p) => p.number == player.number ? p : _withCaptain(p, false),
              )
              .toList()
        : newRoster;
    _teams[i] = team.copyWith(roster: cleaned);
    return player;
  }

  @override
  Future<Player> updatePlayer(
    String deviceId,
    String teamId,
    int currentNumber,
    PlayerDraft draft,
  ) async {
    await Future.delayed(const Duration(milliseconds: 100));
    final i = _teams.indexWhere((t) => t.id == teamId);
    if (i == -1) throw StateError('Team $teamId not found');
    final team = _teams[i];
    final pi = team.roster.indexWhere((p) => p.number == currentNumber);
    if (pi == -1) throw StateError('Player #$currentNumber not found');
    if (draft.number != currentNumber &&
        team.roster.any((p) => p.number == draft.number)) {
      throw StateError('Jersey #${draft.number} already taken on this team');
    }
    final updated = Player(
      number: draft.number,
      name: draft.name,
      position: draft.position,
      captain: draft.captain,
    );
    final newRoster = List<Player>.from(team.roster);
    newRoster[pi] = updated;
    final cleaned = draft.captain
        ? newRoster
              .map(
                (p) => p.number == updated.number ? p : _withCaptain(p, false),
              )
              .toList()
        : newRoster;
    cleaned.sort((a, b) => a.number.compareTo(b.number));
    _teams[i] = team.copyWith(roster: cleaned);
    return updated;
  }

  @override
  Future<void> removePlayer(String deviceId, String teamId, int number) async {
    await Future.delayed(const Duration(milliseconds: 80));
    final i = _teams.indexWhere((t) => t.id == teamId);
    if (i == -1) return;
    final team = _teams[i];
    final newRoster = team.roster.where((p) => p.number != number).toList();
    _teams[i] = team.copyWith(roster: newRoster);
  }

  static Player _withCaptain(Player p, bool captain) => Player(
    number: p.number,
    name: p.name,
    position: p.position,
    captain: captain,
  );

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

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/ble/ble_service.dart';
import 'package:scout_camera/db/app_database.dart';
import 'package:scout_camera/models/command.dart';
import 'package:scout_camera/models/device.dart';
import 'package:scout_camera/models/match.dart';
import 'package:scout_camera/models/recording.dart';
import 'package:scout_camera/models/telemetry.dart';
import 'package:scout_camera/services/backup_service.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Minimal BleService stub for backup tests
// ---------------------------------------------------------------------------

class _StubBleService implements BleService {
  _StubBleService({required this.deviceInfoResult});

  /// Controls what sendCommand returns for GetDeviceInfoCommand.
  /// Pass a [DeviceInfoResponse] for success, or null to return an error
  /// response, or throw to simulate an exception.
  final Object? deviceInfoResult; // DeviceInfoResponse | null | Exception

  @override
  Future<BleCommandResponse<T>> sendCommand<T>(
    String deviceId,
    BleCommand command,
  ) async {
    if (command is GetDeviceInfoCommand) {
      final result = deviceInfoResult;
      if (result is Exception) throw result;
      if (result == null) return BleCommandResponse.error('no device info');
      return BleCommandResponse.ok(result as T?);
    }
    return BleCommandResponse.ok();
  }

  // Unused for backup tests — minimal no-op implementations below.
  @override
  bool get isScanning => false;
  @override
  Stream<List<ScoutDevice>> get discoveredDevices => const Stream.empty();
  @override
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<void> connect(String deviceId) async {}
  @override
  Future<void> disconnect(String deviceId) async {}
  @override
  Stream<CameraConnectionState> connectionStateStream(String deviceId) =>
      const Stream.empty();
  @override
  Stream<DeviceTelemetry> telemetryStream(String deviceId) =>
      const Stream.empty();
  @override
  Future<ThumbnailResult> requestThumbnail(
    String deviceId, {
    int width = 160,
    int height = 90,
    int quality = 60,
  }) async => throw UnimplementedError();
  @override
  Stream<MatchState> matchStateStream(String deviceId) => const Stream.empty();
  @override
  Future<List<RecordingMetadata>> listRecordings(String deviceId) async => [];
  @override
  Future<DownloadToken> requestDownload(
    String deviceId,
    String recordingId,
  ) async => throw UnimplementedError();
  @override
  Future<BleCommandResponse<void>> pushSessionConfig(
    String deviceId,
    PushSessionConfig config,
  ) async => BleCommandResponse.ok();
  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase.forTesting(
  DatabaseConnection(
    NativeDatabase.memory(),
    closeStreamsSynchronously: true,
  ),
);

const _uuid = Uuid();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = _makeDb();
    tempDir = await Directory.systemTemp.createTemp('backup_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  // ---------------------------------------------------------------------------
  // 1. Empty DB export
  // ---------------------------------------------------------------------------

  test('empty DB → valid JSON with empty arrays, device.uuid == null', () async {
    final service = BackupService(db);
    final path = await service.export(outputDir: tempDir);

    final content = await File(path).readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    expect(json['backup_version'], 1);
    expect(json['created_at'], isA<String>());
    expect(json['device']['uuid'], isNull);
    expect(json['device']['model'], 'SST-CAM-01');
    expect(json['users'], isEmpty);
    expect(json['teams'], isEmpty);
    expect(json['sport_configs'], isEmpty);
    expect(json['streaming_configs'], isEmpty);
    expect(json['matches'], isEmpty);
    expect(json['clips'], isEmpty);
  });

  // ---------------------------------------------------------------------------
  // 2. Export with seeded data — correct counts
  // ---------------------------------------------------------------------------

  test('export with users/teams/presets → correct counts in JSON', () async {
    final userId = _uuid.v4();
    final teamId = _uuid.v4();

    // Insert a user
    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: userId, name: 'Coach Diego'),
    );

    // Insert a team with a player
    await db.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: teamId,
        userId: userId,
        name: 'Tigers',
        shortName: 'TIG',
        sport: 'Soccer',
      ),
    );
    await db.teamsDao.insertPlayer(
      PlayersTableCompanion.insert(
        teamId: teamId,
        number: 7,
        name: 'Alice',
        position: 'Midfielder',
      ),
    );

    // Seed built-in presets
    await db.sportPresetsDao.seedBuiltInsForUser(userId);

    final service = BackupService(db);
    final path = await service.export(outputDir: tempDir);

    final content = await File(path).readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    expect(json['users'], hasLength(1));
    expect((json['users'] as List).first['name'], 'Coach Diego');

    final teams = json['teams'] as List;
    expect(teams, hasLength(1));
    expect(teams.first['name'], 'Tigers');
    expect(teams.first['short_name'], 'TIG');

    final roster = teams.first['roster'] as List;
    expect(roster, hasLength(1));
    expect(roster.first['name'], 'Alice');
    expect(roster.first['number'], 7);

    // 7 built-in presets seeded
    expect(json['sport_configs'], hasLength(7));
  });

  // ---------------------------------------------------------------------------
  // 3. JSON is parseable and has backup_version == 1
  // ---------------------------------------------------------------------------

  test('exported JSON parses correctly and has backup_version == 1', () async {
    final service = BackupService(db);
    final path = await service.export(outputDir: tempDir);

    // File must exist
    expect(File(path).existsSync(), isTrue);

    final raw = File(path).readAsStringSync();

    // Must parse without throwing
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      fail('jsonDecode threw: $e');
    }

    expect(json['backup_version'], 1);
    expect(json.containsKey('created_at'), isTrue);
    expect(json.containsKey('device'), isTrue);
    expect(json.containsKey('users'), isTrue);
    expect(json.containsKey('teams'), isTrue);
    expect(json.containsKey('sport_configs'), isTrue);
    expect(json.containsKey('streaming_configs'), isTrue);
    expect(json.containsKey('matches'), isTrue);
    expect(json.containsKey('clips'), isTrue);
  });

  // ---------------------------------------------------------------------------
  // 4. BLE error → device.uuid == null, export still succeeds
  // ---------------------------------------------------------------------------

  test('BLE throws → export succeeds with device.uuid == null', () async {
    final ble = _StubBleService(
      deviceInfoResult: const BleConnectionException('simulated error'),
    );
    final service = BackupService(db, ble: ble);

    final path = await service.export(deviceId: 'dev-1', outputDir: tempDir);

    final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    expect(json['device']['uuid'], isNull);
    expect(json['backup_version'], 1);
  });

  // ---------------------------------------------------------------------------
  // 5. BLE success → device.uuid populated
  // ---------------------------------------------------------------------------

  test('BLE provides device_id → device.uuid populated in JSON', () async {
    const fakeUuid = 'cam-hardware-uuid-abc123';
    final ble = _StubBleService(
      deviceInfoResult: const DeviceInfoResponse(deviceId: fakeUuid),
    );
    final service = BackupService(db, ble: ble);

    final path = await service.export(deviceId: 'dev-1', outputDir: tempDir);

    final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    expect(json['device']['uuid'], fakeUuid);
  });

  // ---------------------------------------------------------------------------
  // 6. BLE returns error response (not ok) → device.uuid == null
  // ---------------------------------------------------------------------------

  test('BLE error response (not ok) → device.uuid == null', () async {
    final ble = _StubBleService(deviceInfoResult: null); // triggers error response
    final service = BackupService(db, ble: ble);

    final path = await service.export(deviceId: 'dev-1', outputDir: tempDir);

    final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    expect(json['device']['uuid'], isNull);
  });

  // ---------------------------------------------------------------------------
  // 7. File is named with today's date
  // ---------------------------------------------------------------------------

  test('exported file is named sst-backup-YYYY-MM-DD.json', () async {
    final service = BackupService(db);
    final path = await service.export(outputDir: tempDir);

    final filename = path.split('/').last;
    expect(filename, startsWith('sst-backup-'));
    expect(filename, endsWith('.json'));
    // Date portion is 10 chars: YYYY-MM-DD
    final datePart = filename.replaceAll('sst-backup-', '').replaceAll('.json', '');
    expect(datePart.length, 10);
    expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(datePart), isTrue);
  });

  // ---------------------------------------------------------------------------
  // 8. Streaming destinations serialized correctly
  // ---------------------------------------------------------------------------

  test('streaming destinations serialized with flat config columns', () async {
    final userId = _uuid.v4();
    final destId = _uuid.v4();

    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: userId, name: 'Coach Maria'),
    );
    await db.streamingDestinationsDao.insertDestination(
      StreamingDestinationsTableCompanion.insert(
        id: destId,
        userId: userId,
        name: 'My YouTube',
        provider: 'youtube',
        protocol: 'rtmp',
        configType: 'rtmp',
        configUrl: 'rtmp://a.rtmp.youtube.com/live2',
        configStreamKey: const Value('sk-abc'),
      ),
    );

    final service = BackupService(db);
    final path = await service.export(outputDir: tempDir);

    final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final configs = json['streaming_configs'] as List;
    expect(configs, hasLength(1));

    final cfg = configs.first as Map<String, dynamic>;
    expect(cfg['id'], destId);
    expect(cfg['user_id'], userId);
    expect(cfg['name'], 'My YouTube');
    expect(cfg['provider'], 'youtube');
    expect(cfg['config_type'], 'rtmp');
    expect(cfg['config_url'], 'rtmp://a.rtmp.youtube.com/live2');
    expect(cfg['config_stream_key'], 'sk-abc');
    expect(cfg['config_username'], isNull);
    expect(cfg['config_password'], isNull);
  });

  // ---------------------------------------------------------------------------
  // 9. Team matches serialized in both teams.matches and top-level matches
  // ---------------------------------------------------------------------------

  test('team matches appear in teams.matches and top-level matches list', () async {
    final userId = _uuid.v4();
    final teamId = _uuid.v4();
    final matchId = _uuid.v4();

    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: userId, name: 'Coach Alex'),
    );
    await db.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: teamId,
        userId: userId,
        name: 'Lions',
        shortName: 'LIO',
        sport: 'Soccer',
      ),
    );
    await db.teamsDao.insertTeamMatch(
      TeamMatchesTableCompanion.insert(
        id: matchId,
        teamId: teamId,
        opponent: 'Bears',
        date: '2026-04-01',
        result: 'W 2-1',
        kind: 'past',
        numPeriods: 2,
        periodLengthSeconds: 2700,
      ),
    );

    final service = BackupService(db);
    final path = await service.export(outputDir: tempDir);

    final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

    // Check top-level matches list
    final matches = json['matches'] as List;
    expect(matches, hasLength(1));
    expect(matches.first['id'], matchId);
    expect(matches.first['opponent'], 'Bears');

    // Check inline in teams
    final teamMatches = (json['teams'] as List).first['matches'] as List;
    expect(teamMatches, hasLength(1));
    expect(teamMatches.first['id'], matchId);
  });
}

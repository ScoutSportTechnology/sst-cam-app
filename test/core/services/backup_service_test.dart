import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_service.dart';
import 'package:sst_cam_app/core/db/app_database.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/core/models/match.dart';
import 'package:sst_cam_app/core/models/network_config.dart';
import 'package:sst_cam_app/core/models/overlay_layout.dart';
import 'package:sst_cam_app/core/models/export_job.dart';
import 'package:sst_cam_app/core/models/preview_layout.dart';
import 'package:sst_cam_app/core/models/recording.dart';
import 'package:sst_cam_app/core/models/telemetry.dart';
import 'package:sst_cam_app/core/services/backup_service.dart';
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
  Stream<List<SstDevice>> get discoveredDevices => const Stream.empty();
  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {}
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
  Future<void> pushSessionConfig(
    String deviceId,
    PushSessionConfig config,
  ) async {}
  @override
  Future<void> pushOverlayLayout(String deviceId, OverlayLayout layout) async {}
  @override
  Future<PreviewLayoutResult> setPreviewLayout(
    String deviceId,
    PreviewLayout layout,
  ) async => const PreviewLayoutResult(
    layout: PreviewLayout.single,
    width: 1280,
    height: 720,
  );
  @override
  Future<ExportJob> requestOverlayExport(
    String deviceId,
    String recordingId,
  ) async => const ExportJob(jobId: 'export-1', state: ExportJobState.pending);
  @override
  Future<ExportJob> pollOverlayExport(String deviceId, String jobId) async =>
      const ExportJob(jobId: 'export-1', state: ExportJobState.failed);
  @override
  Future<NetworkConfigResult> setNetworkConfig(
    String deviceId,
    NetworkConfig config,
  ) async => throw UnimplementedError();
  @override
  Future<NetworkConfigResult> getNetworkConfig(String deviceId) async =>
      throw UnimplementedError();
  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AppDatabase _makeDb() => AppDatabase.forTesting(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
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

  test(
    'fresh DB → JSON has base-seeded user and sport presets, device.uuid == null',
    () async {
      final service = BackupService(db);
      final path = await service.export(outputDir: tempDir);

      final content = await File(path).readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      expect(json['backup_version'], 1);
      expect(json['created_at'], isA<String>());
      expect(json['device']['uuid'], isNull);
      expect(json['device']['model'], 'SST-CAM-01');
      // Base seed always creates default-user with 7 sport presets.
      expect(json['users'], hasLength(1));
      expect(json['sport_configs'], hasLength(7));
      expect(json['teams'], isEmpty);
      expect(json['streaming_configs'], isEmpty);
      expect(json['matches'], isEmpty);
      expect(json['clips'], isEmpty);
    },
  );

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

    // DB has default-user (base seed) + Coach Diego = 2 users.
    final users = json['users'] as List;
    expect(users, hasLength(2));
    expect(users.any((u) => (u as Map)['name'] == 'Coach Diego'), isTrue);

    final teams = json['teams'] as List;
    expect(teams, hasLength(1));
    expect(teams.first['name'], 'Tigers');
    expect(teams.first['short_name'], 'TIG');

    final roster = teams.first['roster'] as List;
    expect(roster, hasLength(1));
    expect(roster.first['name'], 'Alice');
    expect(roster.first['number'], 7);

    // 7 presets for default-user + 7 for Coach Diego = 14 total.
    expect(json['sport_configs'], hasLength(14));
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

    final json =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
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

    final json =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    expect(json['device']['uuid'], fakeUuid);
  });

  // ---------------------------------------------------------------------------
  // 6. BLE returns error response (not ok) → device.uuid == null
  // ---------------------------------------------------------------------------

  test('BLE error response (not ok) → device.uuid == null', () async {
    final ble = _StubBleService(
      deviceInfoResult: null,
    ); // triggers error response
    final service = BackupService(db, ble: ble);

    final path = await service.export(deviceId: 'dev-1', outputDir: tempDir);

    final json =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    expect(json['device']['uuid'], isNull);
  });

  // ---------------------------------------------------------------------------
  // 7. File is named with today's date
  // ---------------------------------------------------------------------------

  test('exported file is named sst-backup-YYYY-MM-DD-HHmm.json', () async {
    final service = BackupService(db);
    final path = await service.export(outputDir: tempDir);

    final filename = path.split('/').last;
    expect(filename, startsWith('sst-backup-'));
    expect(filename, endsWith('.json'));
    // Date-time portion is 15 chars: YYYY-MM-DD-HHmm
    final datePart = filename
        .replaceAll('sst-backup-', '')
        .replaceAll('.json', '');
    expect(datePart.length, 15);
    expect(RegExp(r'^\d{4}-\d{2}-\d{2}-\d{4}$').hasMatch(datePart), isTrue);
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

    final json =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
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
  // 9. Team matches serialized in top-level matches list (inline removed — #19)
  // ---------------------------------------------------------------------------

  test('team matches appear in top-level matches list', () async {
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

    final json =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

    // Matches only in top-level list (inline per-team matches removed)
    final matches = json['matches'] as List;
    expect(matches, hasLength(1));
    expect(matches.first['id'], matchId);
    expect(matches.first['opponent'], 'Bears');

    // Teams do NOT have inline matches
    final teamMap = (json['teams'] as List).first as Map<String, dynamic>;
    expect(teamMap.containsKey('matches'), isFalse);
  });

  // ===========================================================================
  // Import tests
  // ===========================================================================

  // ---------------------------------------------------------------------------
  // 10. Happy path: export → import → counts match
  // ---------------------------------------------------------------------------

  test('import: export then import into fresh DB → counts match', () async {
    final userId = _uuid.v4();
    final teamId = _uuid.v4();

    // Remove base-seeded default-user so only Coach Diego is in the export.
    await db.usersDao.deleteById(kDefaultUserId);

    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: userId, name: 'Coach Diego'),
    );
    await db.teamsDao.insertTeam(
      TeamsTableCompanion.insert(
        id: teamId,
        userId: userId,
        name: 'Tigers',
        shortName: 'TIG',
        sport: 'Soccer',
      ),
    );
    await db.sportPresetsDao.seedBuiltInsForUser(userId);

    final service = BackupService(db);
    final exportPath = await service.export(outputDir: tempDir);

    // Import into a fresh database.
    final freshDb = _makeDb();
    addTearDown(freshDb.close);

    final importService = BackupService(freshDb);
    final firstUserId = await importService.import(File(exportPath));

    expect(firstUserId, userId);
    // Import wipes the DB before importing — fresh DB's default-user is removed
    // and only Coach Diego (from export) is present.
    expect(await freshDb.usersDao.getAll(), hasLength(1));
    expect(await freshDb.teamsDao.getForUser(userId), hasLength(1));
    expect(await freshDb.sportPresetsDao.getForUser(userId), hasLength(7));
  });

  // ---------------------------------------------------------------------------
  // 11. Atomicity: corrupt backup leaves seed rows intact
  // ---------------------------------------------------------------------------

  test('import: corrupt backup rolls back → seed rows intact', () async {
    // Seed the source DB with a known user.
    final seedUserId = _uuid.v4();
    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: seedUserId, name: 'Seed User'),
    );

    // Build a backup JSON that is structurally valid (passes version check) but
    // contains a team whose user_id references a non-existent user — this
    // triggers a FK constraint violation inside the transaction, causing a
    // rollback.
    final corruptBackup = jsonEncode({
      'backup_version': 1,
      'created_at': DateTime.now().toIso8601String(),
      'device': {'uuid': null, 'model': 'SST-CAM-01'},
      'users': [
        {'id': 'valid-user', 'name': 'Valid User'},
      ],
      'teams': [
        {
          'id': 'team-orphan',
          // References a user_id that is NOT in the users list above — FK
          // violation once FK enforcement is active.
          'user_id': 'non-existent-user',
          'name': 'Orphan Team',
          'short_name': 'ORP',
          'sport': 'Soccer',
          'hidden': false,
          'roster': <dynamic>[],
          'matches': <dynamic>[],
        },
      ],
      'matches': <dynamic>[],
      'sport_configs': <dynamic>[],
      'streaming_configs': <dynamic>[],
      'clips': <dynamic>[],
    });

    final corruptFile = File('${tempDir.path}/corrupt.json');
    await corruptFile.writeAsString(corruptBackup);

    final service = BackupService(db);

    // The import should throw (FK violation inside the transaction).
    await expectLater(
      () => service.import(corruptFile),
      throwsA(isNot(isA<BackupImportException>())),
    );

    // Crucially, both the default-user (base seed) and the Seed User must
    // still be present — rollback worked, no partial state was committed.
    final users = await db.usersDao.getAll();
    expect(users, hasLength(2));
    expect(users.any((u) => u.id == seedUserId), isTrue);
  });

  // ---------------------------------------------------------------------------
  // 12. Malformed JSON
  // ---------------------------------------------------------------------------

  test('import: malformed JSON → BackupImportException', () async {
    final badFile = File('${tempDir.path}/bad.json');
    await badFile.writeAsString('not valid json {{{');

    final service = BackupService(db);
    await expectLater(
      () => service.import(badFile),
      throwsA(
        isA<BackupImportException>().having(
          (e) => e.message,
          'message',
          'malformed JSON',
        ),
      ),
    );
  });

  // ---------------------------------------------------------------------------
  // 13. backup_version mismatch
  // ---------------------------------------------------------------------------

  test('import: backup_version 2 → BackupImportException', () async {
    final futureBackup = jsonEncode({
      'backup_version': 2,
      'created_at': DateTime.now().toIso8601String(),
      'device': {'uuid': null, 'model': 'SST-CAM-01'},
      'users': <dynamic>[],
      'teams': <dynamic>[],
      'matches': <dynamic>[],
      'sport_configs': <dynamic>[],
      'streaming_configs': <dynamic>[],
      'clips': <dynamic>[],
    });

    final f = File('${tempDir.path}/future.json');
    await f.writeAsString(futureBackup);

    final service = BackupService(db);
    await expectLater(
      () => service.import(f),
      throwsA(
        isA<BackupImportException>().having(
          (e) => e.message,
          'message',
          'unsupported backup version: 2',
        ),
      ),
    );
  });

  // ---------------------------------------------------------------------------
  // 14. UUID mismatch
  // ---------------------------------------------------------------------------

  test('import: UUID mismatch → BackupImportException', () async {
    final mismatchBackup = jsonEncode({
      'backup_version': 1,
      'created_at': DateTime.now().toIso8601String(),
      'device': {'uuid': 'cam-uuid-A', 'model': 'SST-CAM-01'},
      'users': <dynamic>[],
      'teams': <dynamic>[],
      'matches': <dynamic>[],
      'sport_configs': <dynamic>[],
      'streaming_configs': <dynamic>[],
      'clips': <dynamic>[],
    });

    final f = File('${tempDir.path}/mismatch.json');
    await f.writeAsString(mismatchBackup);

    final service = BackupService(db);
    await expectLater(
      () => service.import(f, currentCameraDeviceId: 'cam-uuid-B'),
      throwsA(
        isA<BackupImportException>().having(
          (e) => e.message,
          'message',
          'backup is for a different camera',
        ),
      ),
    );
  });

  // ---------------------------------------------------------------------------
  // 15. Null backup UUID + non-null camera ID → import proceeds
  // ---------------------------------------------------------------------------

  test('import: null backup uuid + non-null camera id → proceeds', () async {
    final userId = _uuid.v4();
    final backupJson = jsonEncode({
      'backup_version': 1,
      'created_at': DateTime.now().toIso8601String(),
      'device': {'uuid': null, 'model': 'SST-CAM-01'},
      'users': [
        {'id': userId, 'name': 'Solo User'},
      ],
      'teams': <dynamic>[],
      'matches': <dynamic>[],
      'sport_configs': <dynamic>[],
      'streaming_configs': <dynamic>[],
      'clips': <dynamic>[],
    });

    final f = File('${tempDir.path}/null_uuid.json');
    await f.writeAsString(backupJson);

    final service = BackupService(db);
    // Should NOT throw — null backup UUID skips the UUID check.
    final firstId = await service.import(
      f,
      currentCameraDeviceId: 'cam-uuid-X',
    );

    expect(firstId, userId);
    expect(await db.usersDao.getAll(), hasLength(1));
  });

  // ---------------------------------------------------------------------------
  // 16. Both UUID fields null → import proceeds
  // ---------------------------------------------------------------------------

  test('import: both UUIDs null → proceeds without UUID validation', () async {
    final userId = _uuid.v4();
    final backupJson = jsonEncode({
      'backup_version': 1,
      'created_at': DateTime.now().toIso8601String(),
      'device': {'uuid': null, 'model': 'SST-CAM-01'},
      'users': [
        {'id': userId, 'name': 'Solo User'},
      ],
      'teams': <dynamic>[],
      'matches': <dynamic>[],
      'sport_configs': <dynamic>[],
      'streaming_configs': <dynamic>[],
      'clips': <dynamic>[],
    });

    final f = File('${tempDir.path}/both_null.json');
    await f.writeAsString(backupJson);

    final service = BackupService(db);
    // No currentCameraDeviceId provided — should succeed.
    final firstId = await service.import(f);

    expect(firstId, userId);
    expect(await db.usersDao.getAll(), hasLength(1));
  });

  // ---------------------------------------------------------------------------
  // 17. Empty backup (no users) → succeeds, DB is empty
  // ---------------------------------------------------------------------------

  test('import: empty backup (no users) → succeeds, DB empty', () async {
    // First seed the DB so we can verify it is emptied.
    await db.usersDao.insertUser(
      UsersTableCompanion.insert(id: _uuid.v4(), name: 'Existing User'),
    );
    // DB has default-user (base seed) + Existing User = 2 rows.
    expect(await db.usersDao.getAll(), hasLength(2));

    final emptyBackup = jsonEncode({
      'backup_version': 1,
      'created_at': DateTime.now().toIso8601String(),
      'device': {'uuid': null, 'model': 'SST-CAM-01'},
      'users': <dynamic>[],
      'teams': <dynamic>[],
      'matches': <dynamic>[],
      'sport_configs': <dynamic>[],
      'streaming_configs': <dynamic>[],
      'clips': <dynamic>[],
    });

    final f = File('${tempDir.path}/empty.json');
    await f.writeAsString(emptyBackup);

    final service = BackupService(db);
    final firstId = await service.import(f);

    expect(firstId, isNull);
    expect(await db.usersDao.getAll(), isEmpty);
  });
}

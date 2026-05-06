import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../ble/ble_service.dart';
import '../db/app_database.dart';
import '../models/command.dart';

/// Thrown by [BackupService.import] on validation failures.
///
/// Distinct from Drift/IO errors (which propagate as-is) so callers can
/// surface a user-friendly message without catching every exception.
class BackupImportException implements Exception {
  final String message;
  const BackupImportException(this.message);

  @override
  String toString() => 'BackupImportException: $message';
}

/// Exports all app data to a dated JSON backup file.
///
/// Construction: `BackupService(db)` for export-only use. Pass `ble` to enable
/// the optional camera device-UUID embedding in the backup file — used by
/// [BackupService.import] in U11 to validate restore compatibility.
class BackupService {
  BackupService(this._db, {BleService? ble}) : _ble = ble;

  final AppDatabase _db;
  final BleService? _ble;

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  /// Exports all app data to a dated JSON file.
  ///
  /// Returns the absolute path of the written file.
  ///
  /// If [deviceId] is provided and [BleService] was injected, sends
  /// [GetDeviceInfoCommand] to read the camera's stable device UUID. Any
  /// failure (BLE error, timeout, exception) is swallowed and
  /// `device.uuid` is set to null — the export still proceeds.
  ///
  /// Pass [outputDir] to override the target directory. Defaults to
  /// [getApplicationDocumentsDirectory()]. Used in tests to write to a
  /// temporary directory instead of the application documents path (which
  /// is unavailable in the Flutter test environment).
  Future<String> export({String? deviceId, Directory? outputDir}) async {
    // 1. Optionally fetch device UUID via BLE ----------------------------------------
    String? cameraUuid;
    if (_ble != null && deviceId != null) {
      try {
        final response = await _ble.sendCommand<DeviceInfoResponse>(
          deviceId,
          GetDeviceInfoCommand(),
        );
        if (response.isOk) {
          cameraUuid = response.payload?.deviceId;
        }
      } catch (_) {
        // Any BLE failure is silently swallowed; uuid stays null.
      }
    }

    // 2. Read all tables via one-shot DAO queries -------------------------------------
    final users = await _db.usersDao.getAll();

    // Collect per-team data structures indexed by teamId.
    final teamPlayers = <String, List<PlayersTableData>>{};
    final teamMatches = <String, List<TeamMatchesTableData>>{};
    final allTeams = <TeamsTableData>[];

    for (final user in users) {
      final teams = await _db.teamsDao.getForUser(user.id);
      allTeams.addAll(teams);
      for (final team in teams) {
        teamPlayers[team.id] = await _db.teamsDao.getPlayersForTeam(team.id);
        teamMatches[team.id] = await _db.teamsDao.getTeamMatches(team.id);
      }
    }

    final allPresets = <dynamic>[];
    final allDestinations = <dynamic>[];
    for (final user in users) {
      allPresets.addAll(await _db.sportPresetsDao.getForUser(user.id));
      allDestinations.addAll(
        await _db.streamingDestinationsDao.getForUser(user.id),
      );
    }

    // Clips and thumbnails are deferred (firmware clip-UUID contract not yet
    // confirmed). We include an empty list in the schema for forward compatibility.
    // TODO(U10): wire listRecordings() → Drift clips/thumbnails after firmware
    // confirms clip UUID echo-back.

    // 3. Build the backup map -------------------------------------------------------
    final now = DateTime.now();

    final usersJson = users
        .map((u) => <String, dynamic>{'id': u.id, 'name': u.name})
        .toList();

    final teamsJson = allTeams.map((team) {
      final players = teamPlayers[team.id] ?? [];
      return <String, dynamic>{
        'id': team.id,
        'user_id': team.userId,
        'name': team.name,
        'short_name': team.shortName,
        'sport': team.sport,
        'hidden': team.hidden,
        'roster': players
            .map(
              (p) => <String, dynamic>{
                'number': p.number,
                'name': p.name,
                'position': p.position,
                'captain': p.captain,
              },
            )
            .toList(),
      };
    }).toList();

    final matchesJson = allTeams.expand<Map<String, dynamic>>((team) {
      final matches = teamMatches[team.id] ?? [];
      return matches.map(
        (m) => <String, dynamic>{
          'id': m.id,
          'team_id': m.teamId,
          'opponent': m.opponent,
          'date': m.date,
          'result': m.result,
          'kind': m.kind,
          'num_periods': m.numPeriods,
          'period_length_seconds': m.periodLengthSeconds,
          'clips': m.clips,
          'size_mb': m.sizeMb,
        },
      );
    }).toList();

    final sportConfigsJson = allPresets
        .map(
          (p) => <String, dynamic>{
            'id': p.id,
            'user_id': p.userId,
            'name': p.name,
            'sport': p.sport,
            'num_periods': p.numPeriods,
            'period_length_seconds': p.periodLengthSeconds,
            'built_in': p.builtIn,
          },
        )
        .toList();

    final streamingConfigsJson = allDestinations
        .map(
          (d) => <String, dynamic>{
            'id': d.id,
            'user_id': d.userId,
            'name': d.name,
            'provider': d.provider,
            'protocol': d.protocol,
            'config_type': d.configType,
            'config_url': d.configUrl,
            'config_stream_key': d.configStreamKey,
            'config_username': d.configUsername,
            'config_password': d.configPassword,
          },
        )
        .toList();

    final backup = <String, dynamic>{
      'backup_version': 1,
      'created_at': now.toIso8601String(),
      'device': <String, dynamic>{'uuid': cameraUuid, 'model': 'SST-CAM-01'},
      'users': usersJson,
      'teams': teamsJson,
      'sport_configs': sportConfigsJson,
      'streaming_configs': streamingConfigsJson,
      'matches': matchesJson,
      'clips': const <dynamic>[],
    };

    // 4. Serialize to JSON -----------------------------------------------------------
    final json = jsonEncode(backup);

    // 5. Resolve output directory ---------------------------------------------------
    final dir = outputDir ?? await getApplicationDocumentsDirectory();

    // 6. Write file as sst-backup-YYYY-MM-DD.json -----------------------------------
    final dateStr =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final file = File('${dir.path}/sst-backup-$dateStr.json');
    await file.writeAsString(json);

    // 7. Return path ----------------------------------------------------------------
    return file.path;
  }

  // ---------------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------------

  /// Imports backup data from [file] into the database, atomically.
  ///
  /// Validation order:
  /// 1. JSON must parse without error.
  /// 2. `backup_version` must equal 1.
  /// 3. If `device.uuid` in the backup is non-null **and** [currentCameraDeviceId]
  ///    is non-null, they must match — otherwise the backup is for a different
  ///    camera.
  ///
  /// On validation failure throws [BackupImportException]. All other errors
  /// (Drift, IO) propagate as-is; the caller can rely on the transaction
  /// rollback to leave the database unchanged.
  ///
  /// Returns the first user ID from the restored data so the caller can update
  /// `activeUserProvider`; returns null if the backup contained no users.
  ///
  /// NOTE: `device.uuid` stability is assumed to be a hardware UUID from
  /// `DeviceInfoResponse.deviceId` in proto. Firmware confirmation pending —
  /// see U11 open question in the refactor plan.
  Future<String?> import(File file, {String? currentCameraDeviceId}) async {
    // 1. Parse JSON ---------------------------------------------------------------
    late String contents;
    try {
      contents = await file.readAsString();
    } on FileSystemException catch (e) {
      throw BackupImportException('file not found or unreadable: ${e.message}');
    }
    late Map<String, dynamic> json;
    try {
      json = jsonDecode(contents) as Map<String, dynamic>;
    } catch (_) {
      throw const BackupImportException('malformed JSON');
    }

    // 2. Validate backup_version --------------------------------------------------
    if (json['backup_version'] != 1) {
      throw BackupImportException(
        'unsupported backup version: ${json['backup_version']}',
      );
    }

    // 3. Optional UUID validation --------------------------------------------------
    // Fix 9: If the backup has a device UUID, require the camera to be
    // connected so we can verify compatibility. If no UUID in the backup,
    // proceed without the check (legacy backups).
    final backupDeviceUuid =
        (json['device'] as Map<String, dynamic>?)?['uuid'] as String?;
    if (backupDeviceUuid != null) {
      if (currentCameraDeviceId == null) {
        throw const BackupImportException(
          'Connect the camera to verify backup compatibility',
        );
      }
      if (backupDeviceUuid != currentCameraDeviceId) {
        throw const BackupImportException('backup is for a different camera');
      }
    }

    // 4. Parse entities from JSON -------------------------------------------------
    // Fix 12: Wrap all _parse* calls in a try-catch so malformed numbers or
    // missing fields surface as a user-friendly BackupImportException rather
    // than an unhandled TypeError or CastError.
    final List<UsersTableCompanion> userCompanions;
    final List<TeamsTableCompanion> teamCompanions;
    final List<PlayersTableCompanion> playerCompanions;
    final List<TeamMatchesTableCompanion> matchCompanions;
    final List<SportPresetsTableCompanion> presetCompanions;
    final List<StreamingDestinationsTableCompanion> destCompanions;
    try {
      userCompanions = _parseUsers(
        (json['users'] as List<dynamic>?) ?? const [],
      );
      teamCompanions = _parseTeams(
        (json['teams'] as List<dynamic>?) ?? const [],
      );
      playerCompanions = _parsePlayers(
        (json['teams'] as List<dynamic>?) ?? const [],
      );
      // Matches are stored both inline under teams and at the top-level
      // "matches" key. Use the top-level list (canonical; avoids double-insert).
      matchCompanions = _parseMatches(
        (json['matches'] as List<dynamic>?) ?? const [],
      );
      presetCompanions = _parsePresets(
        (json['sport_configs'] as List<dynamic>?) ?? const [],
      );
      destCompanions = _parseDestinations(
        (json['streaming_configs'] as List<dynamic>?) ?? const [],
      );
    } catch (e) {
      throw BackupImportException('invalid backup data: $e');
    }

    // 5. Atomic replace inside db.transaction() -----------------------------------
    await _db.transaction(() async {
      // Delete in FK-safe order (children first).
      await _db.delete(_db.thumbnailsTable).go();
      await _db.delete(_db.clipsTable).go();
      await _db.delete(_db.teamMatchesTable).go();
      await _db.delete(_db.playersTable).go();
      await _db.delete(_db.teamsTable).go();
      await _db.delete(_db.sportPresetsTable).go();
      await _db.delete(_db.streamingDestinationsTable).go();
      await _db.delete(_db.usersTable).go();

      // Insert all backup rows in FK-safe order (parents first).
      await _db.batch((b) {
        b.insertAll(_db.usersTable, userCompanions);
        b.insertAll(_db.teamsTable, teamCompanions);
        b.insertAll(_db.playersTable, playerCompanions);
        b.insertAll(_db.teamMatchesTable, matchCompanions);
        b.insertAll(_db.sportPresetsTable, presetCompanions);
        b.insertAll(_db.streamingDestinationsTable, destCompanions);
      });
    });

    // 6. Return the first user ID -------------------------------------------------
    return userCompanions.isNotEmpty ? userCompanions.first.id.value : null;
  }

  // ---------------------------------------------------------------------------
  // JSON parsing helpers
  // ---------------------------------------------------------------------------

  static List<UsersTableCompanion> _parseUsers(List<dynamic> json) {
    return json.map((u) {
      final m = u as Map<String, dynamic>;
      return UsersTableCompanion.insert(
        id: m['id'] as String,
        name: m['name'] as String,
      );
    }).toList();
  }

  static List<TeamsTableCompanion> _parseTeams(List<dynamic> json) {
    return json.map((t) {
      final m = t as Map<String, dynamic>;
      return TeamsTableCompanion.insert(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        name: m['name'] as String,
        shortName: m['short_name'] as String,
        sport: m['sport'] as String,
        hidden: Value(m['hidden'] as bool? ?? false),
      );
    }).toList();
  }

  /// Collects all roster entries across all teams.
  static List<PlayersTableCompanion> _parsePlayers(List<dynamic> teamsJson) {
    final companions = <PlayersTableCompanion>[];
    for (final t in teamsJson) {
      final team = t as Map<String, dynamic>;
      final teamId = team['id'] as String;
      final roster = (team['roster'] as List<dynamic>?) ?? const [];
      for (final p in roster) {
        final pm = p as Map<String, dynamic>;
        companions.add(
          PlayersTableCompanion.insert(
            teamId: teamId,
            // Fix 12: safe int cast — JSON may deserialize numbers as double.
            number: (pm['number'] as num).toInt(),
            name: pm['name'] as String,
            position: pm['position'] as String,
            captain: Value(pm['captain'] as bool? ?? false),
          ),
        );
      }
    }
    return companions;
  }

  /// Parses the top-level `matches` array in the backup.
  static List<TeamMatchesTableCompanion> _parseMatches(List<dynamic> json) {
    return json.map((match) {
      final m = match as Map<String, dynamic>;
      return TeamMatchesTableCompanion.insert(
        id: m['id'] as String,
        teamId: m['team_id'] as String,
        opponent: m['opponent'] as String,
        date: m['date'] as String,
        result: m['result'] as String,
        kind: m['kind'] as String,
        // Fix 12: safe int casts.
        numPeriods: (m['num_periods'] as num).toInt(),
        periodLengthSeconds: (m['period_length_seconds'] as num).toInt(),
        clips: Value((m['clips'] as num?)?.toInt() ?? 0),
        sizeMb: Value((m['size_mb'] as num?)?.toInt() ?? 0),
      );
    }).toList();
  }

  static List<SportPresetsTableCompanion> _parsePresets(List<dynamic> json) {
    return json.map((p) {
      final m = p as Map<String, dynamic>;
      return SportPresetsTableCompanion.insert(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        name: m['name'] as String,
        sport: m['sport'] as String,
        // Fix 12: safe int casts.
        numPeriods: (m['num_periods'] as num).toInt(),
        periodLengthSeconds: (m['period_length_seconds'] as num).toInt(),
        builtIn: Value(m['built_in'] as bool? ?? false),
      );
    }).toList();
  }

  static List<StreamingDestinationsTableCompanion> _parseDestinations(
    List<dynamic> json,
  ) {
    return json.map((d) {
      final m = d as Map<String, dynamic>;
      return StreamingDestinationsTableCompanion.insert(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        name: m['name'] as String,
        provider: m['provider'] as String,
        protocol: m['protocol'] as String,
        configType: m['config_type'] as String,
        configUrl: m['config_url'] as String,
        configStreamKey: Value(m['config_stream_key'] as String?),
        configUsername: Value(m['config_username'] as String?),
        configPassword: Value(m['config_password'] as String?),
      );
    }).toList();
  }
}

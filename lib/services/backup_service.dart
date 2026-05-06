import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../ble/ble_service.dart';
import '../db/app_database.dart';
import '../models/command.dart';

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
      final matches = teamMatches[team.id] ?? [];
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
        'matches': matches
            .map(
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
      'device': <String, dynamic>{
        'uuid': cameraUuid,
        'model': 'SST-CAM-01',
      },
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
    final dateStr = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final file = File('${dir.path}/sst-backup-$dateStr.json');
    await file.writeAsString(json);

    // 7. Return path ----------------------------------------------------------------
    return file.path;
  }
}

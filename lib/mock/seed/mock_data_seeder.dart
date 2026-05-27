import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import '../../core/db/app_database.dart';
import '../../core/services/video_path_service.dart';

/// Seeds the Drift database with mock fixture data from assets/mock/fixtures/.
///
/// Reads JSON fixtures committed to the repo and inserts them into the DB
/// so every screen has realistic data in development without a real device.
/// Uses insertOnConflictUpdate — calling seed() twice overwrites existing rows
/// with fixture values. Safe to call on a fresh or pre-seeded DB.
///
/// After the DB transaction, also writes a 1-byte placeholder file at
/// [VideoPathService.recordingPath] for every past match that has sizeMb > 0
/// (i.e. "on device"). This lets the Video Library detect a local file without
/// requiring an actual download.
class MockDataSeeder {
  MockDataSeeder(this._db, {VideoPathService? videoPathService})
      : _videoPathService = videoPathService ?? VideoPathService();

  final AppDatabase _db;
  final VideoPathService _videoPathService;

  /// Seeds teams, players, matches, and streaming destinations from fixture
  /// JSON files. The default user ('default-user') is assumed to already exist
  /// (created by AppDatabase._seedBaseData via onCreate).
  ///
  /// After all DB rows are written, placeholder video files are created for
  /// every past match with sizeMb > 0 so the Video Library can detect them.
  Future<void> seed() async {
    // Load all fixture files in parallel, then insert in dependency order
    // (teams must exist before matches/players reference them via FK).
    final [teams, matches, destinations, players] = await Future.wait([
      _loadFixture('teams'),
      _loadFixture('matches'),
      _loadFixture('streaming_destinations'),
      _loadFixture('players'),
    ]);
    // Wrap all inserts in a single transaction — if any insert fails the
    // entire seed is rolled back, leaving the DB in a clean state.
    await _db.transaction(() async {
      await _insertTeams(teams);
      await _insertPlayers(players); // after teams (FK dependency)
      await _insertMatches(matches);
      await _insertStreamingDestinations(destinations);
    });

    // Write placeholder files for "on device" past matches AFTER the
    // transaction completes so any failure here does not roll back DB rows.
    final onDeviceMatches = matches.where(
      (row) =>
          row['kind'] == 'past' && (row['sizeMb'] as int? ?? 0) > 0,
    );
    await Future.wait(
      onDeviceMatches.map((row) => _writePlaceholderFile(row['id'] as String)),
    );
  }

  Future<void> _writePlaceholderFile(String matchId) async {
    final path = await _videoPathService.recordingPath(matchId);
    final file = File(path);
    // Skip only if the file already contains a real video (> 1 KB).
    // A 1-byte sentinel left by an older version of the seeder must be
    // overwritten so the player receives a playable file.
    if (file.existsSync() && file.lengthSync() > 1024) return;
    await file.parent.create(recursive: true);
    // Copy the bundled mock video so the file is a real, playable MP4.
    // Falls back to a 1-byte sentinel only when rootBundle is unavailable
    // (unit-test environments that haven't loaded the asset bundle).
    try {
      final data = await rootBundle.load('assets/ble/mock-video.mp4');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    } catch (_) {
      try {
        await file.writeAsBytes([0x00], flush: true);
      } catch (writeError) {
        debugPrint(
          'MockDataSeeder: sentinel write also failed: $writeError',
        );
        // Non-fatal: the match row is already committed; missing placeholder
        // means isOnDeviceProvider returns false for this match.
      }
    }
  }

  Future<void> _insertTeams(List<Map<String, dynamic>> rows) async {
    final companions = rows
        .map(
          (row) => TeamsTableCompanion.insert(
            id: row['id'] as String,
            userId: row['userId'] as String,
            name: row['name'] as String,
            shortName: row['shortName'] as String,
            sport: row['sport'] as String,
            hidden: Value(row['hidden'] as bool? ?? false),
          ),
        )
        .toList();
    await _db.batch((b) => b.insertAllOnConflictUpdate(_db.teamsTable, companions));
  }

  Future<void> _insertPlayers(List<Map<String, dynamic>> rows) async {
    final companions = rows
        .map(
          (row) => PlayersTableCompanion.insert(
            teamId: row['teamId'] as String,
            number: row['number'] as int,
            name: row['name'] as String,
            position: row['position'] as String,
            captain: Value(row['captain'] as bool? ?? false),
          ),
        )
        .toList();
    await _db.batch((b) => b.insertAllOnConflictUpdate(_db.playersTable, companions));
  }

  Future<void> _insertMatches(List<Map<String, dynamic>> rows) async {
    final companions = rows
        .map(
          (row) => TeamMatchesTableCompanion.insert(
            id: row['id'] as String,
            teamId: row['teamId'] as String,
            opponent: row['opponent'] as String,
            date: row['date'] as String,
            result: row['result'] as String,
            kind: row['kind'] as String,
            numPeriods: row['numPeriods'] as int,
            periodLengthSeconds: row['periodLengthSeconds'] as int,
            clips: Value(row['clips'] as int? ?? 0),
            sizeMb: Value(row['sizeMb'] as int? ?? 0),
            eventsJson: Value(row['eventsJson'] as String? ?? '[]'),
          ),
        )
        .toList();
    await _db.batch((b) => b.insertAllOnConflictUpdate(_db.teamMatchesTable, companions));
  }

  Future<void> _insertStreamingDestinations(
    List<Map<String, dynamic>> rows,
  ) async {
    final companions = rows
        .map(
          (row) => StreamingDestinationsTableCompanion.insert(
            id: row['id'] as String,
            userId: row['userId'] as String,
            name: row['name'] as String,
            provider: row['provider'] as String,
            protocol: row['protocol'] as String,
            configType: row['configType'] as String,
            configUrl: row['configUrl'] as String,
            configStreamKey: Value(row['configStreamKey'] as String?),
            configUsername: Value(row['configUsername'] as String?),
            configPassword: Value(row['configPassword'] as String?),
          ),
        )
        .toList();
    await _db.batch(
      (b) => b.insertAllOnConflictUpdate(
        _db.streamingDestinationsTable,
        companions,
      ),
    );
  }

  /// Loads and parses a fixture JSON file, stripping `//` comment lines.
  Future<List<Map<String, dynamic>>> _loadFixture(String name) async {
    final raw =
        await rootBundle.loadString('assets/ble/fixtures/$name.json');
    // Strip lines that are purely // comments (JSON doesn't support comments).
    final stripped = raw
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    final parsed = jsonDecode(stripped) as List<dynamic>;
    return parsed.cast<Map<String, dynamic>>();
  }
}

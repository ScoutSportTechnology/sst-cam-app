import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';

import 'app_database.dart';

/// Seeds the Drift database with mock fixture data from assets/mock/fixtures/.
///
/// Reads JSON fixtures committed to the repo and inserts them into the DB
/// so every screen has realistic data in development without a real device.
/// Uses insertOrIgnore so the seeder is safe to call multiple times.
class MockDataSeeder {
  const MockDataSeeder(this._db);

  final AppDatabase _db;

  /// Seeds teams, matches, and streaming destinations from fixture JSON files.
  /// The default user ('default-user') is assumed to already exist (created by
  /// AppDatabase._seedBaseData via onCreate).
  Future<void> seed() async {
    // Load all fixture files in parallel, then insert in dependency order
    // (teams must exist before matches reference them via FK).
    final results = await Future.wait([
      _loadFixture('teams'),
      _loadFixture('matches'),
      _loadFixture('streaming_destinations'),
    ]);
    await _insertTeams(results[0]);
    await _insertMatches(results[1]);
    await _insertStreamingDestinations(results[2]);
  }

  Future<void> _insertTeams(List<Map<String, dynamic>> rows) async {
    for (final row in rows) {
      await _db.into(_db.teamsTable).insertOnConflictUpdate(
        TeamsTableCompanion.insert(
          id: row['id'] as String,
          userId: row['userId'] as String,
          name: row['name'] as String,
          shortName: row['shortName'] as String,
          sport: row['sport'] as String,
          hidden: Value(row['hidden'] as bool? ?? false),
        ),
      );
    }
  }

  Future<void> _insertMatches(List<Map<String, dynamic>> rows) async {
    for (final row in rows) {
      await _db.into(_db.teamMatchesTable).insertOnConflictUpdate(
        TeamMatchesTableCompanion.insert(
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
      );
    }
  }

  Future<void> _insertStreamingDestinations(
    List<Map<String, dynamic>> rows,
  ) async {
    for (final row in rows) {
      await _db.into(_db.streamingDestinationsTable).insertOnConflictUpdate(
        StreamingDestinationsTableCompanion.insert(
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
      );
    }
  }

  /// Loads and parses a fixture JSON file, stripping `//` comment lines.
  Future<List<Map<String, dynamic>>> _loadFixture(String name) async {
    final raw =
        await rootBundle.loadString('assets/mock/fixtures/$name.json');
    // Strip lines that are purely // comments (JSON doesn't support comments).
    final stripped = raw
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    final parsed = jsonDecode(stripped) as List<dynamic>;
    return parsed.cast<Map<String, dynamic>>();
  }
}

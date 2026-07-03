import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../../core/db/app_database.dart';
import '../../core/services/video_path_service.dart';
import '../mock_video_fetcher.dart';

/// Applies the seed-data flag to the local database at dev startup:
///
/// - [seed] == true → insert mock fixtures (teams, matches, players, streaming
///   destinations) and materialize on-device videos by fetching them over the
///   live mock WiFi download path ([downloadBaseUrl]).
/// - [seed] == false → wipe all rows back to base scaffolding (default user +
///   sport presets) AND delete on-device past-match video files so the app
///   boots with a clean slate.
///
/// [downloadBaseUrl] is read regardless of the camera toggle so the seed path
/// can always reach the mock download endpoint. Lives under `lib/mock/` so it
/// and its [MockDataSeeder] dependency are excluded from stage/prod builds —
/// only `main.dart` (dev) imports it.
Future<void> applySeedData(
  AppDatabase db, {
  required bool seed,
  String downloadBaseUrl = 'http://localhost:8080',
  VideoPathService? videoPathService,
  Dio? httpClient,
}) async {
  final videoSvc = videoPathService ?? VideoPathService();
  if (seed) {
    await MockDataSeeder(
      db,
      downloadBaseUrl: downloadBaseUrl,
      videoPathService: videoSvc,
      httpClient: httpClient,
    ).seed();
  } else {
    await _wipeToBaseData(db, videoSvc);
  }
}

Future<void> _wipeToBaseData(
  AppDatabase db,
  VideoPathService videoPathService,
) async {
  // Capture on-device past-match ids BEFORE the wipe so the video files can be
  // deleted afterwards — once the rows are gone the ids are unrecoverable.
  final onDeviceIds =
      await (db.select(db.teamMatchesTable)..where(
            (m) => m.kind.equals('past') & m.sizeMb.isBiggerThanValue(0),
          ))
          .get()
          .then((rows) => rows.map((r) => r.id).toList());

  await db.transaction(() async {
    await db.delete(db.clipsTable).go(); // cascade-deletes thumbnails
    await db.delete(db.teamMatchesTable).go();
    await db.delete(db.playersTable).go();
    await db.delete(db.teamsTable).go();
    await db.delete(db.streamingDestinationsTable).go();
    await db.delete(db.sportPresetsTable).go();
    await db.delete(db.usersTable).go();
  });
  // Re-seed the base scaffolding (default user + built-in presets) so provider
  // scopes that require an active user keep working. Pin to kDefaultUserId here
  // (dev/mock) so the emulator fixtures — which reference that id — line up.
  await db.seedBaseData(userId: kDefaultUserId);

  // Delete the on-device video files for the wiped past matches.
  for (final id in onDeviceIds) {
    final file = File(await videoPathService.recordingPath(id));
    if (!file.existsSync()) continue;
    try {
      await file.delete();
    } catch (e) {
      debugPrint('MockDataService: failed to delete video for $id: $e');
    }
  }
}

/// Seeds the Drift database with mock fixture data from the internal fixtures.
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
  MockDataSeeder(
    this._db, {
    this.downloadBaseUrl = 'http://localhost:8080',
    VideoPathService? videoPathService,
    Dio? httpClient,
  }) : _videoPathService = videoPathService ?? VideoPathService(),
       _httpClient = httpClient;

  final AppDatabase _db;

  /// Base URL of the mock WiFi download endpoint; on-device videos are fetched
  /// from `<downloadBaseUrl>/recordings/<matchId>`.
  final String downloadBaseUrl;
  final VideoPathService _videoPathService;
  final Dio? _httpClient;

  /// Seeds teams, players, matches, and streaming destinations from fixture
  /// JSON files.
  ///
  /// After all DB rows are written, placeholder video files are created for
  /// every past match with sizeMb > 0 so the Video Library can detect them.
  Future<void> seed() async {
    // Ensure the kDefaultUserId base user exists first. onCreate seeds the base
    // user with a RANDOM per-install uuid (prod identity), NOT kDefaultUserId —
    // but the team/destination fixtures reference kDefaultUserId, so without this
    // the teams insert hits a FOREIGN KEY failure (787) and the whole seed rolls
    // back (no dev/mock data). Idempotent, so safe on a pre-seeded DB.
    await _db.seedBaseData(userId: kDefaultUserId);

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
      (row) => row['kind'] == 'past' && (row['sizeMb'] as int? ?? 0) > 0,
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
    // Fetch over the live mock download path (container → bundled → sentinel)
    // so the seed video matches what the camera would actually serve.
    await fetchVideoOrFallback(
      url: joinBaseUrl(downloadBaseUrl, 'recordings/$matchId'),
      authToken: 'dev-token',
      savePath: path,
      httpClient: _httpClient,
    );
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
    await _db.batch(
      (b) => b.insertAllOnConflictUpdate(_db.teamsTable, companions),
    );
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
    await _db.batch(
      (b) => b.insertAllOnConflictUpdate(_db.playersTable, companions),
    );
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
    await _db.batch(
      (b) => b.insertAllOnConflictUpdate(_db.teamMatchesTable, companions),
    );
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
    final raw = await rootBundle.loadString(
      'lib/mock/internal/fixtures/$name.json',
    );
    // Strip lines that are purely // comments (JSON doesn't support comments).
    final stripped = raw
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    final parsed = jsonDecode(stripped) as List<dynamic>;
    return parsed.cast<Map<String, dynamic>>();
  }
}

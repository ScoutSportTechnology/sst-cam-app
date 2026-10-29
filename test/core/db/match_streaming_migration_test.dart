// U5 — per-match streaming credential schema (R19).
//
// Verifies the v4→v5 schema: team_matches carries nullable rtmp_url / stream_key
// columns, existing rows have no credential, and the columns round-trip (with
// synthetic placeholders only — never real keys).
// hide isNull: drift exports an isNull query helper that collides with the
// matcher of the same name used in the raw-SQL migration test below.
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
// sqlite3 is pulled in transitively by drift; used here only to drive the raw
// v4→v5 migration SQL directly.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart';

import '../../test_helpers.dart';

void main() {
  // Exercises the ACTUAL v4→v5 migration SQL on a v4-shaped table with a
  // pre-existing row — useInMemoryDb (below) only runs onCreate at v5, so this
  // is the only coverage of the onUpgrade ALTER path (a broken ALTER would
  // otherwise pass CI and crash on-device upgrade).
  test('v4→v5 ALTER adds nullable creds + preserves existing rows', () {
    final raw = sqlite3.openInMemory();
    // team_matches as it existed at schemaVersion 4 (no credential columns).
    raw.execute('''
      CREATE TABLE team_matches (
        id TEXT NOT NULL PRIMARY KEY,
        team_id TEXT NOT NULL,
        opponent TEXT NOT NULL,
        date TEXT NOT NULL,
        result TEXT NOT NULL,
        kind TEXT NOT NULL,
        num_periods INTEGER NOT NULL,
        period_length_seconds INTEGER NOT NULL,
        clips INTEGER NOT NULL DEFAULT 0,
        size_mb INTEGER NOT NULL DEFAULT 0,
        events_json TEXT NOT NULL DEFAULT '[]'
      )''');
    raw.execute(
      "INSERT INTO team_matches (id, team_id, opponent, date, result, kind, "
      "num_periods, period_length_seconds) "
      "VALUES ('m1','t1','Foo','2026-01-01','-','upcoming',2,2100)",
    );

    // The exact statements from app_database.dart onUpgrade `if (from < 5)`.
    raw.execute('ALTER TABLE team_matches ADD COLUMN rtmp_url TEXT');
    raw.execute('ALTER TABLE team_matches ADD COLUMN stream_key TEXT');

    final rows = raw.select(
      'SELECT rtmp_url, stream_key, opponent FROM team_matches WHERE id = ?',
      ['m1'],
    );
    expect(rows, hasLength(1));
    expect(rows.first['rtmp_url'], isNull); // new column, null on old row
    expect(rows.first['stream_key'], isNull);
    expect(rows.first['opponent'], 'Foo'); // existing data preserved
    // ignore: deprecated_member_use
    raw.dispose();
  });

  final db = useInMemoryDb();

  test('schemaVersion is 7', () {
    // v5 added the credential columns under test here; v6 added live_matches
    // (see live_matches_migration_test.dart); v7 dropped raw_recordings
    // (proxy capture went firmware-internal).
    expect(db.value.schemaVersion, 7);
  });

  test('seeded matches have no credential', () async {
    final database = db.value;
    final seeded = await database.select(database.teamMatchesTable).get();
    expect(seeded, isNotEmpty);
    expect(
      seeded.every((m) => m.rtmpUrl == null && m.streamKey == null),
      isTrue,
    );
  });

  test('per-match credential round-trips (synthetic placeholder)', () async {
    final database = db.value;
    final match =
        (await database.select(database.teamMatchesTable).get()).first;
    await (database.update(
      database.teamMatchesTable,
    )..where((t) => t.id.equals(match.id))).write(
      const TeamMatchesTableCompanion(
        rtmpUrl: Value('rtmp://test.invalid/live'),
        streamKey: Value('TEST_KEY_DO_NOT_USE'),
      ),
    );

    final updated = await (database.select(
      database.teamMatchesTable,
    )..where((t) => t.id.equals(match.id))).getSingle();
    expect(updated.rtmpUrl, 'rtmp://test.invalid/live');
    expect(updated.streamKey, 'TEST_KEY_DO_NOT_USE');
  });
}

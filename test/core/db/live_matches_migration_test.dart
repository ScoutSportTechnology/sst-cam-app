// v5→v6 migration — live_matches (persisted live-match scoreboard, U2).
//
// The in-memory test helper opens a FRESH database at the current
// schemaVersion and only ever runs onCreate — the onUpgrade ladder ships
// uncovered unless a test opens a REAL prior-version file (see
// docs/solutions/conventions/
// drift-migration-onupgrade-untested-by-inmemory-helper-2026-06-29.md).
// This test builds an on-disk v5 database by hand (user_version = 5 + the v5
// team_matches shape with a live row), opens AppDatabase over it so the
// actual `if (from < 6)` branch executes, and asserts the new table exists,
// the old data survived, and the version advanced.

import 'dart:io';

// hide isNull: drift exports an isNull query helper that collides with the
// matcher of the same name used below.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// sqlite3 is transitive via drift; used here only to build the v5 file.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart';
import 'package:sst_cam_app/core/db/app_database.dart';

void main() {
  test('v5→v6 onUpgrade creates live_matches on a real v5 file and preserves '
      'existing rows', () async {
    final dir = await Directory.systemTemp.createTemp('sst-cam-migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'app.sqlite'));

    // Hand-built v5 database: version pragma + team_matches at its v5 shape
    // (incl. the v5 credential columns) seeded with a pre-existing row.
    // onUpgrade only runs the `from < 6` branch, so no other table is needed.
    final raw = sqlite3.open(file.path);
    raw.execute('PRAGMA user_version = 5');
    raw.execute('''
      CREATE TABLE team_matches (
        id TEXT NOT NULL PRIMARY KEY, team_id TEXT NOT NULL,
        opponent TEXT NOT NULL, date TEXT NOT NULL, result TEXT NOT NULL,
        kind TEXT NOT NULL, num_periods INTEGER NOT NULL,
        period_length_seconds INTEGER NOT NULL,
        clips INTEGER NOT NULL DEFAULT 0, size_mb INTEGER NOT NULL DEFAULT 0,
        events_json TEXT NOT NULL DEFAULT '[]',
        rtmp_url TEXT, stream_key TEXT
      )''');
    raw.execute(
      "INSERT INTO team_matches (id, team_id, opponent, date, result, kind, "
      "num_periods, period_length_seconds) "
      "VALUES ('m1','t1','Foo','2026-01-01','-','upcoming',2,2100)",
    );
    // ignore: deprecated_member_use
    raw.dispose();

    // Opening the file at schemaVersion 6 triggers onUpgrade(5, 6) — the
    // exact production migration, not a paraphrase.
    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    // New table exists and is queryable (upsert + select round-trip).
    await db.customStatement(
      "INSERT INTO live_matches (device_id, match_uuid, phase) "
      "VALUES ('dev-1', 'match-1', 'period')",
    );
    final live = await db
        .customSelect('SELECT match_uuid, phase FROM live_matches')
        .get();
    expect(live, hasLength(1));
    expect(live.first.data['match_uuid'], 'match-1');
    expect(live.first.data['phase'], 'period');

    // Pre-existing data survived the upgrade.
    final rows = await db
        .customSelect(
          'SELECT opponent, rtmp_url FROM team_matches WHERE id = ?',
          variables: [Variable.withString('m1')],
        )
        .get();
    expect(rows, hasLength(1));
    expect(rows.first.data['opponent'], 'Foo');
    expect(rows.first.data['rtmp_url'], isNull);

    // Version advanced to the current schema.
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.single, 6);
  });
}

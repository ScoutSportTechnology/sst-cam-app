// Full onUpgrade ladder walk — every historical schema version → current.
//
// The in-memory test helper opens a FRESH database at the current
// schemaVersion and only ever runs onCreate — the onUpgrade ladder ships
// uncovered unless a test opens a REAL prior-version file (see
// docs/solutions/conventions/
// drift-migration-onupgrade-untested-by-inmemory-helper-2026-06-29.md).
//
// This test hand-builds an on-disk database at EVERY historical version
// (v1…v6), plants a consistent user→team→match→clip row chain, then opens
// AppDatabase over the file so the production onUpgrade(from, 7) actually
// executes. It asserts: the version advanced, ALL planted data survived
// (a migration must never nuke user data — the 2026-07 dev-boot wipe bug
// made "data survives a restart" a load-bearing invariant), the columns each
// branch adds exist, and the retired raw_recordings table is gone.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// sqlite3 is transitive via drift; used here only to build the version files.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/sqlite3.dart';
import 'package:sst_cam_app/core/db/app_database.dart';

/// Builds a real SQLite file at historical schema [version] (1–6), seeded
/// with one user, team, match, and clip. The SQL below is the fixture of
/// historical truth: v1 is the launch schema, each later version applies the
/// exact shape its migration produced at the time (including the retired
/// v3→v4 raw_recordings table, so the v6→v7 drop runs against a REAL table,
/// not just the IF EXISTS no-op).
void buildVersionFile(File file, int version) {
  final raw = sqlite3.open(file.path);
  raw.execute('PRAGMA user_version = $version');

  // --- v1 launch schema ---
  raw.execute('''
    CREATE TABLE users (
      id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL
    )''');
  raw.execute('''
    CREATE TABLE teams (
      id TEXT NOT NULL PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
      name TEXT NOT NULL, short_name TEXT NOT NULL, sport TEXT NOT NULL,
      hidden INTEGER NOT NULL DEFAULT 0
    )''');
  raw.execute('''
    CREATE TABLE players (
      team_id TEXT NOT NULL REFERENCES teams (id) ON DELETE CASCADE,
      number INTEGER NOT NULL, name TEXT NOT NULL, position TEXT NOT NULL,
      captain INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (team_id, number)
    )''');
  raw.execute('''
    CREATE TABLE team_matches (
      id TEXT NOT NULL PRIMARY KEY,
      team_id TEXT NOT NULL REFERENCES teams (id) ON DELETE CASCADE,
      opponent TEXT NOT NULL, date TEXT NOT NULL, result TEXT NOT NULL,
      kind TEXT NOT NULL, num_periods INTEGER NOT NULL,
      period_length_seconds INTEGER NOT NULL,
      clips INTEGER NOT NULL DEFAULT 0, size_mb INTEGER NOT NULL DEFAULT 0
    )''');
  raw.execute('''
    CREATE TABLE sport_presets (
      id TEXT NOT NULL,
      user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
      name TEXT NOT NULL, sport TEXT NOT NULL,
      num_periods INTEGER NOT NULL, period_length_seconds INTEGER NOT NULL,
      built_in INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (id, user_id)
    )''');
  raw.execute('''
    CREATE TABLE streaming_destinations (
      id TEXT NOT NULL PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
      name TEXT NOT NULL, provider TEXT NOT NULL, protocol TEXT NOT NULL,
      config_type TEXT NOT NULL, config_url TEXT NOT NULL,
      config_stream_key TEXT, config_username TEXT, config_password TEXT
    )''');
  raw.execute('''
    CREATE TABLE clips (
      id TEXT NOT NULL PRIMARY KEY,
      match_id TEXT NOT NULL REFERENCES team_matches (id) ON DELETE CASCADE,
      duration_seconds INTEGER NOT NULL, size_bytes INTEGER NOT NULL,
      started_at TEXT NOT NULL
    )''');
  raw.execute('''
    CREATE TABLE thumbnails (
      clip_id TEXT NOT NULL PRIMARY KEY
        REFERENCES clips (id) ON DELETE CASCADE,
      local_path TEXT NOT NULL
    )''');

  // --- historical deltas, mirroring what each migration produced ---
  if (version >= 2) {
    raw.execute(
      'ALTER TABLE clips ADD COLUMN start_seconds INTEGER NOT NULL DEFAULT 0',
    );
    raw.execute('ALTER TABLE clips ADD COLUMN label TEXT');
    raw.execute(
      "ALTER TABLE team_matches ADD COLUMN events_json TEXT NOT NULL "
      "DEFAULT '[]'",
    );
  }
  if (version >= 3) {
    raw.execute('ALTER TABLE teams ADD COLUMN color_hex TEXT');
  }
  if (version >= 4) {
    // Retired v3→v4 table — must exist in v4–v6 files so the v6→v7 DROP runs
    // against a populated table.
    raw.execute('''
      CREATE TABLE raw_recordings (
        id TEXT NOT NULL PRIMARY KEY,
        capture_group_id TEXT NOT NULL, camera_index INTEGER NOT NULL,
        match_id TEXT REFERENCES team_matches (id) ON DELETE CASCADE,
        local_path TEXT, size_bytes INTEGER NOT NULL DEFAULT 0,
        is_raw INTEGER NOT NULL DEFAULT 1
      )''');
    raw.execute(
      'CREATE INDEX idx_raw_recordings_capture_group_id '
      'ON raw_recordings(capture_group_id)',
    );
    raw.execute(
      "INSERT INTO raw_recordings (id, capture_group_id, camera_index) "
      "VALUES ('raw-1', 'grp-1', 0)",
    );
  }
  if (version >= 5) {
    raw.execute('ALTER TABLE team_matches ADD COLUMN rtmp_url TEXT');
    raw.execute('ALTER TABLE team_matches ADD COLUMN stream_key TEXT');
  }
  if (version >= 6) {
    raw.execute('''
      CREATE TABLE live_matches (
        device_id TEXT NOT NULL PRIMARY KEY,
        match_uuid TEXT NOT NULL, library_match_id TEXT,
        score_home INTEGER NOT NULL DEFAULT 0,
        score_away INTEGER NOT NULL DEFAULT 0,
        home_name TEXT NOT NULL DEFAULT '',
        away_name TEXT NOT NULL DEFAULT '',
        phase TEXT NOT NULL,
        timer_running INTEGER NOT NULL DEFAULT 0,
        rec_paused INTEGER NOT NULL DEFAULT 0,
        current_period INTEGER NOT NULL DEFAULT 0,
        num_periods INTEGER NOT NULL DEFAULT 2,
        period_length_seconds INTEGER NOT NULL DEFAULT 0,
        elapsed_seconds INTEGER NOT NULL DEFAULT 0,
        anchor_epoch_ms INTEGER,
        events_json TEXT NOT NULL DEFAULT '[]'
      )''');
  }

  // --- planted user data (must survive every migration) ---
  raw.execute("INSERT INTO users (id, name) VALUES ('u1', 'Coach')");
  raw.execute(
    "INSERT INTO teams (id, user_id, name, short_name, sport) "
    "VALUES ('t1', 'u1', 'Newton Rangers', 'NR', 'soccer')",
  );
  raw.execute(
    "INSERT INTO team_matches (id, team_id, opponent, date, result, kind, "
    "num_periods, period_length_seconds) "
    "VALUES ('m1', 't1', 'Foo', '2026-01-01', '2-1', 'past', 2, 2100)",
  );
  raw.execute(
    "INSERT INTO clips (id, match_id, duration_seconds, size_bytes, "
    "started_at) VALUES ('c1', 'm1', 30, 1024, '2026-01-01T10:00:00Z')",
  );
  // ignore: deprecated_member_use
  raw.dispose();
}

void main() {
  for (var from = 1; from <= 6; from++) {
    test('v$from→v7 onUpgrade on a real v$from file preserves all data and '
        'lands on the current schema', () async {
      final dir = await Directory.systemTemp.createTemp('sst-cam-walk');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'app.sqlite'));
      buildVersionFile(file, from);

      // Opening at the current schemaVersion triggers onUpgrade(from, 7) —
      // the exact production migration, not a paraphrase.
      final db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);

      // Force the open + migration, then check the version advanced.
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.single, 7);

      // Planted data survived — a migration must never nuke user data.
      final team = await db
          .customSelect("SELECT name, color_hex FROM teams WHERE id = 't1'")
          .getSingle();
      expect(team.data['name'], 'Newton Rangers');
      final match = await db
          .customSelect(
            "SELECT opponent, events_json, rtmp_url, stream_key "
            "FROM team_matches WHERE id = 'm1'",
          )
          .getSingle();
      expect(match.data['opponent'], 'Foo');
      expect(match.data['events_json'], '[]');
      final clip = await db
          .customSelect(
            "SELECT start_seconds, label FROM clips WHERE id = 'c1'",
          )
          .getSingle();
      expect(clip.data['start_seconds'], 0);
      final user = await db
          .customSelect("SELECT name FROM users WHERE id = 'u1'")
          .getSingle();
      expect(user.data['name'], 'Coach');

      // live_matches exists and is queryable at the v7 shape.
      await db.customStatement(
        "INSERT INTO live_matches (device_id, match_uuid, phase) "
        "VALUES ('dev-1', 'match-1', 'period')",
      );
      final live = await db
          .customSelect('SELECT match_uuid FROM live_matches')
          .get();
      expect(live, hasLength(1));

      // The retired raw_recordings table is gone (dropped for v4–v6 files
      // where it really existed; a no-op IF EXISTS for v1–v3 files).
      final rawTables = await db
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name = 'raw_recordings'",
          )
          .get();
      expect(rawTables, isEmpty);
    });
  }
}

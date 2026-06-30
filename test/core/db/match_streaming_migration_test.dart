// U5 — per-match streaming credential schema (R19).
//
// Verifies the v4→v5 schema: team_matches carries nullable rtmp_url / stream_key
// columns, existing rows have no credential, and the columns round-trip (with
// synthetic placeholders only — never real keys).
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

void main() {
  final db = useInMemoryDb();

  test('schemaVersion is 5', () {
    expect(db.value.schemaVersion, 5);
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

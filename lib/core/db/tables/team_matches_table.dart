import 'package:drift/drift.dart';

import 'teams_table.dart';

class TeamMatchesTable extends Table {
  @override
  String get tableName => 'team_matches';

  TextColumn get id => text()();
  TextColumn get teamId =>
      text().references(TeamsTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get opponent => text()();
  TextColumn get date => text()();
  TextColumn get result => text()();

  /// 'past' | 'upcoming'
  TextColumn get kind => text()();
  IntColumn get numPeriods => integer()();
  IntColumn get periodLengthSeconds => integer()();
  IntColumn get clips => integer().withDefault(const Constant(0))();
  IntColumn get sizeMb => integer().withDefault(const Constant(0))();

  /// JSON-encoded list of match events: [{timeSeconds, label, team, kind}].
  /// Empty array '[]' when no events recorded.
  TextColumn get eventsJson => text().withDefault(const Constant('[]'))();

  /// Per-match streaming credential (U5). Set at match setup or mid-match when
  /// streaming starts with no destination; scoped to this match only (never
  /// added to the global streaming_destinations list). Null when the match has
  /// no streaming credential. Stored plaintext (accepted risk; debug-signed
  /// builds are ADB-readable) and excluded from BackupService exports.
  TextColumn get rtmpUrl => text().nullable()();
  TextColumn get streamKey => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

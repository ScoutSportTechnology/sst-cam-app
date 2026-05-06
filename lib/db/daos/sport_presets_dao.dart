import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/sport_presets_table.dart';

part 'sport_presets_dao.g.dart';

@DriftAccessor(tables: [SportPresetsTable])
class SportPresetsDao extends DatabaseAccessor<AppDatabase>
    with _$SportPresetsDaoMixin {
  SportPresetsDao(super.db);

  /// Watch all presets for a user (built-in + custom) — emits on every
  /// mutation.
  Stream<List<SportPresetsTableData>> watchForUser(String userId) => (select(
    sportPresetsTable,
  )..where((p) => p.userId.equals(userId))).watch();

  /// One-shot fetch of all presets for a user.
  Future<List<SportPresetsTableData>> getForUser(String userId) =>
      (select(sportPresetsTable)..where((p) => p.userId.equals(userId))).get();

  /// One-shot fetch of a single preset, or null if not found.
  Future<SportPresetsTableData?> getById(String id) => (select(
    sportPresetsTable,
  )..where((p) => p.id.equals(id))).getSingleOrNull();

  /// Insert a new preset row.
  Future<void> insertPreset(SportPresetsTableCompanion companion) =>
      into(sportPresetsTable).insert(companion);

  /// Update an existing preset row.
  Future<bool> updatePreset(SportPresetsTableCompanion companion) =>
      update(sportPresetsTable).replace(companion);

  /// Delete a preset by id.
  Future<int> deleteById(String id) =>
      (delete(sportPresetsTable)..where((p) => p.id.equals(id))).go();

  /// Seed the seven built-in sport presets for [userId].
  ///
  /// Uses [insertOnConflictUpdate] so this is safe to call more than once —
  /// existing rows are updated in-place and no duplicates are created.
  ///
  /// The preset data mirrors [DevDataStore._builtInSportPresets()] exactly so
  /// that test data and production data stay in sync.
  Future<void> seedBuiltInsForUser(String userId) async {
    final presets = _builtInPresets(userId);
    await batch((b) {
      b.insertAllOnConflictUpdate(sportPresetsTable, presets);
    });
  }

  static List<SportPresetsTableCompanion> _builtInPresets(String userId) => [
    SportPresetsTableCompanion.insert(
      id: 'preset-soccer-std',
      userId: userId,
      name: 'Soccer · Standard',
      sport: 'Soccer',
      numPeriods: 2,
      periodLengthSeconds: 45 * 60,
      builtIn: const Value(true),
    ),
    SportPresetsTableCompanion.insert(
      id: 'preset-soccer-youth',
      userId: userId,
      name: 'Soccer · Youth (U14)',
      sport: 'Soccer',
      numPeriods: 2,
      periodLengthSeconds: 35 * 60,
      builtIn: const Value(true),
    ),
    SportPresetsTableCompanion.insert(
      id: 'preset-basketball-fiba',
      userId: userId,
      name: 'Basketball · FIBA',
      sport: 'Basketball',
      numPeriods: 4,
      periodLengthSeconds: 10 * 60,
      builtIn: const Value(true),
    ),
    SportPresetsTableCompanion.insert(
      id: 'preset-hockey-std',
      userId: userId,
      name: 'Hockey · Standard',
      sport: 'Hockey',
      numPeriods: 3,
      periodLengthSeconds: 20 * 60,
      builtIn: const Value(true),
    ),
    SportPresetsTableCompanion.insert(
      id: 'preset-volleyball-5set',
      userId: userId,
      name: 'Volleyball · 5-set',
      sport: 'Volleyball',
      numPeriods: 5,
      periodLengthSeconds: 25 * 60,
      builtIn: const Value(true),
    ),
    SportPresetsTableCompanion.insert(
      id: 'preset-rugby-std',
      userId: userId,
      name: 'Rugby · Standard',
      sport: 'Rugby',
      numPeriods: 2,
      periodLengthSeconds: 40 * 60,
      builtIn: const Value(true),
    ),
    SportPresetsTableCompanion.insert(
      id: 'preset-other-single',
      userId: userId,
      name: 'Other · Single period',
      sport: 'Other',
      numPeriods: 1,
      periodLengthSeconds: 30 * 60,
      builtIn: const Value(true),
    ),
  ];
}

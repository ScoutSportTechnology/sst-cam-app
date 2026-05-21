// Sport presets state — saved per-user time configs grouped by base sport.
// Picked at match-schedule time to materialize a match's periods.
// Backed by Drift (U6); no camera connection required for reads or writes.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart'
    show SportPresetsTableData, SportPresetsTableCompanion;
import '../../../core/models/sport_preset.dart';
import '../../../core/state/db_providers.dart';
import '../users/users_state.dart' show activeUserProvider;

export '../../../core/models/sport_preset.dart';

const _uuid = Uuid();

/// Typed exception for [SportPresetsController] UI-rule violations (e.g.
/// attempting to edit or delete a built-in preset).
class SportPresetsControllerException implements Exception {
  const SportPresetsControllerException(this.message);
  final String message;

  @override
  String toString() => 'SportPresetsControllerException: $message';
}

SportPreset _rowToSportPreset(SportPresetsTableData row) => SportPreset(
  id: row.id,
  name: row.name,
  sport: row.sport,
  numPeriods: row.numPeriods,
  periodLengthSeconds: row.periodLengthSeconds,
  builtIn: row.builtIn,
);

class SportPresetsController extends AsyncNotifier<List<SportPreset>> {
  @override
  Future<List<SportPreset>> build() async {
    final userId = ref.watch(activeUserProvider);
    if (userId == null) return const [];

    final dao = ref.watch(sportPresetsDaoProvider);

    // Subscribe to watch stream for live updates. Skip the first tick to avoid
    // a redundant rebuild (the initial snapshot is returned below).
    bool first = true;
    final sub = dao
        .watchForUser(userId)
        .listen(
          (rows) {
            if (first) {
              first = false;
              return;
            }
            state = AsyncValue.data(rows.map(_rowToSportPreset).toList());
          },
          onError: (Object e, StackTrace st) {
            state = AsyncValue.error(e, st);
          },
        );
    ref.onDispose(sub.cancel);

    // Initial snapshot.
    final rows = await dao.getForUser(userId);
    return rows.map(_rowToSportPreset).toList();
  }

  String _requireActiveUser() {
    final userId = ref.read(activeUserProvider);
    if (userId == null) throw StateError('No active user');
    return userId;
  }

  Future<SportPreset> create(SportPresetDraft draft) async {
    final userId = _requireActiveUser();
    final id = _uuid.v4();
    final dao = ref.read(sportPresetsDaoProvider);
    await dao.insertPreset(
      SportPresetsTableCompanion.insert(
        id: id,
        userId: userId,
        name: draft.name,
        sport: draft.sport,
        numPeriods: draft.numPeriods,
        periodLengthSeconds: draft.periodLengthSeconds,
        builtIn: const Value(false),
      ),
    );
    return SportPreset(
      id: id,
      name: draft.name,
      sport: draft.sport,
      numPeriods: draft.numPeriods,
      periodLengthSeconds: draft.periodLengthSeconds,
    );
  }

  Future<void> edit(SportPresetDraft draft) async {
    final userId = _requireActiveUser();
    final dao = ref.read(sportPresetsDaoProvider);
    final existing = await dao.getById(draft.id);
    if (existing == null) {
      throw SportPresetsControllerException('Preset ${draft.id} not found');
    }
    if (existing.builtIn) {
      throw const SportPresetsControllerException(
        'Built-in presets cannot be edited',
      );
    }
    await dao.updatePreset(
      SportPresetsTableCompanion.insert(
        id: draft.id,
        userId: userId,
        name: draft.name,
        sport: draft.sport,
        numPeriods: draft.numPeriods,
        periodLengthSeconds: draft.periodLengthSeconds,
        builtIn: const Value(false),
      ),
    );
  }

  Future<void> delete(String presetId) async {
    final dao = ref.read(sportPresetsDaoProvider);
    final existing = await dao.getById(presetId);
    if (existing == null) {
      throw SportPresetsControllerException('Preset $presetId not found');
    }
    if (existing.builtIn) {
      throw const SportPresetsControllerException(
        'Built-in presets cannot be deleted',
      );
    }
    await dao.deleteById(presetId);
  }
}

final sportPresetsControllerProvider =
    AsyncNotifierProvider<SportPresetsController, List<SportPreset>>(
      SportPresetsController.new,
    );

/// Sport presets filtered to a given base sport (e.g. team's sport).
final sportPresetsForSportProvider = Provider.family<List<SportPreset>, String>(
  (ref, sport) {
    final all =
        ref.watch(sportPresetsControllerProvider).valueOrNull ?? const [];
    return all.where((p) => p.sport == sport).toList();
  },
);

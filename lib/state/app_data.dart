// Local app data — library, live match state, team controller.
//
// Users, streaming destinations, teams, rosters, upcoming matches, and sport
// presets are all owned by the local Drift DB.
// Library is backed by the Drift DB (TeamMatchesTable); libraryProvider
// queries past matches. LiveMatch state is polled from the BLE service.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../db/daos/streaming_destinations_dao.dart';
import '../db/daos/teams_dao.dart';
import '../models/sport_preset.dart';
import '../models/streaming.dart';
import '../models/team.dart';
import '../models/user.dart';
import 'db_providers.dart';

export '../models/sport_preset.dart';
export '../models/streaming.dart';
export '../models/team.dart';
export '../models/user.dart';

class LibraryEvent {
  const LibraryEvent({
    required this.timeSeconds,
    required this.label,
    required this.team,
    required this.kind,
  });
  final int timeSeconds;
  final String label;
  final String team;
  final String kind; // goal, foul, card, sub, save, other
  String get clock {
    final m = (timeSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (timeSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class LibraryMatch {
  const LibraryMatch({
    required this.id,
    required this.teamId,
    required this.date,
    required this.opponent,
    required this.result,
    required this.fullDuration,
    required this.fullSizeMb,
    required this.events,
    required this.downloadState,
  });
  final String id;
  final String teamId;
  final String date;
  final String opponent;
  final String result;
  final String fullDuration; // 01:23:42
  final int fullSizeMb;
  final List<LibraryEvent> events;
  final String downloadState; // 'all-local', 'partial', 'remote'
}

// ---------------------------------------------------------------------------
// Camera handle — `activeCameraIdProvider` is set by the discovery flow on a
// successful connect and cleared on disconnect. Team/match data now comes from
// Drift (U5); this provider remains for camera-connected UI (settings header,
// telemetry) until U7 removes remaining device gates.
// ---------------------------------------------------------------------------

final activeCameraIdProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// Active user — single source of truth on the app side. Hydrated from
// SharedPreferences in `UsersController.build()`. Per-user-scoped controllers
// (teams, sport presets, streaming destinations) watch this provider so they
// rebuild on user switch.
//
// `upcomingMatchesProvider` does NOT watch this — it has no userId arg, and
// is invalidated explicitly by `UsersController.setActive` instead.
// ---------------------------------------------------------------------------

final activeUserProvider = StateProvider<String?>((_) => null);

const _kActiveUserIdKey = 'active_user_id';

const _uuid = Uuid();

/// Typed exception for `UsersController` UI-rule pre-checks. Surfaced to the
/// UI so the user / form layers can render an inline message rather than
/// letting the BLE call fail noisily.
class UsersControllerException implements Exception {
  const UsersControllerException(this.message);
  final String message;

  @override
  String toString() => 'UsersControllerException: $message';
}

class UsersController extends AsyncNotifier<List<UserRecord>> {
  @override
  Future<List<UserRecord>> build() async {
    final dao = ref.watch(usersDaoProvider);

    // Hydrate active user from SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_kActiveUserIdKey);
    if (savedId != null) {
      final exists = await dao.getUserById(savedId);
      if (exists != null) {
        ref.read(activeUserProvider.notifier).state = savedId;
      } else {
        await prefs.remove(_kActiveUserIdKey);
      }
    }

    // Auto-select the only user on first launch or after the saved user was
    // deleted — avoids a blank-screen state where all per-user data is empty.
    if (ref.read(activeUserProvider) == null) {
      final all = await dao.getAll();
      if (all.length == 1) {
        final onlyId = all.first.id;
        ref.read(activeUserProvider.notifier).state = onlyId;
        await prefs.setString(_kActiveUserIdKey, onlyId);
      }
    }

    // Subscribe to watch stream for all mutations. The listener may fire once
    // with the same data as the initial snapshot below; that is acceptable.
    final sub = dao.watchAll().listen(
      (rows) {
        state = AsyncValue.data(_toUserRecords(rows));
      },
      onError: (Object e, StackTrace st) {
        state = AsyncValue.error(e, st);
      },
    );
    ref.onDispose(sub.cancel);

    // Return initial snapshot.
    return _toUserRecords(await dao.getAll());
  }

  static List<UserRecord> _toUserRecords(List<UsersTableData> rows) =>
      rows.map((r) => UserRecord(id: r.id, name: r.name)).toList();

  Future<UserRecord> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const UsersControllerException('User name is required');
    }
    final userId = _uuid.v4();
    final dao = ref.read(usersDaoProvider);
    await dao.insertUser(UsersTableCompanion.insert(id: userId, name: trimmed));

    // Seed built-in sport presets for this user.
    await ref.read(sportPresetsDaoProvider).seedBuiltInsForUser(userId);

    // If no active user yet, auto-activate the first user.
    if (ref.read(activeUserProvider) == null) {
      ref.read(activeUserProvider.notifier).state = userId;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kActiveUserIdKey, userId);
    }

    return UserRecord(id: userId, name: trimmed);
  }

  Future<void> rename(String userId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const UsersControllerException('User name is required');
    }
    await ref
        .read(usersDaoProvider)
        .updateUser(UsersTableCompanion.insert(id: userId, name: trimmed));
  }

  /// Switch the active user. Writes SharedPreferences then updates the
  /// provider. `upcomingMatchesProvider` rebuilds automatically because
  /// TeamsController (which feeds it) watches `activeUserProvider`.
  Future<void> setActive(String userId) async {
    if (userId == ref.read(activeUserProvider)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveUserIdKey, userId); // persist first
    ref.read(activeUserProvider.notifier).state =
        userId; // then update in-memory
  }

  /// Restore the active user after a backup import. Writes to SharedPreferences
  /// and updates [activeUserProvider]. Pass null to clear the active user.
  ///
  /// Fix 11: Centralises the SharedPreferences write that was previously
  /// duplicated in settings_page.dart's restore handler.
  Future<void> restoreActive(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId != null) {
      ref.read(activeUserProvider.notifier).state = userId;
      await prefs.setString(_kActiveUserIdKey, userId);
    } else {
      ref.read(activeUserProvider.notifier).state = null;
      await prefs.remove(_kActiveUserIdKey);
    }
  }

  /// Delete a user. UI-rule pre-checks raise [UsersControllerException]
  /// BEFORE touching the DB so the form can render an inline message and
  /// no DB state is touched on a UI-rule violation.
  Future<void> delete(String userId) async {
    final users = state.valueOrNull ?? const [];
    final activeUserId = ref.read(activeUserProvider);
    if (userId == activeUserId) {
      throw const UsersControllerException('Cannot delete the active user');
    }
    if (users.length <= 1) {
      throw const UsersControllerException('At least one user must remain');
    }
    // Block delete while any match is live.
    if (isLiveMatchRunning(ref.read(liveMatchProvider))) {
      throw const UsersControllerException(
        'End the live match before deleting',
      );
    }

    // FK cascade removes all owned teams / presets / destinations.
    await ref.read(usersDaoProvider).deleteById(userId);
  }
}

final usersControllerProvider =
    AsyncNotifierProvider<UsersController, List<UserRecord>>(
      UsersController.new,
    );

// ---------------------------------------------------------------------------
// Streaming destinations — per-user list. `userId` is passed explicitly to
// every BleService call (sourced from `activeUserProvider`); when no user
// is active, `build()` returns empty without making a BLE call.
// ---------------------------------------------------------------------------

class StreamingDestinationsController
    extends AsyncNotifier<List<StreamingDestination>> {
  String _requireActiveUser() {
    final activeUserId = ref.read(activeUserProvider);
    if (activeUserId == null) {
      throw StateError('No active user');
    }
    return activeUserId;
  }

  @override
  Future<List<StreamingDestination>> build() async {
    final activeUserId = ref.watch(activeUserProvider);
    if (activeUserId == null) return const [];

    final dao = ref.watch(streamingDestinationsDaoProvider);

    // Subscribe to all mutations. The listener may fire once with the same
    // data as the initial snapshot below; that is acceptable.
    final sub = dao
        .watchForUser(activeUserId)
        .listen(
          (rows) {
            state = AsyncValue.data(_toDestinations(rows));
          },
          onError: (Object e, StackTrace st) {
            state = AsyncValue.error(e, st);
          },
        );
    ref.onDispose(sub.cancel);

    return _toDestinations(await dao.getForUser(activeUserId));
  }

  static List<StreamingDestination> _toDestinations(
    List<StreamingDestinationsTableData> rows,
  ) => rows
      .map(
        (r) => StreamingDestination(
          id: r.id,
          name: r.name,
          provider: StreamingProvider.values.byName(r.provider),
          protocol: StreamingProtocol.values.byName(r.protocol),
          config: StreamingDestinationsDao.configFromRow(r),
        ),
      )
      .toList();

  StreamingDestinationsTableCompanion _draftToCompanion(
    String id,
    String userId,
    StreamingDestinationDraft draft,
  ) {
    final config = draft.config;
    return switch (config) {
      RtmpConfig() => StreamingDestinationsTableCompanion.insert(
        id: id,
        userId: userId,
        name: draft.name,
        provider: draft.provider.name,
        protocol: draft.protocol.name,
        configType: 'rtmp',
        configUrl: config.url,
        configStreamKey: Value(config.streamKey),
        configUsername: const Value(null),
        configPassword: const Value(null),
      ),
      RtspConfig() => StreamingDestinationsTableCompanion.insert(
        id: id,
        userId: userId,
        name: draft.name,
        provider: draft.provider.name,
        protocol: draft.protocol.name,
        configType: 'rtsp',
        configUrl: config.url,
        configStreamKey: const Value(null),
        configUsername: Value(config.username),
        configPassword: Value(config.password),
      ),
    };
  }

  Future<StreamingDestination> create(StreamingDestinationDraft draft) async {
    final userId = _requireActiveUser();
    final id = _uuid.v4();
    final companion = _draftToCompanion(id, userId, draft);
    await ref
        .read(streamingDestinationsDaoProvider)
        .insertDestination(companion);
    final config = draft.config;
    return StreamingDestination(
      id: id,
      name: draft.name,
      provider: draft.provider,
      protocol: draft.protocol,
      config: config,
    );
  }

  Future<StreamingDestination> edit(StreamingDestinationDraft draft) async {
    final userId = _requireActiveUser();
    final companion = _draftToCompanion(draft.id, userId, draft);
    await ref
        .read(streamingDestinationsDaoProvider)
        .updateDestination(companion);
    return StreamingDestination(
      id: draft.id,
      name: draft.name,
      provider: draft.provider,
      protocol: draft.protocol,
      config: draft.config,
    );
  }

  Future<void> delete(String destinationId) async {
    await ref.read(streamingDestinationsDaoProvider).deleteById(destinationId);
  }
}

final streamingDestinationsControllerProvider =
    AsyncNotifierProvider<
      StreamingDestinationsController,
      List<StreamingDestination>
    >(StreamingDestinationsController.new);

// ---------------------------------------------------------------------------
// Teams — controller + filter providers. The controller is the only writer;
// UI mutates by calling its methods.
//
// Design note (U5): `AsyncNotifier` is kept (rather than `StreamNotifier`)
// because write methods need to be on the same class as `build()`. The pattern
// mirrors `UsersController`: get initial snapshot, subscribe to watch stream
// for mutations, push subsequent emissions into `state` via a listener. No
// `_refresh()` calls — Drift emits on every mutation automatically.
// ---------------------------------------------------------------------------

/// Convert a raw [TeamsTableData] row and its [PlayersTableData] list into the
/// app-model [TeamRecord].
TeamRecord _rowToTeamRecord(TeamsTableData t, List<PlayersTableData> players) =>
    TeamRecord(
      id: t.id,
      name: t.name,
      shortName: t.shortName,
      sport: t.sport,
      hidden: t.hidden,
      roster: players.map(_rowToPlayer).toList(),
    );

Player _rowToPlayer(PlayersTableData p) => Player(
  number: p.number,
  name: p.name,
  position: p.position,
  captain: p.captain,
);

/// Convert a raw [TeamMatchesTableData] row into the app-model [TeamMatch].
TeamMatch _rowToTeamMatch(TeamMatchesTableData m) => TeamMatch(
  id: m.id,
  opponent: m.opponent,
  date: m.date,
  result: m.result,
  kind: m.kind == 'upcoming' ? MatchKind.upcoming : MatchKind.past,
  numPeriods: m.numPeriods,
  periodLengthSeconds: m.periodLengthSeconds,
  clips: m.clips,
  sizeMb: m.sizeMb,
);

class TeamsController extends AsyncNotifier<List<TeamRecord>> {
  String _requireActiveUser() {
    final userId = ref.read(activeUserProvider);
    if (userId == null) throw StateError('No active user');
    return userId;
  }

  @override
  Future<List<TeamRecord>> build() async {
    final userId = ref.watch(activeUserProvider);
    if (userId == null) return const [];

    final dao = ref.watch(teamsDaoProvider);

    // Fix 7: Subscribe to both teamsTable and playersTable so roster mutations
    // also invalidate the stream. Skip the very first emission from each stream
    // to avoid double-building on startup (the initial snapshot is returned
    // below).
    bool firstTeam = true;
    final teamSub = dao
        .watchForUser(userId)
        .listen(
          (rows) async {
            if (firstTeam) {
              firstTeam = false;
              return;
            }
            final records = await _buildRecords(dao, rows);
            state = AsyncValue.data(records);
          },
          onError: (Object e, StackTrace st) {
            state = AsyncValue.error(e, st);
          },
        );
    ref.onDispose(teamSub.cancel);

    bool firstPlayer = true;
    final playerSub = dao.watchAllPlayers().listen(
      (_) async {
        if (firstPlayer) {
          firstPlayer = false;
          return;
        }
        try {
          final rows = await dao.getForUser(userId);
          state = AsyncValue.data(await _buildRecords(dao, rows));
        } catch (e, st) {
          state = AsyncValue.error(e, st);
        }
      },
      onError: (Object e, StackTrace st) {
        state = AsyncValue.error(e, st);
      },
    );
    ref.onDispose(playerSub.cancel);

    // Initial snapshot.
    final rows = await dao.getForUser(userId);
    return _buildRecords(dao, rows);
  }

  /// Bulk-fetch players for all teams and assemble [TeamRecord] list.
  ///
  /// Uses a single bulk query instead of one-per-team to avoid N+1 queries
  /// (Fix 6).
  Future<List<TeamRecord>> _buildRecords(
    TeamsDao dao,
    List<TeamsTableData> rows,
  ) async {
    if (rows.isEmpty) return const [];
    final teamIds = rows.map((r) => r.id).toList();
    final allPlayers = await dao.getPlayersForTeams(teamIds);
    final playersByTeam = <String, List<PlayersTableData>>{};
    for (final p in allPlayers) {
      playersByTeam.putIfAbsent(p.teamId, () => []).add(p);
    }
    return rows
        .map((r) => _rowToTeamRecord(r, playersByTeam[r.id] ?? const []))
        .toList();
  }

  Future<TeamRecord> create(TeamDraft draft) async {
    final userId = _requireActiveUser();
    final dao = ref.read(teamsDaoProvider);
    final id = _uuid.v4();
    await dao.insertTeam(
      TeamsTableCompanion.insert(
        id: id,
        userId: userId,
        name: draft.name.trim(),
        shortName: draft.shortName.trim(),
        sport: draft.sport,
      ),
    );
    return TeamRecord(
      id: id,
      name: draft.name.trim(),
      shortName: draft.shortName.trim(),
      sport: draft.sport,
      roster: const [],
    );
  }

  Future<void> edit(TeamDraft draft) async {
    final userId = _requireActiveUser();
    final dao = ref.read(teamsDaoProvider);
    await dao.updateTeam(
      TeamsTableCompanion.insert(
        id: draft.id,
        userId: userId,
        name: draft.name.trim(),
        shortName: draft.shortName.trim(),
        sport: draft.sport,
      ),
    );
  }

  Future<void> delete(String teamId) async {
    await ref.read(teamsDaoProvider).deleteTeamById(teamId);
    // FK cascade removes players and team_matches automatically.
    // upcomingMatchesProvider rebuilds automatically via its Drift stream.
  }

  Future<void> setHidden(String teamId, {required bool hidden}) async {
    final dao = ref.read(teamsDaoProvider);
    await dao.setTeamHidden(teamId, hidden);
  }

  Future<void> addPlayer(String teamId, PlayerDraft draft) async {
    await ref
        .read(teamsDaoProvider)
        .insertPlayer(
          PlayersTableCompanion.insert(
            teamId: teamId,
            number: draft.number,
            name: draft.name,
            position: draft.position,
            captain: Value(draft.captain),
          ),
        );
  }

  Future<void> updatePlayer(
    String teamId,
    int currentNumber,
    PlayerDraft draft,
  ) async {
    final dao = ref.read(teamsDaoProvider);
    // Fix 8: Wrap delete + re-insert in a transaction so the operation is
    // atomic — no window where the player row is absent.
    await ref.read(appDatabaseProvider).transaction(() async {
      await dao.deletePlayer(teamId, currentNumber);
      await dao.insertPlayer(
        PlayersTableCompanion.insert(
          teamId: teamId,
          number: draft.number,
          name: draft.name,
          position: draft.position,
          captain: Value(draft.captain),
        ),
      );
    });
  }

  Future<void> removePlayer(String teamId, int number) async {
    await ref.read(teamsDaoProvider).deletePlayer(teamId, number);
  }

  Future<TeamMatch> addMatch(String teamId, TeamMatchDraft draft) async {
    final dao = ref.read(teamsDaoProvider);
    final id = draft.id.isEmpty ? _uuid.v4() : draft.id;
    await dao.insertTeamMatch(
      TeamMatchesTableCompanion.insert(
        id: id,
        teamId: teamId,
        opponent: draft.opponent,
        date: draft.date,
        result: draft.result,
        kind: draft.kind == MatchKind.upcoming ? 'upcoming' : 'past',
        numPeriods: draft.numPeriods,
        periodLengthSeconds: draft.periodLengthSeconds,
      ),
    );
    // teamMatchesProvider and upcomingMatchesProvider rebuild automatically
    // via their Drift watch streams.
    return TeamMatch(
      id: id,
      opponent: draft.opponent,
      date: draft.date,
      result: draft.result,
      kind: draft.kind,
      numPeriods: draft.numPeriods,
      periodLengthSeconds: draft.periodLengthSeconds,
      clips: 0,
      sizeMb: 0,
    );
  }

  Future<void> removeMatch(String teamId, String matchId) async {
    await ref.read(teamsDaoProvider).deleteTeamMatch(matchId);
    // teamMatchesProvider and upcomingMatchesProvider rebuild automatically.
  }
}

final teamsControllerProvider =
    AsyncNotifierProvider<TeamsController, List<TeamRecord>>(
      TeamsController.new,
    );

/// Per-team match list — live stream backed by Drift. Emits on every mutation
/// to the team_matches table for the given team. No camera connection required.
final teamMatchesProvider = StreamProvider.family<List<TeamMatch>, String>((
  ref,
  teamId,
) {
  return ref
      .watch(teamsDaoProvider)
      .watchTeamMatches(teamId)
      .map((rows) => rows.map(_rowToTeamMatch).toList());
});

/// Joined view of an upcoming match with its owning team — used by the
/// Match tab landing list. Built by [upcomingMatchesProvider]; not stored.
@immutable
class UpcomingMatch {
  const UpcomingMatch({required this.team, required this.match});
  final TeamRecord team;
  final TeamMatch match;
}

/// All upcoming matches across all non-hidden teams for the active user,
/// ordered ascending by date. Backed by a Drift JOIN watch stream — emits on
/// every mutation to teamMatchesTable or teamsTable. No camera connection
/// required (R2 fix, U2).
final upcomingMatchesProvider = StreamProvider<List<UpcomingMatch>>((ref) {
  final userId = ref.watch(activeUserProvider);
  if (userId == null) return Stream.value(const []);
  final dao = ref.watch(teamsDaoProvider);
  return dao
      .watchUpcomingMatchesForUser(userId)
      .map((rows) => rows.map(_rowToUpcomingMatch).toList());
});

UpcomingMatch _rowToUpcomingMatch(UpcomingMatchRow row) => UpcomingMatch(
  team: _rowToTeamRecord(row.team, const []),
  match: _rowToTeamMatch(row.match),
);

// ---------------------------------------------------------------------------
// Sport setups (presets) — saved per-user time configs grouped by base
// sport. Picked at match-schedule time to materialize a match's periods.
// Backed by Drift (U6); no camera connection required for reads or writes.
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Filter / search state for the Teams page.
// ---------------------------------------------------------------------------

final teamsSearchQueryProvider = StateProvider<String>((_) => '');
final teamsSportFilterProvider = StateProvider<String?>(
  (_) => null,
); // null = All
final teamsShowHiddenProvider = StateProvider<bool>((_) => false);

final sportPresetsFilterProvider = StateProvider<String?>(
  (_) => null,
); // null = All

/// Sports actually present in the current team set, in `kSports` order.
/// Used to drive the filter chip row so we never show a chip with zero teams.
final availableSportsProvider = Provider<List<String>>((ref) {
  final teams = ref.watch(teamsControllerProvider).valueOrNull ?? const [];
  final present = teams.map((t) => t.sport).toSet();
  return kSports.where(present.contains).toList();
});

/// Teams after applying search + sport filter + hidden toggle.
final filteredTeamsProvider = Provider<List<TeamRecord>>((ref) {
  final teams = ref.watch(teamsControllerProvider).valueOrNull ?? const [];
  final query = ref.watch(teamsSearchQueryProvider).trim().toLowerCase();
  final sport = ref.watch(teamsSportFilterProvider);
  final showHidden = ref.watch(teamsShowHiddenProvider);

  return teams.where((t) {
    if (!showHidden && t.hidden) return false;
    if (sport != null && t.sport != sport) return false;
    if (query.isEmpty) return true;
    return t.name.toLowerCase().contains(query) ||
        t.shortName.toLowerCase().contains(query);
  }).toList();
});

// ---------------------------------------------------------------------------
// Filter / search state for the Match landing page.
// ---------------------------------------------------------------------------

final upcomingSearchQueryProvider = StateProvider<String>((_) => '');
final upcomingMatchSportFilterProvider = StateProvider<String?>((_) => null); // null = All

final filteredUpcomingMatchesProvider = Provider<List<UpcomingMatch>>((ref) {
  final matches = ref.watch(upcomingMatchesProvider).valueOrNull ?? const [];
  final query = ref.watch(upcomingSearchQueryProvider).trim().toLowerCase();
  final sport = ref.watch(upcomingMatchSportFilterProvider);
  return matches.where((m) {
    if (sport != null && m.team.sport != sport) return false;
    if (query.isEmpty) return true;
    return m.team.name.toLowerCase().contains(query) ||
        m.match.opponent.toLowerCase().contains(query);
  }).toList();
});

// ---------------------------------------------------------------------------
// Filter / search state for the Library (Video) page.
// ---------------------------------------------------------------------------

final librarySearchQueryProvider = StateProvider<String>((_) => '');
final librarySportFilterProvider = StateProvider<String?>((_) => null); // null = All

/// Sports actually present in the current library set, in `kSports` order.
final availableLibrarySportsProvider = Provider<List<String>>((ref) {
  final library = ref.watch(libraryProvider).valueOrNull ?? const [];
  final teams = ref.watch(teamsControllerProvider).valueOrNull ?? const [];
  final teamMap = {for (final t in teams) t.id: t};
  final present = library
      .map((m) => teamMap[m.teamId]?.sport)
      .whereType<String>()
      .toSet();
  return kSports.where(present.contains).toList();
});

/// Teams that have at least one local library entry, after applying search +
/// sport filter.
final filteredLibraryTeamsProvider = Provider<List<TeamRecord>>((ref) {
  final library = ref.watch(libraryProvider).valueOrNull ?? const [];
  final teams = ref.watch(teamsControllerProvider).valueOrNull ?? const [];
  final query = ref.watch(librarySearchQueryProvider).trim().toLowerCase();
  final sport = ref.watch(librarySportFilterProvider);

  // Build set of team IDs that have local library entries.
  final presentIds = library
      .where((m) => m.downloadState != 'remote')
      .map((m) => m.teamId)
      .toSet();

  return teams.where((t) {
    if (!presentIds.contains(t.id)) return false;
    if (sport != null && t.sport != sport) return false;
    if (query.isEmpty) return true;
    return t.name.toLowerCase().contains(query) ||
        t.shortName.toLowerCase().contains(query);
  }).toList();
});

// ---------------------------------------------------------------------------
// Library — backed by TeamMatchesTable joined with TeamsTable.
// Emits the current list of past matches with events parsed from eventsJson.
// ---------------------------------------------------------------------------

final libraryProvider = StreamProvider<List<LibraryMatch>>((ref) {
  final dao = ref.watch(teamsDaoProvider);
  return dao.watchPastMatchesForLibrary().map((rows) => rows.map(_rowToLibraryMatch).toList());
});

LibraryMatch _rowToLibraryMatch(LibraryMatchRow row) {
  final match = row.match;
  final team = row.team;

  // Derive download state from size: sizeMb > 0 means content is available.
  final downloadState = match.sizeMb > 0 ? 'all-local' : 'remote';

  // Format duration: numPeriods × periodLengthSeconds → HH:MM:SS.
  final totalSec = match.numPeriods * match.periodLengthSeconds;
  final h = (totalSec ~/ 3600).toString().padLeft(2, '0');
  final m = ((totalSec % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (totalSec % 60).toString().padLeft(2, '0');
  final fullDuration = '$h:$m:$s';

  // Parse events from JSON stored in eventsJson column.
  final events = _parseEvents(match.eventsJson);

  return LibraryMatch(
    id: match.id,
    teamId: team.id,
    date: match.date,
    opponent: match.opponent,
    result: match.result,
    fullDuration: fullDuration,
    fullSizeMb: match.sizeMb,
    events: events,
    downloadState: downloadState,
  );
}

List<LibraryEvent> _parseEvents(String eventsJson) {
  try {
    final raw = jsonDecode(eventsJson) as List<dynamic>;
    return raw.map((e) {
      final m = e as Map<String, dynamic>;
      return LibraryEvent(
        timeSeconds: m['timeSeconds'] as int,
        label: m['label'] as String,
        team: m['team'] as String,
        kind: m['kind'] as String,
      );
    }).toList();
  } catch (_) {
    return const [];
  }
}

final libraryMatchProvider = Provider.family<LibraryMatch?, String>((ref, id) {
  final library = ref.watch(libraryProvider).valueOrNull ?? const [];
  return library.where((m) => m.id == id).firstOrNull;
});

// ---------------------------------------------------------------------------
// Filter / search state for the Video library page.
// ---------------------------------------------------------------------------

final librarySearchQueryProvider = StateProvider<String>((_) => '');
final librarySportFilterProvider = StateProvider<String?>(
  (_) => null,
); // null = All

/// Sports actually present in the local library (non-remote matches), in
/// `kSports` order. Used to drive the filter chip row.
final availableLibrarySportsProvider = Provider<List<String>>((ref) {
  final teams = ref.watch(teamsControllerProvider).valueOrNull ?? const [];
  final library = (ref.watch(libraryProvider).valueOrNull ?? const [])
      .where((m) => m.downloadState != 'remote')
      .toList();
  final teamIdsInLibrary = library.map((m) => m.teamId).toSet();
  final present = teams
      .where((t) => teamIdsInLibrary.contains(t.id))
      .map((t) => t.sport)
      .toSet();
  return kSports.where(present.contains).toList();
});

/// Teams with at least one local library entry, after applying search + sport
/// filter. Used by [VideoPage] to drive the team list.
final filteredLibraryTeamsProvider = Provider<List<TeamRecord>>((ref) {
  final teams = ref.watch(teamsControllerProvider).valueOrNull ?? const [];
  final library = (ref.watch(libraryProvider).valueOrNull ?? const [])
      .where((m) => m.downloadState != 'remote')
      .toList();
  final teamIdsInLibrary = library.map((m) => m.teamId).toSet();
  final query = ref.watch(librarySearchQueryProvider).trim().toLowerCase();
  final sport = ref.watch(librarySportFilterProvider);

  return teams.where((t) {
    if (!teamIdsInLibrary.contains(t.id)) return false;
    if (sport != null && t.sport != sport) return false;
    if (query.isEmpty) return true;
    return t.name.toLowerCase().contains(query) ||
        t.shortName.toLowerCase().contains(query);
  }).toList();
});

// ---------------------------------------------------------------------------
// Live match state — local mirror of what the firmware would push back over
// BLE. The match flow drives this directly from the UI so the wireframe
// interactions are end-to-end clickable without a real device.
//
// Phase model is generalized over `numPeriods`:
//   idle         → before kickoff (pre-game; recording/streaming may be on)
//   period       → a period is in progress; clock counts up to periodLengthSeconds
//   periodBreak  → between periods (or after final period, awaiting end-of-match)
//   ended        → match is over; back-arrow returns to landing
// ---------------------------------------------------------------------------

enum MatchPhase { idle, period, periodBreak, ended }

enum MatchTimer { running, paused }

enum RecState { idle, recording, paused }

@immutable
class LiveEvent {
  const LiveEvent({
    required this.clock,
    required this.label,
    this.kind = 'event',
  });
  final String clock;
  final String label;
  final String kind; // event | phase
}

@immutable
class LiveMatchState {
  const LiveMatchState({
    required this.phase,
    required this.timer,
    required this.rec,
    required this.streaming,
    required this.elapsedSeconds,
    required this.currentPeriod,
    required this.numPeriods,
    required this.periodLengthSeconds,
    required this.scoreHome,
    required this.scoreAway,
    required this.homeName,
    required this.awayName,
    required this.events,
  });

  final MatchPhase phase;
  final MatchTimer timer;
  final RecState rec;
  final bool streaming;

  /// Elapsed seconds in the current period. Resets to 0 each period.
  final int elapsedSeconds;

  /// 1-based; 0 in [MatchPhase.idle].
  final int currentPeriod;
  final int numPeriods;
  final int periodLengthSeconds;

  final int scoreHome;
  final int scoreAway;
  final String homeName;
  final String awayName;
  final List<LiveEvent> events;

  bool get isPeriodActive => phase == MatchPhase.period;
  bool get isLastPeriod => currentPeriod == numPeriods && numPeriods > 0;
  bool get awaitingEndOfMatch =>
      phase == MatchPhase.periodBreak && isLastPeriod;

  String get clockText {
    final m = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Compact phase label for the score overlay / top bar:
  ///   PRE  · idle
  ///   P{N} · period (e.g. P1, P2)
  ///   BRK  · between periods
  ///   FT   · ended
  String get phaseLabel => switch (phase) {
    MatchPhase.idle => 'PRE',
    MatchPhase.period => 'P$currentPeriod',
    MatchPhase.periodBreak => isLastPeriod ? 'END' : 'BRK',
    MatchPhase.ended => 'FT',
  };

  LiveMatchState copyWith({
    MatchPhase? phase,
    MatchTimer? timer,
    RecState? rec,
    bool? streaming,
    int? elapsedSeconds,
    int? currentPeriod,
    int? numPeriods,
    int? periodLengthSeconds,
    int? scoreHome,
    int? scoreAway,
    String? homeName,
    String? awayName,
    List<LiveEvent>? events,
  }) {
    return LiveMatchState(
      phase: phase ?? this.phase,
      timer: timer ?? this.timer,
      rec: rec ?? this.rec,
      streaming: streaming ?? this.streaming,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      currentPeriod: currentPeriod ?? this.currentPeriod,
      numPeriods: numPeriods ?? this.numPeriods,
      periodLengthSeconds: periodLengthSeconds ?? this.periodLengthSeconds,
      scoreHome: scoreHome ?? this.scoreHome,
      scoreAway: scoreAway ?? this.scoreAway,
      homeName: homeName ?? this.homeName,
      awayName: awayName ?? this.awayName,
      events: events ?? this.events,
    );
  }

  static const initial = LiveMatchState(
    phase: MatchPhase.idle,
    timer: MatchTimer.paused,
    rec: RecState.idle,
    streaming: false,
    elapsedSeconds: 0,
    currentPeriod: 0,
    numPeriods: 2,
    periodLengthSeconds: 35 * 60,
    scoreHome: 0,
    scoreAway: 0,
    homeName: 'NR',
    awayName: 'EFC',
    events: [],
  );
}

class LiveMatchController extends Notifier<LiveMatchState> {
  @override
  LiveMatchState build() => LiveMatchState.initial;

  static String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  /// Called once per second by the live page. Increments the per-period
  /// clock when the timer is running and a period is active. When the
  /// period length is reached the timer auto-stops and we transition to
  /// [MatchPhase.periodBreak] (the user must explicitly end the match
  /// from the periodBreak after the final period).
  void tick() {
    if (state.phase != MatchPhase.period) return;
    if (state.timer != MatchTimer.running) return;
    final next = state.elapsedSeconds + 1;
    if (next >= state.periodLengthSeconds && state.periodLengthSeconds > 0) {
      _endPeriodInternal(elapsed: state.periodLengthSeconds);
      return;
    }
    state = state.copyWith(elapsedSeconds: next);
  }

  /// Start the next period (period 1 from idle, period N+1 from break).
  /// Optionally toggles recording / streaming on at the same time — the
  /// kickoff modal in the UI passes the user's choices here.
  void startPeriod({bool? startRecording, bool? startStreaming}) {
    if (state.phase != MatchPhase.idle &&
        state.phase != MatchPhase.periodBreak) {
      return;
    }
    if (state.awaitingEndOfMatch) return; // last period already played
    final next = state.currentPeriod + 1;
    if (next > state.numPeriods) return;
    final rec = startRecording == true && state.rec == RecState.idle
        ? RecState.recording
        : state.rec;
    final streaming = startStreaming ?? state.streaming;
    state = state.copyWith(
      phase: MatchPhase.period,
      timer: MatchTimer.running,
      currentPeriod: next,
      elapsedSeconds: 0,
      rec: rec,
      streaming: streaming,
      events: [
        LiveEvent(
          clock: '00:00',
          label: next == 1 ? 'Kickoff' : 'Start period $next',
          kind: 'phase',
        ),
        ...state.events,
      ],
    );
  }

  /// Manually end the current period — same effect as the auto-stop on
  /// reaching the period length.
  void endPeriod() {
    if (state.phase != MatchPhase.period) return;
    _endPeriodInternal(elapsed: state.elapsedSeconds);
  }

  void _endPeriodInternal({required int elapsed}) {
    state = state.copyWith(
      phase: MatchPhase.periodBreak,
      timer: MatchTimer.paused,
      elapsedSeconds: elapsed,
      events: [
        LiveEvent(
          clock: _fmt(elapsed),
          label: 'End period ${state.currentPeriod}',
          kind: 'phase',
        ),
        ...state.events,
      ],
    );
  }

  /// Final transition — only valid after the last period has ended.
  /// `stopRecording` / `stopStreaming` reflect the user's choices in the
  /// end-of-match modal.
  void endMatch({bool stopRecording = true, bool stopStreaming = true}) {
    final rec = stopRecording ? RecState.idle : state.rec;
    final streaming = stopStreaming ? false : state.streaming;
    state = state.copyWith(
      phase: MatchPhase.ended,
      timer: MatchTimer.paused,
      rec: rec,
      streaming: streaming,
      events: [
        LiveEvent(
          clock: _fmt(state.elapsedSeconds),
          label: 'End match',
          kind: 'phase',
        ),
        ...state.events,
      ],
    );
  }

  void toggleTimer() {
    if (state.phase != MatchPhase.period) return;
    state = state.copyWith(
      timer: state.timer == MatchTimer.running
          ? MatchTimer.paused
          : MatchTimer.running,
    );
  }

  // Recording — independent of the period timer; can run during pre-game
  // and post-game.
  void startRecording() {
    if (state.rec == RecState.idle) {
      state = state.copyWith(rec: RecState.recording);
    }
  }

  void toggleRecPause() {
    if (state.rec == RecState.recording) {
      state = state.copyWith(rec: RecState.paused);
    } else if (state.rec == RecState.paused) {
      state = state.copyWith(rec: RecState.recording);
    } else {
      state = state.copyWith(rec: RecState.recording);
    }
  }

  void stopRecording() {
    state = state.copyWith(rec: RecState.idle);
  }

  // Streaming — independent of the period timer.
  void setStreaming(bool on) => state = state.copyWith(streaming: on);

  void addEvent({
    required String type,
    required String teamLabel,
    String? jersey,
  }) {
    final clock = _fmt(state.elapsedSeconds);
    final jerseyPart = jersey == null || jersey.isEmpty ? '' : ' · #$jersey';
    final isGoal = type == 'Goal';
    final newScoreH = isGoal && teamLabel == state.homeName
        ? state.scoreHome + 1
        : state.scoreHome;
    final newScoreA = isGoal && teamLabel == state.awayName
        ? state.scoreAway + 1
        : state.scoreAway;
    state = state.copyWith(
      scoreHome: newScoreH,
      scoreAway: newScoreA,
      events: [
        LiveEvent(clock: clock, label: '$type · $teamLabel$jerseyPart'),
        ...state.events,
      ],
    );
  }

  void setTeams(String home, String away) =>
      state = state.copyWith(homeName: home, awayName: away);

  /// Hydrate from an upcoming-match selection. Resets clock + events and
  /// pulls home/away from the team and opponent strings, plus the
  /// scheduled time config (numPeriods, periodLengthSeconds).
  void loadFromUpcoming(UpcomingMatch up) {
    final home = up.team.shortName.isNotEmpty
        ? up.team.shortName
        : up.team.name;
    final opp = up.match.opponent;
    final away = opp.startsWith('vs ') ? opp.substring(3) : opp;
    final periods = up.match.numPeriods > 0 ? up.match.numPeriods : 2;
    final periodLen = up.match.periodLengthSeconds > 0
        ? up.match.periodLengthSeconds
        : 35 * 60;
    state = LiveMatchState.initial.copyWith(
      homeName: home,
      awayName: away,
      numPeriods: periods,
      periodLengthSeconds: periodLen,
    );
  }

  void reset() {
    state = LiveMatchState.initial;
  }
}

final liveMatchProvider = NotifierProvider<LiveMatchController, LiveMatchState>(
  LiveMatchController.new,
);

/// True iff a match is in flight — i.e. past kickoff and not yet finalized.
/// Phases `period` (period running) and `periodBreak` (between / after the
/// final period, awaiting end-of-match) both qualify. `idle` and `ended`
/// don't.
///
/// Used by [UsersController.delete] for the R10 live-match precondition. We
/// keep the rule conservative: any live match blocks deleting any user. The
/// per-user-cross-reference variant of this check is deferred (would require
/// `LiveMatchState` to expose owning team / preset / destination ids).
bool isLiveMatchRunning(LiveMatchState s) =>
    s.phase == MatchPhase.period || s.phase == MatchPhase.periodBreak;

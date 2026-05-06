// Local app data — library, live match state, team controller.
//
// Users + streaming destinations are owned by the local Drift DB. Teams,
// rosters, and sport presets will migrate in U5/U6. Library + LiveMatch are
// still local — the library will move to BLE in Phase 7 once recordings are
// wired up.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../db/daos/streaming_destinations_dao.dart';
import '../models/sport_preset.dart';
import '../models/streaming.dart';
import '../models/team.dart';
import '../models/user.dart';
import 'ble_providers.dart';
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
    required this.highlightSizeMb,
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
  final int highlightSizeMb;
  final List<LibraryEvent> events;
  final String downloadState; // 'all-local', 'partial', 'remote'
}

const _seedLibrary = <LibraryMatch>[
  LibraryMatch(
    id: 'nr-u14-m1',
    teamId: 'nr-u14',
    date: 'Mar 12',
    opponent: 'vs Eastfield FC',
    result: 'W 3–1',
    fullDuration: '01:23:42',
    fullSizeMb: 3100,
    highlightSizeMb: 380,
    events: [
      LibraryEvent(
        timeSeconds: 6 * 60 + 18,
        label: 'Goal · NR · #07',
        team: 'NR',
        kind: 'goal',
      ),
      LibraryEvent(
        timeSeconds: 14 * 60 + 42,
        label: 'Foul · EFC',
        team: 'EFC',
        kind: 'foul',
      ),
      LibraryEvent(
        timeSeconds: 22 * 60 + 48,
        label: 'Goal · NR · #11',
        team: 'NR',
        kind: 'goal',
      ),
      LibraryEvent(
        timeSeconds: 27 * 60 + 18,
        label: 'Goal · EFC · #14',
        team: 'EFC',
        kind: 'goal',
      ),
    ],
    downloadState: 'all-local',
  ),
  LibraryMatch(
    id: 'nr-u14-m2',
    teamId: 'nr-u14',
    date: 'Mar 05',
    opponent: 'vs Riverdale Utd',
    result: 'L 0–2',
    fullDuration: '01:25:48',
    fullSizeMb: 3000,
    highlightSizeMb: 180,
    events: [
      LibraryEvent(
        timeSeconds: 18 * 60 + 30,
        label: 'Goal · RU · #09',
        team: 'RU',
        kind: 'goal',
      ),
      LibraryEvent(
        timeSeconds: 56 * 60 + 12,
        label: 'Goal · RU · #11',
        team: 'RU',
        kind: 'goal',
      ),
    ],
    downloadState: 'partial',
  ),
  LibraryMatch(
    id: 'nr-u14-m3',
    teamId: 'nr-u14',
    date: 'Feb 26',
    opponent: 'vs Lakeside',
    result: 'D 1–1',
    fullDuration: '01:28:12',
    fullSizeMb: 3200,
    highlightSizeMb: 540,
    events: [
      LibraryEvent(
        timeSeconds: 12 * 60,
        label: 'Goal · NR · #07',
        team: 'NR',
        kind: 'goal',
      ),
      LibraryEvent(
        timeSeconds: 71 * 60,
        label: 'Goal · LK · #06',
        team: 'LK',
        kind: 'goal',
      ),
    ],
    downloadState: 'remote',
  ),
];

// ---------------------------------------------------------------------------
// Camera handle — `activeCameraIdProvider` is set by the discovery flow on a
// successful connect and cleared on disconnect. Team/match data still goes
// through BLE (migrated in U5); this provider remains until U7 removes all
// device gates.
// ---------------------------------------------------------------------------

final activeCameraIdProvider = StateProvider<String?>((ref) => null);

String? _resolveDeviceId(Ref ref) => ref.watch(activeCameraIdProvider);

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
      }
    }

    // Subscribe to watch stream for all mutations. The listener may fire once
    // with the same data as the initial snapshot below; that is acceptable.
    final sub = dao.watchAll().listen((rows) {
      state = AsyncValue.data(_toUserRecords(rows));
    });
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
  /// provider. Invalidates `upcomingMatchesProvider` (no userId arg there).
  ///
  /// Bridge (removed in U5): also calls BleService.setActiveUser so that
  /// DevDataStore stays in sync while TeamsController still reads from BLE.
  Future<void> setActive(String userId) async {
    if (userId == ref.read(activeUserProvider)) return;
    // BLE bridge — keeps DevDataStore in sync while TeamsController uses BLE.
    // Remove this block in U5 when TeamsController migrates to Drift.
    final deviceId = _resolveDeviceId(ref);
    if (deviceId != null) {
      await ref.read(bleServiceProvider).setActiveUser(deviceId, userId);
    }
    ref.read(activeUserProvider.notifier).state = userId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveUserIdKey, userId);
    ref.invalidate(upcomingMatchesProvider);
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
    final sub = dao.watchForUser(activeUserId).listen((rows) {
      state = AsyncValue.data(_toDestinations(rows));
    });
    ref.onDispose(sub.cancel);

    return _toDestinations(await dao.getForUser(activeUserId));
  }

  static List<StreamingDestination> _toDestinations(
    List<StreamingDestinationsTableData> rows,
  ) =>
      rows
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
    await ref.read(streamingDestinationsDaoProvider).insertDestination(companion);
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
    await ref.read(streamingDestinationsDaoProvider).updateDestination(companion);
    return StreamingDestination(
      id: draft.id,
      name: draft.name,
      provider: draft.provider,
      protocol: draft.protocol,
      config: draft.config,
    );
  }

  Future<void> delete(String destinationId) async {
    await ref
        .read(streamingDestinationsDaoProvider)
        .deleteById(destinationId);
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
// ---------------------------------------------------------------------------

class TeamsController extends AsyncNotifier<List<TeamRecord>> {
  String? get _deviceId => _resolveDeviceId(ref);

  /// Throws when callers try to mutate without an active connection. UI is
  /// expected to gate these calls behind `activeCameraIdProvider`, so this is
  /// a safety net rather than a routine error path.
  String _requireDevice() {
    final id = _deviceId;
    if (id == null) {
      throw StateError('No camera connected');
    }
    return id;
  }

  @override
  Future<List<TeamRecord>> build() async {
    final svc = ref.watch(bleServiceProvider);
    // Rebuild on user switch — the actual scoping happens inside the
    // BleService impl via DevDataStore.getActiveUser().
    ref.watch(activeUserProvider);
    final id = _deviceId;
    if (id == null) return const [];
    return svc.listTeams(id);
  }

  Future<void> _refresh() async {
    final svc = ref.read(bleServiceProvider);
    final id = _deviceId;
    state = AsyncValue.data(id == null ? const [] : await svc.listTeams(id));
  }

  Future<TeamRecord> create(TeamDraft draft) async {
    final svc = ref.read(bleServiceProvider);
    final created = await svc.createTeam(_requireDevice(), draft);
    await _refresh();
    return created;
  }

  Future<void> edit(TeamDraft draft) async {
    final svc = ref.read(bleServiceProvider);
    await svc.updateTeam(_requireDevice(), draft);
    await _refresh();
    // Team rename / sport change can affect how upcoming matches render.
    ref.invalidate(upcomingMatchesProvider);
  }

  Future<void> delete(String teamId) async {
    final svc = ref.read(bleServiceProvider);
    await svc.deleteTeam(_requireDevice(), teamId);
    await _refresh();
    ref.invalidate(upcomingMatchesProvider);
  }

  Future<void> setHidden(String teamId, {required bool hidden}) async {
    final svc = ref.read(bleServiceProvider);
    await svc.setTeamHidden(_requireDevice(), teamId, hidden: hidden);
    await _refresh();
    // Hidden teams are filtered out of the upcoming-matches list.
    ref.invalidate(upcomingMatchesProvider);
  }

  Future<void> addPlayer(String teamId, PlayerDraft draft) async {
    final svc = ref.read(bleServiceProvider);
    await svc.addPlayer(_requireDevice(), teamId, draft);
    await _refresh();
  }

  Future<void> updatePlayer(
    String teamId,
    int currentNumber,
    PlayerDraft draft,
  ) async {
    final svc = ref.read(bleServiceProvider);
    await svc.updatePlayer(_requireDevice(), teamId, currentNumber, draft);
    await _refresh();
  }

  Future<void> removePlayer(String teamId, int number) async {
    final svc = ref.read(bleServiceProvider);
    await svc.removePlayer(_requireDevice(), teamId, number);
    await _refresh();
  }

  Future<TeamMatch> addMatch(String teamId, TeamMatchDraft draft) async {
    final svc = ref.read(bleServiceProvider);
    final created = await svc.addTeamMatch(_requireDevice(), teamId, draft);
    ref.invalidate(teamMatchesProvider(teamId));
    ref.invalidate(upcomingMatchesProvider);
    return created;
  }

  Future<void> removeMatch(String teamId, String matchId) async {
    final svc = ref.read(bleServiceProvider);
    await svc.removeTeamMatch(_requireDevice(), teamId, matchId);
    ref.invalidate(teamMatchesProvider(teamId));
    ref.invalidate(upcomingMatchesProvider);
  }
}

final teamsControllerProvider =
    AsyncNotifierProvider<TeamsController, List<TeamRecord>>(
      TeamsController.new,
    );

/// Per-team match list — fetched fresh per page mount, empty while no
/// camera is connected.
final teamMatchesProvider = FutureProvider.family<List<TeamMatch>, String>((
  ref,
  teamId,
) async {
  final svc = ref.watch(bleServiceProvider);
  final id = _resolveDeviceId(ref);
  if (id == null) return const [];
  return svc.listTeamMatches(id, teamId);
});

/// Joined view of an upcoming match with its owning team — used by the
/// Match tab landing list. Built by [upcomingMatchesProvider]; not stored.
@immutable
class UpcomingMatch {
  const UpcomingMatch({required this.team, required this.match});
  final TeamRecord team;
  final TeamMatch match;
}

/// All upcoming matches across all teams on the camera, ordered by date
/// as returned by firmware. Reads teams directly via [BleService] instead
/// of watching [teamsControllerProvider] — that would create a circular
/// dependency, since [TeamsController] mutations explicitly invalidate
/// this provider when matches change.
///
/// Team-level mutations (edit / delete / setHidden) also invalidate this
/// provider, see [TeamsController].
final upcomingMatchesProvider = FutureProvider<List<UpcomingMatch>>((
  ref,
) async {
  final svc = ref.watch(bleServiceProvider);
  final id = _resolveDeviceId(ref);
  if (id == null) return const [];
  final teams = await svc.listTeams(id);
  final out = <UpcomingMatch>[];
  for (final t in teams) {
    if (t.hidden) continue;
    final matches = await svc.listTeamMatches(id, t.id);
    for (final m in matches) {
      if (m.kind != MatchKind.upcoming) continue;
      out.add(UpcomingMatch(team: t, match: m));
    }
  }
  return out;
});

// ---------------------------------------------------------------------------
// Sport setups (presets) — saved per-camera time configs grouped by base
// sport. Picked at match-schedule time to materialize a match's periods.
// ---------------------------------------------------------------------------

class SportPresetsController extends AsyncNotifier<List<SportPreset>> {
  String? get _deviceId => _resolveDeviceId(ref);

  String _requireDevice() {
    final id = _deviceId;
    if (id == null) throw StateError('No camera connected');
    return id;
  }

  @override
  Future<List<SportPreset>> build() async {
    final svc = ref.watch(bleServiceProvider);
    // Rebuild on user switch — the actual scoping happens inside the
    // BleService impl via DevDataStore.getActiveUser().
    ref.watch(activeUserProvider);
    final id = _deviceId;
    if (id == null) return const [];
    return svc.listSportPresets(id);
  }

  Future<void> _refresh() async {
    final svc = ref.read(bleServiceProvider);
    final id = _deviceId;
    state = AsyncValue.data(
      id == null ? const [] : await svc.listSportPresets(id),
    );
  }

  Future<SportPreset> create(SportPresetDraft draft) async {
    final svc = ref.read(bleServiceProvider);
    final created = await svc.createSportPreset(_requireDevice(), draft);
    await _refresh();
    return created;
  }

  Future<void> edit(SportPresetDraft draft) async {
    final svc = ref.read(bleServiceProvider);
    await svc.updateSportPreset(_requireDevice(), draft);
    await _refresh();
  }

  Future<void> delete(String presetId) async {
    final svc = ref.read(bleServiceProvider);
    await svc.deleteSportPreset(_requireDevice(), presetId);
    await _refresh();
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
// Library (recordings) — still local; will move to BLE in Phase 7.
// ---------------------------------------------------------------------------

final libraryProvider = Provider<List<LibraryMatch>>((ref) => _seedLibrary);

final libraryMatchProvider = Provider.family<LibraryMatch?, String>((ref, id) {
  return ref.watch(libraryProvider).where((m) => m.id == id).firstOrNull;
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

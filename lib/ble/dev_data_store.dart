// Process-global in-memory data layer shared by both BLE service
// implementations during dev. Owns users, streaming destinations, and the
// per-user-keyed views of teams, team matches, and sport presets.
//
// Designed as the single seam where `MockBleService` (always) and
// `BleServiceImpl` (only when `kAppEnv.isMock`) delegate. Real firmware
// integration replaces those delegations method-by-method in Phase 7.
//
// Lifecycle:
//   * `_instance` runs `_seed()` eagerly at construction so tests that don't
//     set an active user still see seed data under `user-1`.
//   * `reset()` clears everything and re-runs `_seed()`. Tests fire it via
//     `useDevDataStoreReset()` from `test/test_helpers.dart`. Production
//     code never calls `reset()`.
//
// Active-user discipline (CRITICAL — see plan's Key Technical Decisions):
//   `_activeUserId` is a persistence record only. It is read by
//   `getActiveUser` and written by `setActiveUser`. It is NEVER the
//   implicit scope for any read/write method — every CRUD method requires
//   the caller to pass `userId` explicitly. The single source of truth for
//   the active user lives in `activeUserProvider` on the Riverpod side.

import '../models/sport_preset.dart';
import '../models/streaming.dart';
import '../models/team.dart';
import '../models/user.dart';

/// Typed exception for invariants the store enforces as a safety net (last
/// user / active user delete blocks, built-in preset protection, missing
/// user lookups). UI layers usually pre-check the same conditions before
/// calling in.
class DevDataStoreException implements Exception {
  const DevDataStoreException(this.message);
  final String message;

  @override
  String toString() => 'DevDataStoreException: $message';
}

class DevDataStore {
  DevDataStore._();

  static final DevDataStore _instance = DevDataStore._().._seed();

  static DevDataStore get instance => _instance;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  final Map<String, UserRecord> _users = {};
  String? _activeUserId;
  final Map<String, List<TeamRecord>> _teamsByUser = {};
  final Map<String, Map<String, List<TeamMatch>>> _matchesByUserAndTeam = {};
  final Map<String, List<SportPreset>> _presetsByUser = {};
  final Map<String, List<StreamingDestination>> _destinationsByUser = {};

  int _userIdCounter = 0;
  int _teamIdCounter = 0;
  int _matchIdCounter = 0;
  int _presetIdCounter = 0;
  int _destinationIdCounter = 0;

  // ---------------------------------------------------------------------------
  // USER CRUD
  // ---------------------------------------------------------------------------

  List<UserRecord> listUsers() => List.unmodifiable(_users.values);

  UserRecord createUser(UserDraft draft) {
    final id = 'user-${++_userIdCounter}';
    final user = UserRecord(id: id, name: draft.name);
    _users[id] = user;
    _teamsByUser[id] = [];
    _matchesByUserAndTeam[id] = {};
    _presetsByUser[id] = _builtInSportPresets();
    _destinationsByUser[id] = [];
    // First-user bootstrap: if no user was active, the new one becomes
    // active. Subsequent createUser calls do NOT change the active user.
    _activeUserId ??= id;
    return user;
  }

  UserRecord updateUser(UserDraft draft) {
    if (draft.id.isEmpty) {
      throw const DevDataStoreException('updateUser requires a non-empty id');
    }
    final existing = _users[draft.id];
    if (existing == null) {
      throw DevDataStoreException('User ${draft.id} not found');
    }
    final updated = existing.copyWith(name: draft.name);
    _users[draft.id] = updated;
    return updated;
  }

  void deleteUser(String userId) {
    if (!_users.containsKey(userId)) {
      throw DevDataStoreException('User $userId not found');
    }
    if (userId == _activeUserId) {
      throw DevDataStoreException(
        'Cannot delete the active user — switch to another user first',
      );
    }
    if (_users.length == 1) {
      throw const DevDataStoreException(
        'Cannot delete the last remaining user',
      );
    }
    _users.remove(userId);
    _teamsByUser.remove(userId);
    _matchesByUserAndTeam.remove(userId);
    _presetsByUser.remove(userId);
    _destinationsByUser.remove(userId);
  }

  String? getActiveUser() => _activeUserId;

  void setActiveUser(String userId) {
    if (!_users.containsKey(userId)) {
      throw DevDataStoreException('User $userId not found');
    }
    _activeUserId = userId;
  }

  // ---------------------------------------------------------------------------
  // TEAMS (per-user)
  // ---------------------------------------------------------------------------

  List<TeamRecord> listTeams(String userId) {
    final list = _teamsByUser[userId];
    if (list == null) return const [];
    return List.unmodifiable(list);
  }

  TeamRecord createTeam(String userId, TeamDraft draft) {
    final list = _requireTeams(userId);
    final id =
        'team-${++_teamIdCounter}-${DateTime.now().millisecondsSinceEpoch}';
    final record = TeamRecord(
      id: id,
      name: draft.name,
      shortName: draft.shortName,
      sport: draft.sport,
      roster: const [],
    );
    list.add(record);
    return record;
  }

  TeamRecord updateTeam(String userId, TeamDraft draft) {
    final list = _requireTeams(userId);
    final i = list.indexWhere((t) => t.id == draft.id);
    if (i == -1) {
      throw DevDataStoreException('Team ${draft.id} not found');
    }
    final updated = list[i].copyWith(
      name: draft.name,
      shortName: draft.shortName,
      sport: draft.sport,
    );
    list[i] = updated;
    return updated;
  }

  void deleteTeam(String userId, String teamId) {
    final list = _requireTeams(userId);
    list.removeWhere((t) => t.id == teamId);
    _matchesByUserAndTeam[userId]?.remove(teamId);
  }

  TeamRecord setTeamHidden(
    String userId,
    String teamId, {
    required bool hidden,
  }) {
    final list = _requireTeams(userId);
    final i = list.indexWhere((t) => t.id == teamId);
    if (i == -1) {
      throw DevDataStoreException('Team $teamId not found');
    }
    final updated = list[i].copyWith(hidden: hidden);
    list[i] = updated;
    return updated;
  }

  Player addPlayer(String userId, String teamId, PlayerDraft draft) {
    final list = _requireTeams(userId);
    final i = list.indexWhere((t) => t.id == teamId);
    if (i == -1) {
      throw DevDataStoreException('Team $teamId not found');
    }
    final team = list[i];
    if (team.roster.any((p) => p.number == draft.number)) {
      throw DevDataStoreException(
        'Jersey #${draft.number} already taken on this team',
      );
    }
    final player = Player(
      number: draft.number,
      name: draft.name,
      position: draft.position,
      captain: draft.captain,
    );
    final newRoster = List<Player>.from(team.roster)
      ..add(player)
      ..sort((a, b) => a.number.compareTo(b.number));
    final cleaned = draft.captain
        ? newRoster
              .map(
                (p) => p.number == player.number ? p : _withCaptain(p, false),
              )
              .toList()
        : newRoster;
    list[i] = team.copyWith(roster: cleaned);
    return player;
  }

  Player updatePlayer(
    String userId,
    String teamId,
    int currentNumber,
    PlayerDraft draft,
  ) {
    final list = _requireTeams(userId);
    final i = list.indexWhere((t) => t.id == teamId);
    if (i == -1) {
      throw DevDataStoreException('Team $teamId not found');
    }
    final team = list[i];
    final pi = team.roster.indexWhere((p) => p.number == currentNumber);
    if (pi == -1) {
      throw DevDataStoreException('Player #$currentNumber not found');
    }
    if (draft.number != currentNumber &&
        team.roster.any((p) => p.number == draft.number)) {
      throw DevDataStoreException(
        'Jersey #${draft.number} already taken on this team',
      );
    }
    final updated = Player(
      number: draft.number,
      name: draft.name,
      position: draft.position,
      captain: draft.captain,
    );
    final newRoster = List<Player>.from(team.roster);
    newRoster[pi] = updated;
    final cleaned = draft.captain
        ? newRoster
              .map(
                (p) => p.number == updated.number ? p : _withCaptain(p, false),
              )
              .toList()
        : newRoster;
    cleaned.sort((a, b) => a.number.compareTo(b.number));
    list[i] = team.copyWith(roster: cleaned);
    return updated;
  }

  void removePlayer(String userId, String teamId, int number) {
    final list = _requireTeams(userId);
    final i = list.indexWhere((t) => t.id == teamId);
    if (i == -1) return;
    final team = list[i];
    final newRoster = team.roster.where((p) => p.number != number).toList();
    list[i] = team.copyWith(roster: newRoster);
  }

  // ---------------------------------------------------------------------------
  // TEAM MATCHES (per-user, per-team)
  // ---------------------------------------------------------------------------

  List<TeamMatch> listTeamMatches(String userId, String teamId) {
    final perTeam = _matchesByUserAndTeam[userId];
    if (perTeam == null) return const [];
    return List.unmodifiable(perTeam[teamId] ?? const []);
  }

  TeamMatch addTeamMatch(
    String userId,
    String teamId,
    TeamMatchDraft draft,
  ) {
    final perTeam = _requireMatches(userId);
    final id =
        'match-${++_matchIdCounter}-${DateTime.now().millisecondsSinceEpoch}';
    final match = TeamMatch(
      id: id,
      opponent: draft.opponent,
      date: draft.date,
      result: draft.kind == MatchKind.past ? draft.result : '',
      kind: draft.kind,
      numPeriods: draft.numPeriods,
      periodLengthSeconds: draft.periodLengthSeconds,
      clips: 0,
      sizeMb: 0,
    );
    final list = List<TeamMatch>.from(perTeam[teamId] ?? const []);
    list.insert(0, match);
    perTeam[teamId] = list;
    return match;
  }

  void removeTeamMatch(String userId, String teamId, String matchId) {
    final perTeam = _matchesByUserAndTeam[userId];
    if (perTeam == null) return;
    final list = perTeam[teamId];
    if (list == null) return;
    perTeam[teamId] = list.where((m) => m.id != matchId).toList();
  }

  // ---------------------------------------------------------------------------
  // SPORT PRESETS (per-user)
  // ---------------------------------------------------------------------------

  List<SportPreset> listSportPresets(String userId) {
    final list = _presetsByUser[userId];
    if (list == null) return const [];
    return List.unmodifiable(list);
  }

  SportPreset createSportPreset(String userId, SportPresetDraft draft) {
    final list = _requirePresets(userId);
    final id =
        'preset-${++_presetIdCounter}-${DateTime.now().millisecondsSinceEpoch}';
    final preset = SportPreset(
      id: id,
      name: draft.name,
      sport: draft.sport,
      numPeriods: draft.numPeriods,
      periodLengthSeconds: draft.periodLengthSeconds,
    );
    list.add(preset);
    return preset;
  }

  SportPreset updateSportPreset(String userId, SportPresetDraft draft) {
    final list = _requirePresets(userId);
    final i = list.indexWhere((p) => p.id == draft.id);
    if (i == -1) {
      throw DevDataStoreException('Sport preset ${draft.id} not found');
    }
    if (list[i].builtIn) {
      throw const DevDataStoreException('Built-in presets cannot be edited');
    }
    final updated = list[i].copyWith(
      name: draft.name,
      sport: draft.sport,
      numPeriods: draft.numPeriods,
      periodLengthSeconds: draft.periodLengthSeconds,
    );
    list[i] = updated;
    return updated;
  }

  void deleteSportPreset(String userId, String presetId) {
    final list = _requirePresets(userId);
    final i = list.indexWhere((p) => p.id == presetId);
    if (i == -1) return;
    if (list[i].builtIn) {
      throw const DevDataStoreException('Built-in presets cannot be deleted');
    }
    list.removeAt(i);
  }

  // ---------------------------------------------------------------------------
  // STREAMING DESTINATIONS (per-user)
  // ---------------------------------------------------------------------------

  List<StreamingDestination> listStreamingDestinations(String userId) {
    final list = _destinationsByUser[userId];
    if (list == null) return const [];
    return List.unmodifiable(list);
  }

  StreamingDestination createStreamingDestination(
    String userId,
    StreamingDestinationDraft draft,
  ) {
    final list = _requireDestinations(userId);
    final id =
        'dest-${++_destinationIdCounter}-${DateTime.now().millisecondsSinceEpoch}';
    final dest = StreamingDestination(
      id: id,
      name: draft.name,
      provider: draft.provider,
      protocol: draft.protocol,
      config: draft.config,
    );
    list.add(dest);
    return dest;
  }

  StreamingDestination updateStreamingDestination(
    String userId,
    StreamingDestinationDraft draft,
  ) {
    final list = _requireDestinations(userId);
    final i = list.indexWhere((d) => d.id == draft.id);
    if (i == -1) {
      throw DevDataStoreException(
        'Streaming destination ${draft.id} not found',
      );
    }
    final updated = list[i].copyWith(
      name: draft.name,
      provider: draft.provider,
      protocol: draft.protocol,
      config: draft.config,
    );
    list[i] = updated;
    return updated;
  }

  void deleteStreamingDestination(String userId, String destinationId) {
    final list = _requireDestinations(userId);
    list.removeWhere((d) => d.id == destinationId);
  }

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  /// Clears all state and re-runs the eager seed. Tests fire this in
  /// `setUp` via `useDevDataStoreReset()` so the process-global store
  /// can't leak across test cases.
  void reset() {
    _users.clear();
    _activeUserId = null;
    _teamsByUser.clear();
    _matchesByUserAndTeam.clear();
    _presetsByUser.clear();
    _destinationsByUser.clear();
    _userIdCounter = 0;
    _teamIdCounter = 0;
    _matchIdCounter = 0;
    _presetIdCounter = 0;
    _destinationIdCounter = 0;
    _seed();
  }

  // ---------------------------------------------------------------------------
  // Seed
  // ---------------------------------------------------------------------------

  void _seed() {
    // user-1 — Coach Diego — owns all the existing seed teams/matches.
    final user1 = UserRecord(
      id: 'user-${++_userIdCounter}',
      name: 'Coach Diego',
    );
    // user-2 — Coach Maria — empty teams/matches; still gets built-in presets.
    final user2 = UserRecord(
      id: 'user-${++_userIdCounter}',
      name: 'Coach Maria',
    );

    _users[user1.id] = user1;
    _users[user2.id] = user2;
    _activeUserId = user1.id;

    _teamsByUser[user1.id] = _seedTeams();
    _teamsByUser[user2.id] = [];

    _matchesByUserAndTeam[user1.id] = _seedMatches();
    _matchesByUserAndTeam[user2.id] = {};

    _presetsByUser[user1.id] = _builtInSportPresets();
    _presetsByUser[user2.id] = _builtInSportPresets();

    _destinationsByUser[user1.id] = [];
    _destinationsByUser[user2.id] = [];
  }

  static const _seedRoster = <Player>[
    Player(number: 7, name: 'A. Patel', position: 'Forward', captain: true),
    Player(number: 10, name: 'B. Okafor', position: 'Mid'),
    Player(number: 4, name: 'C. Nguyen', position: 'Defender'),
    Player(number: 1, name: 'D. Reyes', position: 'Keeper'),
    Player(number: 11, name: 'E. Mahmoud', position: 'Forward'),
    Player(number: 8, name: 'F. Lopez', position: 'Mid'),
    Player(number: 5, name: 'G. Singh', position: 'Defender'),
  ];

  List<TeamRecord> _seedTeams() => [
    const TeamRecord(
      id: 'nr-u14',
      name: 'Northside Rovers U14',
      shortName: 'NRA',
      sport: 'Soccer',
      roster: _seedRoster,
    ),
    const TeamRecord(
      id: 'nr-u12',
      name: 'Northside Rovers U12',
      shortName: 'NRB',
      sport: 'Soccer',
      roster: [],
    ),
    const TeamRecord(
      id: 'efc-r',
      name: 'Eastfield FC Reserves',
      shortName: 'EFC',
      sport: 'Soccer',
      roster: [],
    ),
    const TeamRecord(
      id: 'rd-utd',
      name: 'Riverdale United',
      shortName: 'RDU',
      sport: 'Soccer',
      roster: [],
    ),
  ];

  Map<String, List<TeamMatch>> _seedMatches() => {
    'nr-u14': [
      const TeamMatch(
        id: 'nr-u14-up1',
        opponent: 'vs Eastfield FC',
        date: 'May 11',
        result: '',
        kind: MatchKind.upcoming,
        numPeriods: 2,
        periodLengthSeconds: 35 * 60,
        clips: 0,
        sizeMb: 0,
      ),
      const TeamMatch(
        id: 'nr-u14-up2',
        opponent: 'vs Lakeside',
        date: 'May 18',
        result: '',
        kind: MatchKind.upcoming,
        numPeriods: 2,
        periodLengthSeconds: 35 * 60,
        clips: 0,
        sizeMb: 0,
      ),
      const TeamMatch(
        id: 'nr-u14-m1',
        opponent: 'vs Eastfield FC',
        date: 'Mar 12',
        result: 'W 3–1',
        clips: 2,
        sizeMb: 380,
      ),
      const TeamMatch(
        id: 'nr-u14-m2',
        opponent: 'vs Riverdale Utd',
        date: 'Mar 05',
        result: 'L 0–2',
        clips: 2,
        sizeMb: 180,
      ),
      const TeamMatch(
        id: 'nr-u14-m3',
        opponent: 'vs Lakeside',
        date: 'Feb 26',
        result: 'D 1–1',
        clips: 2,
        sizeMb: 540,
      ),
    ],
  };

  /// Built-in sport presets — one entry per `kSports` value. Each user
  /// gets a fresh copy at seed and at createUser so per-user mutations
  /// (custom presets) stay isolated.
  List<SportPreset> _builtInSportPresets() => [
    const SportPreset(
      id: 'preset-soccer-std',
      name: 'Soccer · Standard',
      sport: 'Soccer',
      numPeriods: 2,
      periodLengthSeconds: 45 * 60,
      builtIn: true,
    ),
    const SportPreset(
      id: 'preset-soccer-youth',
      name: 'Soccer · Youth (U14)',
      sport: 'Soccer',
      numPeriods: 2,
      periodLengthSeconds: 35 * 60,
      builtIn: true,
    ),
    const SportPreset(
      id: 'preset-basketball-fiba',
      name: 'Basketball · FIBA',
      sport: 'Basketball',
      numPeriods: 4,
      periodLengthSeconds: 10 * 60,
      builtIn: true,
    ),
    const SportPreset(
      id: 'preset-hockey-std',
      name: 'Hockey · Standard',
      sport: 'Hockey',
      numPeriods: 3,
      periodLengthSeconds: 20 * 60,
      builtIn: true,
    ),
    const SportPreset(
      id: 'preset-volleyball-5set',
      name: 'Volleyball · 5-set',
      sport: 'Volleyball',
      numPeriods: 5,
      periodLengthSeconds: 25 * 60,
      builtIn: true,
    ),
    const SportPreset(
      id: 'preset-rugby-std',
      name: 'Rugby · Standard',
      sport: 'Rugby',
      numPeriods: 2,
      periodLengthSeconds: 40 * 60,
      builtIn: true,
    ),
    const SportPreset(
      id: 'preset-other-single',
      name: 'Other · Single period',
      sport: 'Other',
      numPeriods: 1,
      periodLengthSeconds: 30 * 60,
      builtIn: true,
    ),
  ];

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<TeamRecord> _requireTeams(String userId) {
    final list = _teamsByUser[userId];
    if (list == null) {
      throw DevDataStoreException('User $userId not found');
    }
    return list;
  }

  Map<String, List<TeamMatch>> _requireMatches(String userId) {
    final perTeam = _matchesByUserAndTeam[userId];
    if (perTeam == null) {
      throw DevDataStoreException('User $userId not found');
    }
    return perTeam;
  }

  List<SportPreset> _requirePresets(String userId) {
    final list = _presetsByUser[userId];
    if (list == null) {
      throw DevDataStoreException('User $userId not found');
    }
    return list;
  }

  List<StreamingDestination> _requireDestinations(String userId) {
    final list = _destinationsByUser[userId];
    if (list == null) {
      throw DevDataStoreException('User $userId not found');
    }
    return list;
  }

  static Player _withCaptain(Player p, bool captain) => Player(
    number: p.number,
    name: p.name,
    position: p.position,
    captain: captain,
  );
}

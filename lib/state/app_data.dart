// Local app data — library, live match state, team controller.
//
// Team / roster / per-team match data is owned by the camera. The app reads
// and writes it through `BleService`. Library + LiveMatch are still local —
// the library will move to BLE in Phase 7 once recordings are wired up.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/team.dart';
import 'ble_providers.dart';

export '../models/team.dart';

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
// successful connect and cleared on disconnect. Team data lives on the
// camera, so every team query is gated on this id: if there's no active
// camera, the controllers return empty and the UI prompts to connect.
// ---------------------------------------------------------------------------

final activeCameraIdProvider = StateProvider<String?>((ref) => null);

String? _resolveDeviceId(Ref ref) => ref.watch(activeCameraIdProvider);

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
  }

  Future<void> delete(String teamId) async {
    final svc = ref.read(bleServiceProvider);
    await svc.deleteTeam(_requireDevice(), teamId);
    await _refresh();
  }

  Future<void> setHidden(String teamId, {required bool hidden}) async {
    final svc = ref.read(bleServiceProvider);
    await svc.setTeamHidden(_requireDevice(), teamId, hidden: hidden);
    await _refresh();
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
    return created;
  }

  Future<void> removeMatch(String teamId, String matchId) async {
    final svc = ref.read(bleServiceProvider);
    await svc.removeTeamMatch(_requireDevice(), teamId, matchId);
    ref.invalidate(teamMatchesProvider(teamId));
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

// ---------------------------------------------------------------------------
// Filter / search state for the Teams page.
// ---------------------------------------------------------------------------

final teamsSearchQueryProvider = StateProvider<String>((_) => '');
final teamsSportFilterProvider = StateProvider<String?>(
  (_) => null,
); // null = All
final teamsShowHiddenProvider = StateProvider<bool>((_) => false);

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
// ---------------------------------------------------------------------------

enum MatchPhase { idle, firstHalf, halftime, secondHalf, ended }

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
    required this.elapsedSeconds,
    required this.scoreHome,
    required this.scoreAway,
    required this.homeName,
    required this.awayName,
    required this.events,
    required this.recordingEnabled,
    required this.streamingEnabled,
  });

  final MatchPhase phase;
  final MatchTimer timer;
  final RecState rec;
  final int elapsedSeconds;
  final int scoreHome;
  final int scoreAway;
  final String homeName;
  final String awayName;
  final List<LiveEvent> events;
  final bool recordingEnabled;
  final bool streamingEnabled;

  bool get isLive =>
      phase == MatchPhase.firstHalf || phase == MatchPhase.secondHalf;

  String get clockText {
    final m = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get phaseLabel => switch (phase) {
    MatchPhase.idle => 'PRE',
    MatchPhase.firstHalf => '1H',
    MatchPhase.halftime => 'HT',
    MatchPhase.secondHalf => '2H',
    MatchPhase.ended => 'FT',
  };

  LiveMatchState copyWith({
    MatchPhase? phase,
    MatchTimer? timer,
    RecState? rec,
    int? elapsedSeconds,
    int? scoreHome,
    int? scoreAway,
    String? homeName,
    String? awayName,
    List<LiveEvent>? events,
    bool? recordingEnabled,
    bool? streamingEnabled,
  }) {
    return LiveMatchState(
      phase: phase ?? this.phase,
      timer: timer ?? this.timer,
      rec: rec ?? this.rec,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      scoreHome: scoreHome ?? this.scoreHome,
      scoreAway: scoreAway ?? this.scoreAway,
      homeName: homeName ?? this.homeName,
      awayName: awayName ?? this.awayName,
      events: events ?? this.events,
      recordingEnabled: recordingEnabled ?? this.recordingEnabled,
      streamingEnabled: streamingEnabled ?? this.streamingEnabled,
    );
  }

  static const initial = LiveMatchState(
    phase: MatchPhase.idle,
    timer: MatchTimer.paused,
    rec: RecState.idle,
    elapsedSeconds: 0,
    scoreHome: 0,
    scoreAway: 0,
    homeName: 'NR',
    awayName: 'EFC',
    events: [],
    recordingEnabled: true,
    streamingEnabled: true,
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

  /// Called once per second by the live page while the match is running.
  void tick() {
    if (state.timer != MatchTimer.running) return;
    if (!state.isLive) return;
    state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
  }

  void startFirstHalf() {
    if (state.phase != MatchPhase.idle) return;
    state = state.copyWith(
      phase: MatchPhase.firstHalf,
      timer: MatchTimer.running,
      rec: state.recordingEnabled ? RecState.recording : state.rec,
      elapsedSeconds: 0,
      events: [
        ...state.events,
        const LiveEvent(clock: '00:00', label: 'Start 1st half', kind: 'phase'),
      ],
    );
  }

  void endFirstHalf() {
    if (state.phase != MatchPhase.firstHalf) return;
    state = state.copyWith(
      phase: MatchPhase.halftime,
      timer: MatchTimer.paused,
      events: [
        LiveEvent(
          clock: _fmt(state.elapsedSeconds),
          label: 'End 1st half',
          kind: 'phase',
        ),
        ...state.events,
      ],
    );
  }

  void startSecondHalf() {
    if (state.phase != MatchPhase.halftime) return;
    state = state.copyWith(
      phase: MatchPhase.secondHalf,
      timer: MatchTimer.running,
      events: [
        LiveEvent(
          clock: _fmt(state.elapsedSeconds),
          label: 'Start 2nd half',
          kind: 'phase',
        ),
        ...state.events,
      ],
    );
  }

  void endMatch() {
    state = state.copyWith(
      phase: MatchPhase.ended,
      timer: MatchTimer.paused,
      rec: RecState.idle,
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
    if (!state.isLive) return;
    state = state.copyWith(
      timer: state.timer == MatchTimer.running
          ? MatchTimer.paused
          : MatchTimer.running,
    );
  }

  void toggleRecPause() {
    if (state.rec == RecState.recording) {
      state = state.copyWith(rec: RecState.paused);
    } else if (state.rec == RecState.paused) {
      state = state.copyWith(rec: RecState.recording);
    }
  }

  void stopRecording() {
    state = state.copyWith(rec: RecState.idle);
  }

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

  void setRecordingEnabled(bool v) =>
      state = state.copyWith(recordingEnabled: v);

  void setStreamingEnabled(bool v) =>
      state = state.copyWith(streamingEnabled: v);

  void setTeams(String home, String away) =>
      state = state.copyWith(homeName: home, awayName: away);

  void reset() {
    state = LiveMatchState.initial;
  }
}

final liveMatchProvider = NotifierProvider<LiveMatchController, LiveMatchState>(
  LiveMatchController.new,
);

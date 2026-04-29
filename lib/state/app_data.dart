// Local app data — teams, library, match state.
//
// In-memory only for now. Phase 3 will swap the team store for a drift DB
// and the library/match clips will come from BLE + WiFi blob transfer.
// Keeping the providers stable here means the UI can already exercise
// every flow end-to-end.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Player {
  const Player({
    required this.number,
    required this.name,
    required this.position,
    this.captain = false,
  });
  final int number;
  final String name;
  final String position;
  final bool captain;
}

class TeamRecord {
  const TeamRecord({
    required this.id,
    required this.name,
    required this.shortName,
    required this.initials,
    required this.sport,
    required this.roster,
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.cleanSheets,
    required this.cards,
    required this.lastMatchDate,
  });

  final String id;
  final String name;
  final String shortName;
  final String initials;
  final String sport;
  final List<Player> roster;
  final int played;
  final int wins;
  final int draws;
  final int losses;
  final int goalsFor;
  final int goalsAgainst;
  final int cleanSheets;
  final int cards;
  final String lastMatchDate;
}

class TeamMatch {
  const TeamMatch({
    required this.id,
    required this.opponent,
    required this.date,
    required this.result, // 'W 3–1' / 'L 0–2' / 'D 1–1'
    required this.clips,
    required this.sizeMb,
  });
  final String id;
  final String opponent;
  final String date;
  final String result;
  final int clips;
  final int sizeMb;

  String get outcome => result.substring(0, 1); // W / L / D
}

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

// ---------------------------------------------------------------------------
// Seed data (mirrors the wireframe content so the screens look familiar).
// ---------------------------------------------------------------------------

const _nrU14Roster = <Player>[
  Player(number: 7, name: 'A. Patel', position: 'Forward', captain: true),
  Player(number: 10, name: 'B. Okafor', position: 'Mid'),
  Player(number: 4, name: 'C. Nguyen', position: 'Defender'),
  Player(number: 1, name: 'D. Reyes', position: 'Keeper'),
  Player(number: 11, name: 'E. Mahmoud', position: 'Forward'),
  Player(number: 8, name: 'F. Lopez', position: 'Mid'),
  Player(number: 5, name: 'G. Singh', position: 'Defender'),
];

const _seedTeams = <TeamRecord>[
  TeamRecord(
    id: 'nr-u14',
    name: 'Northside Rovers U14',
    shortName: 'NR U14',
    initials: 'NR',
    sport: 'Soccer',
    roster: _nrU14Roster,
    played: 6,
    wins: 3,
    draws: 1,
    losses: 2,
    goalsFor: 13,
    goalsAgainst: 9,
    cleanSheets: 2,
    cards: 7,
    lastMatchDate: 'Mar 12',
  ),
  TeamRecord(
    id: 'nr-u12',
    name: 'Northside Rovers U12',
    shortName: 'NR U12',
    initials: 'NR',
    sport: 'Soccer',
    roster: [],
    played: 4,
    wins: 2,
    draws: 1,
    losses: 1,
    goalsFor: 8,
    goalsAgainst: 6,
    cleanSheets: 1,
    cards: 3,
    lastMatchDate: 'Mar 09',
  ),
  TeamRecord(
    id: 'efc-r',
    name: 'Eastfield FC Reserves',
    shortName: 'EFC R',
    initials: 'EF',
    sport: 'Soccer',
    roster: [],
    played: 5,
    wins: 1,
    draws: 1,
    losses: 3,
    goalsFor: 6,
    goalsAgainst: 11,
    cleanSheets: 0,
    cards: 8,
    lastMatchDate: 'Feb 28',
  ),
  TeamRecord(
    id: 'rd-utd',
    name: 'Riverdale United',
    shortName: 'RD Utd',
    initials: 'RU',
    sport: 'Soccer',
    roster: [],
    played: 3,
    wins: 2,
    draws: 0,
    losses: 1,
    goalsFor: 7,
    goalsAgainst: 4,
    cleanSheets: 1,
    cards: 2,
    lastMatchDate: 'Feb 14',
  ),
];

const _nrU14Matches = <TeamMatch>[
  TeamMatch(
    id: 'nr-u14-m1',
    opponent: 'vs Eastfield FC',
    date: 'Mar 12',
    result: 'W 3–1',
    clips: 2,
    sizeMb: 380,
  ),
  TeamMatch(
    id: 'nr-u14-m2',
    opponent: 'vs Riverdale Utd',
    date: 'Mar 05',
    result: 'L 0–2',
    clips: 2,
    sizeMb: 180,
  ),
  TeamMatch(
    id: 'nr-u14-m3',
    opponent: 'vs Lakeside',
    date: 'Feb 26',
    result: 'D 1–1',
    clips: 2,
    sizeMb: 540,
  ),
  TeamMatch(
    id: 'nr-u14-m4',
    opponent: 'vs Brookfield',
    date: 'Feb 19',
    result: 'W 2–0',
    clips: 2,
    sizeMb: 220,
  ),
  TeamMatch(
    id: 'nr-u14-m5',
    opponent: 'vs Hillcrest',
    date: 'Feb 12',
    result: 'L 1–3',
    clips: 2,
    sizeMb: 410,
  ),
  TeamMatch(
    id: 'nr-u14-m6',
    opponent: 'vs Glenview',
    date: 'Feb 05',
    result: 'W 4–2',
    clips: 2,
    sizeMb: 620,
  ),
];

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
// Providers
// ---------------------------------------------------------------------------

final teamsProvider = Provider<List<TeamRecord>>((ref) => _seedTeams);

final teamMatchesProvider = Provider.family<List<TeamMatch>, String>((
  ref,
  teamId,
) {
  return teamId == 'nr-u14' ? _nrU14Matches : const [];
});

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

// Currently-connected camera id. UI screens pull telemetry/match streams via
// this. Set by the discovery flow on a successful connect; cleared on
// disconnect.
final activeCameraIdProvider = StateProvider<String?>((ref) => null);

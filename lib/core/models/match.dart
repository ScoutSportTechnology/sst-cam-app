enum Sport {
  unknown,
  soccer,
  basketball,
  americanFootball,
  volleyball,
  hockey,
  baseball,
  rugby,
  other,
}

class TeamInfo {
  const TeamInfo({required this.id, required this.name, this.colorHex});
  final String id;
  final String name;
  final String? colorHex;
}

class PlayerInfo {
  const PlayerInfo({
    required this.id,
    required this.name,
    required this.number,
    this.position,
  });
  final String id;
  final String name;
  final int number;
  final String? position;
}

class MatchConfig {
  const MatchConfig({
    required this.sport,
    required this.periodLengthSeconds,
    required this.numPeriods,
    required this.teamA,
    required this.teamB,
    this.rosterA = const [],
    this.rosterB = const [],
  });

  final Sport sport;
  final int periodLengthSeconds;
  final int numPeriods;
  final TeamInfo teamA;
  final TeamInfo teamB;
  final List<PlayerInfo> rosterA;
  final List<PlayerInfo> rosterB;
}

enum MatchStatus { unknown, notStarted, active, paused, halfTime, finished }

class MatchState {
  const MatchState({
    required this.status,
    required this.currentPeriod,
    required this.timeRemainingSeconds,
    required this.scoreA,
    required this.scoreB,
    required this.teamAId,
    required this.teamBId,
    required this.updatedAt,
    this.elapsedSeconds,
    this.clockRunning,
    this.matchUuid,
  });

  final MatchStatus status;
  final int currentPeriod;
  final int timeRemainingSeconds;
  final int scoreA;
  final int scoreB;
  final String teamAId;
  final String teamBId;
  final DateTime updatedAt;

  // State-health cycle additions — null on firmware predating the fields.

  /// Monotonic seconds since period start, ticked by the firmware's own
  /// runtime loop; NOT clamped at period length. The firmware clock is the
  /// only clock that runs through an app disconnect, so on reconnect it wins.
  final int? elapsedSeconds;

  /// Whether the display clock is currently ticking (clock pause/resume).
  final bool? clockRunning;

  /// The PushSessionConfig `match_uuid` this state belongs to. The app keys
  /// scoreboard persistence and rejoin decisions on (device_id, match_uuid) —
  /// never rehydrate one match's data against another's session.
  final String? matchUuid;

  static MatchState idle() => MatchState(
    status: MatchStatus.notStarted,
    currentPeriod: 0,
    timeRemainingSeconds: 0,
    scoreA: 0,
    scoreB: 0,
    teamAId: '',
    teamBId: '',
    updatedAt: DateTime.now(),
  );
}

enum MatchControlAction { start, stop, pause, resume, nextPeriod }

class BannerEvent {
  const BannerEvent({
    required this.templateId,
    required this.params,
    required this.durationSeconds,
    this.playerId,
  });
  final String templateId;
  final Map<String, String> params;
  final int durationSeconds;
  final String? playerId;
}

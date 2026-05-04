// Plain Dart view models for team data. Wire format lives in proto/team.proto.
//
// All teams, rosters, and per-team match history are owned by the camera.
// The app is a thin client over BleService; these classes are immutable
// snapshots returned from list/create/update calls.

import 'package:flutter/foundation.dart';

const int kShortNameMaxLength = 3;

@immutable
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

@immutable
class TeamRecord {
  const TeamRecord({
    required this.id,
    required this.name,
    required this.shortName,
    required this.sport,
    required this.roster,
    this.hidden = false,
  });

  final String id;
  final String name;

  /// Short label used in row avatars and score overlays. Capped at
  /// [kShortNameMaxLength] characters.
  final String shortName;
  final String sport;
  final List<Player> roster;
  final bool hidden;

  TeamRecord copyWith({
    String? name,
    String? shortName,
    String? sport,
    List<Player>? roster,
    bool? hidden,
  }) {
    return TeamRecord(
      id: id,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      sport: sport ?? this.sport,
      roster: roster ?? this.roster,
      hidden: hidden ?? this.hidden,
    );
  }
}

/// Whether a match has already been played (counts toward stats only) or is
/// scheduled in the future (counts toward stats AND will be recorded /
/// streamed when the camera fires).
enum MatchKind { past, upcoming }

@immutable
class TeamMatch {
  const TeamMatch({
    required this.id,
    required this.opponent,
    required this.date,
    required this.result,
    required this.clips,
    required this.sizeMb,
    this.kind = MatchKind.past,
    this.numPeriods = 0,
    this.periodLengthSeconds = 0,
  });
  final String id;
  final String opponent;
  final String date;

  /// `'W 3–1'` / `'L 0–2'` / `'D 1–1'` for past matches, empty for upcoming.
  final String result;
  final int clips;
  final int sizeMb;
  final MatchKind kind;

  /// Materialized time config for this match — copied from the chosen
  /// `SportPreset` (or supplied directly when the user picks "Custom"). Both
  /// fields are 0 for past matches that pre-date this field.
  final int numPeriods;
  final int periodLengthSeconds;

  /// `'W'` / `'L'` / `'D'` — empty for upcoming matches with no result yet.
  String get outcome => result.isEmpty ? '' : result.substring(0, 1);

  bool get isPlayed => kind == MatchKind.past && result.isNotEmpty;
}

/// Aggregate stats computed from a team's match list. The camera no longer
/// stores these — they're derived from [TeamMatch] entries each time.
@immutable
class TeamStats {
  const TeamStats({
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.cleanSheets,
    required this.lastMatchDate,
  });

  final int played;
  final int wins;
  final int draws;
  final int losses;
  final int goalsFor;
  final int goalsAgainst;
  final int cleanSheets;
  final String lastMatchDate;

  static const empty = TeamStats(
    played: 0,
    wins: 0,
    draws: 0,
    losses: 0,
    goalsFor: 0,
    goalsAgainst: 0,
    cleanSheets: 0,
    lastMatchDate: '—',
  );

  static TeamStats fromMatches(List<TeamMatch> matches) {
    int wins = 0, draws = 0, losses = 0, gf = 0, ga = 0, cs = 0;
    String lastDate = '—';
    var played = 0;
    for (final m in matches) {
      if (!m.isPlayed) continue;
      played++;
      switch (m.outcome) {
        case 'W':
          wins++;
        case 'L':
          losses++;
        case 'D':
          draws++;
      }
      final score = _parseScore(m.result);
      if (score != null) {
        gf += score.$1;
        ga += score.$2;
        if (score.$2 == 0) cs++;
      }
      if (lastDate == '—') lastDate = m.date;
    }
    return TeamStats(
      played: played,
      wins: wins,
      draws: draws,
      losses: losses,
      goalsFor: gf,
      goalsAgainst: ga,
      cleanSheets: cs,
      lastMatchDate: lastDate,
    );
  }

  /// Parse `"W 3–1"` (en-dash) into `(3, 1)`. Returns null if the format
  /// doesn't match — e.g. the result is empty for upcoming matches.
  static (int, int)? _parseScore(String result) {
    final m = RegExp(r'(\d+)[–\-](\d+)').firstMatch(result);
    if (m == null) return null;
    return (int.parse(m.group(1)!), int.parse(m.group(2)!));
  }
}

/// Mutable inputs for create/update. `id` is empty on create — firmware
/// assigns it. On update the id is required and must match an existing team.
@immutable
class TeamDraft {
  const TeamDraft({
    required this.name,
    required this.shortName,
    required this.sport,
    this.id = '',
  });
  final String id;
  final String name;
  final String shortName;
  final String sport;
}

@immutable
class PlayerDraft {
  const PlayerDraft({
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

@immutable
class TeamMatchDraft {
  const TeamMatchDraft({
    required this.opponent,
    required this.date,
    required this.kind,
    this.result = '',
    this.id = '',
    this.numPeriods = 0,
    this.periodLengthSeconds = 0,
  });
  final String id;
  final String opponent;
  final String date;
  final MatchKind kind;

  /// Required when [kind] is [MatchKind.past]; ignored for upcoming.
  final String result;

  /// Materialized time config — copied from the picked `SportPreset` or
  /// entered directly when the user chose "Custom". Required for upcoming
  /// matches; 0 for past entries that only count toward stats.
  final int numPeriods;
  final int periodLengthSeconds;
}

/// The fixed sport vocabulary the app exposes to the user. Mirrors
/// `Sport` in `proto/team.proto`. Order is the order shown in filter chips.
const kSports = <String>[
  'Soccer',
  'Basketball',
  'Hockey',
  'Rugby',
  'Volleyball',
  'Other',
];

/// Available player positions for the form picker. Matches `PlayerPosition`
/// in `proto/team.proto`.
const kPlayerPositions = <String>[
  'Keeper',
  'Defender',
  'Mid',
  'Forward',
  'Other',
];

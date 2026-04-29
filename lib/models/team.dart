// Plain Dart view models for team data. Wire format lives in proto/team.proto.
//
// All teams, rosters, and per-team match history are owned by the camera.
// The app is a thin client over BleService; these classes are immutable
// snapshots returned from list/create/update calls.

import 'package:flutter/foundation.dart';

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
    this.hidden = false,
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
  final bool hidden;

  TeamRecord copyWith({
    String? name,
    String? shortName,
    String? initials,
    String? sport,
    List<Player>? roster,
    bool? hidden,
  }) {
    return TeamRecord(
      id: id,
      name: name ?? this.name,
      shortName: shortName ?? this.shortName,
      initials: initials ?? this.initials,
      sport: sport ?? this.sport,
      roster: roster ?? this.roster,
      played: played,
      wins: wins,
      draws: draws,
      losses: losses,
      goalsFor: goalsFor,
      goalsAgainst: goalsAgainst,
      cleanSheets: cleanSheets,
      cards: cards,
      lastMatchDate: lastMatchDate,
      hidden: hidden ?? this.hidden,
    );
  }
}

@immutable
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

/// Mutable inputs for create/update. `id` is empty on create — firmware
/// assigns it. On update the id is required and must match an existing team.
@immutable
class TeamDraft {
  const TeamDraft({
    required this.name,
    required this.shortName,
    required this.initials,
    required this.sport,
    this.id = '',
  });
  final String id;
  final String name;
  final String shortName;
  final String initials;
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

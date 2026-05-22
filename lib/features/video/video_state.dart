// Video library state — LibraryEvent, LibraryMatch, library providers and
// filter state. Backed by TeamMatchesTable joined with TeamsTable.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos/teams_dao.dart';
import '../../core/models/team.dart';
import '../../core/state/db_providers.dart';
import '../teams/teams_state.dart' show teamsControllerProvider;

export '../../core/models/team.dart';

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
    required this.teamName,
    required this.teamShortName,
    required this.date,
    required this.opponent,
    required this.result,
    required this.sport,
    required this.fullDuration,
    required this.fullSizeMb,
    required this.periodLengthSeconds,
    required this.events,
    required this.downloadState,
  });
  final String id;
  final String teamId;
  final String teamName;
  final String teamShortName;
  final String date;
  final String opponent;
  final String result;
  final String sport;
  final String fullDuration; // 01:23:42
  final int fullSizeMb;
  final int periodLengthSeconds;
  final List<LibraryEvent> events;
  final String downloadState; // 'all-local', 'partial', 'remote'
}

// ---------------------------------------------------------------------------
// Library — backed by TeamMatchesTable joined with TeamsTable.
// Emits the current list of past matches with events parsed from eventsJson.
// ---------------------------------------------------------------------------

final libraryProvider = StreamProvider<List<LibraryMatch>>((ref) {
  final dao = ref.watch(teamsDaoProvider);
  return dao
      .watchPastMatchesForLibrary()
      .map((rows) => rows.map(_rowToLibraryMatch).toList());
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
    teamName: team.name,
    teamShortName: team.shortName,
    date: match.date,
    opponent: match.opponent,
    result: match.result,
    sport: team.sport,
    fullDuration: fullDuration,
    fullSizeMb: match.sizeMb,
    periodLengthSeconds: match.periodLengthSeconds,
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
// Filter / search state for the Library (Video) page.
// ---------------------------------------------------------------------------

final librarySearchQueryProvider = StateProvider<String>((_) => '');
final librarySportFilterProvider = StateProvider<String?>((_) => null); // null = All

/// Team short-name filter for the library page. Null = no team filter.
/// When set to a team's shortName, returns any match where the teamShortName
/// matches OR opponent contains the shortName (case-insensitive).
final libraryTeamFilterProvider = StateProvider<String?>((_) => null);

/// True when the recording file exists at the UUID-derived device storage path.
/// This is the authoritative on-device check (R10) — replaces the sizeMb heuristic.
final isOnDeviceProvider = FutureProvider.family<bool, String>((
  ref,
  matchId,
) async {
  final svc = ref.watch(videoPathServiceProvider);
  final path = await svc.recordingPath(matchId);
  return File(path).existsSync();
});

/// Flat, filtered list of past LibraryMatch records across all teams.
/// Applies sport filter, team filter, and text search simultaneously.
/// Search matches teamName, teamShortName, and opponent string (case-insensitive).
/// Team filter matches if teamShortName == filter OR opponent contains filter.
final filteredLibraryMatchesProvider = Provider<List<LibraryMatch>>((ref) {
  final library = ref.watch(libraryProvider);
  return library.when(
    data: (matches) {
      final query = ref.watch(librarySearchQueryProvider).toLowerCase().trim();
      final sport = ref.watch(librarySportFilterProvider);
      final teamFilter = ref.watch(libraryTeamFilterProvider)?.toLowerCase();

      return matches.where((m) {
        // Sport filter
        if (sport != null && m.sport != sport) return false;

        // Team filter (both sides: recording team or opponent)
        if (teamFilter != null && teamFilter.isNotEmpty) {
          final matchesTeam = m.teamShortName.toLowerCase() == teamFilter;
          final matchesOpponent =
              m.opponent.toLowerCase().contains(teamFilter);
          if (!matchesTeam && !matchesOpponent) return false;
        }

        // Text search (R8: teamName, shortName, or opponent)
        if (query.isNotEmpty) {
          final inTeamName = m.teamName.toLowerCase().contains(query);
          final inShortName = m.teamShortName.toLowerCase().contains(query);
          final inOpponent = m.opponent.toLowerCase().contains(query);
          if (!inTeamName && !inShortName && !inOpponent) return false;
        }

        return true;
      }).toList();
    },
    loading: () => [],
    // ignore: avoid_types_on_closure_parameters
    error: (e, st) => [],
  );
});

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

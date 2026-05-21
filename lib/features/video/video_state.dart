// Video library state — LibraryEvent, LibraryMatch, library providers and
// filter state. Backed by TeamMatchesTable joined with TeamsTable.

import 'dart:convert';

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

/// Per-team aggregated stats derived from the library, excluding remote-only
/// entries. Computed once here so [VideoPage] and any other consumer read from
/// a single reactive snapshot — avoiding the dual-read divergence where the
/// page recomputed inline from `libraryProvider` while
/// `filteredLibraryTeamsProvider` read it separately.
final libraryStatsByTeamProvider =
    Provider<Map<String, ({int matches, int clips, int sizeMb, String date})>>(
  (ref) {
    final library = ref.watch(libraryProvider).valueOrNull ?? const [];
    final byTeam =
        <String, ({int matches, int clips, int sizeMb, String date})>{};
    for (final m in library.where((m) => m.downloadState != 'remote')) {
      final cur =
          byTeam[m.teamId] ?? (matches: 0, clips: 0, sizeMb: 0, date: m.date);
      byTeam[m.teamId] = (
        matches: cur.matches + 1,
        clips: cur.clips + m.events.length + 1,
        sizeMb: cur.sizeMb + m.fullSizeMb,
        date: m.date,
      );
    }
    return byTeam;
  },
);

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

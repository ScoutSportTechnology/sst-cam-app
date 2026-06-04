// Match landing state — upcoming matches joined with teams, filter providers.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/daos/teams_dao.dart';
import '../../core/state/db_providers.dart';
import '../settings/users/users_state.dart' show activeUserProvider;
import '../teams/teams_state.dart'
    show rowToTeamRecord, rowToTeamMatch, TeamRecord, TeamMatch;

export '../../core/models/team.dart';

/// Joined view of an upcoming match with its owning team — used by the
/// Match tab landing list. Built by [upcomingMatchesProvider]; not stored.
@immutable
class UpcomingMatch {
  const UpcomingMatch({required this.team, required this.match});
  final TeamRecord team;
  final TeamMatch match;
  String? get homeColorHex => team.colorHex;
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
  team: rowToTeamRecord(row.team, const []),
  match: rowToTeamMatch(row.match),
);

// ---------------------------------------------------------------------------
// Filter / search state for the Match landing page.
// ---------------------------------------------------------------------------

final upcomingSearchQueryProvider = StateProvider<String>((_) => '');
final upcomingMatchSportFilterProvider =
    StateProvider<String?>((_) => null); // null = All
final upcomingMatchTeamFilterProvider =
    StateProvider<String?>((_) => null); // null = All teams

final filteredUpcomingMatchesProvider = Provider<List<UpcomingMatch>>((ref) {
  final matches = ref.watch(upcomingMatchesProvider).valueOrNull ?? const [];
  final query = ref.watch(upcomingSearchQueryProvider).trim().toLowerCase();
  final sport = ref.watch(upcomingMatchSportFilterProvider);
  final team = ref.watch(upcomingMatchTeamFilterProvider);
  return matches.where((m) {
    if (sport != null && m.team.sport != sport) return false;
    if (team != null && m.team.name != team) return false;
    if (query.isEmpty) return true;
    return m.team.name.toLowerCase().contains(query) ||
        m.match.opponent.toLowerCase().contains(query);
  }).toList();
});

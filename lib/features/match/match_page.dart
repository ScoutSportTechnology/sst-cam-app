import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'landing_screen.dart';
import 'match_state.dart';
import 'session/session_screen.dart';
import 'session/session_state.dart';
import 'setup_screen.dart';

/// The Match tab routes between Landing → Setup → Session based on user
/// selection. The Session screen unifies the old pre-match and live views
/// since the user can run pre-game / post-game recording independently of
/// the period timer. While the match is active it drives a 1 Hz tick into
/// the controller.
class MatchPage extends ConsumerStatefulWidget {
  const MatchPage({super.key});

  @override
  ConsumerState<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends ConsumerState<MatchPage> {
  Timer? _tick;

  /// The upcoming match the user has chosen to set up / play. Null = on the
  /// landing screen. Cleared by `_leave()` when the user pops out of an
  /// ended match.
  UpcomingMatch? _selected;

  /// True once the user has tapped "Start match" on the setup screen.
  /// Drives the Setup → Session transition.
  bool _setupConfirmed = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      ref.read(liveMatchProvider.notifier).tick();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _select(UpcomingMatch up) {
    ref
        .read(liveMatchProvider.notifier)
        .loadFromUpcoming(
          matchId: up.match.id,
          teamShortName: up.team.shortName,
          teamName: up.team.name,
          opponent: up.match.opponent,
          numPeriods: up.match.numPeriods,
          periodLengthSeconds: up.match.periodLengthSeconds,
        );
    setState(() {
      _selected = up;
      _setupConfirmed = false;
    });
  }

  /// Pop out of the live session back to landing. A match played to its end has
  /// been finalized into a 'past' library entry (see _finalizeMatchToLibrary in
  /// session_screen), which also flips it out of the 'upcoming' landing list —
  /// so there is nothing to remove here. Deleting it (the old behavior, when
  /// matches weren't persisted as recordings) would destroy the library entry.
  void _leave() {
    ref.read(liveMatchProvider.notifier).reset();
    setState(() {
      _selected = null;
      _setupConfirmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;

    // Live state owns the truth about whether the user is mid-session.
    // If a match is loaded and we've passed setup, render the session
    // screen for any non-idle phase OR the pre-game (idle) phase too.
    if (selected != null && _setupConfirmed) {
      return SessionScreen(match: selected, onLeave: _leave);
    }

    if (selected == null) {
      return LandingScreen(onSelect: _select);
    }

    return SetupScreen(
      match: selected,
      onBack: () => setState(() => _selected = null),
      onStart: () => setState(() => _setupConfirmed = true),
    );
  }
}

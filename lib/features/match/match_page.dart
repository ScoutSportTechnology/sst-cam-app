import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'landing_screen.dart';
import 'match_state.dart';
import 'session/session_screen.dart';
import 'session/session_state.dart';
import 'setup_screen.dart';
import '../teams/teams_state.dart' show teamsControllerProvider;

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

  /// Pop out of the live session back to landing. When the match ended
  /// naturally we also remove the upcoming entry from the camera so it
  /// no longer shows on the landing list.
  ///
  /// Order matters: we remove the camera-side entry FIRST and only then
  /// flip the local state. Otherwise the landing rebuild can race with
  /// the (mock-delayed) removal and briefly render the just-played match.
  Future<void> _leave({required bool wasEnded}) async {
    final selected = _selected;
    if (wasEnded && selected != null) {
      try {
        await ref
            .read(teamsControllerProvider.notifier)
            .removeMatch(selected.team.id, selected.match.id);
      } catch (_) {
        // Non-fatal: the match may already be gone or the camera may
        // have disconnected. We still want to leave the session.
      }
    }
    if (!mounted) return;
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
      return SessionScreen(
        match: selected,
        onLeave: () => _leave(
          wasEnded: ref.read(liveMatchProvider).phase == MatchPhase.ended,
        ),
      );
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

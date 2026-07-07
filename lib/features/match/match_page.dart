import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_providers.dart' show bleServiceProvider;
import '../../core/models/overlay_layout.dart';
import '../camera/camera_state.dart' show activeCameraIdProvider;
import 'landing_screen.dart';
import 'match_state.dart';
import 'session/session_screen.dart';
import 'session/session_state.dart';
import 'setup_screen.dart';

/// An empty overlay pushed to the camera when a match session ends, so the
/// firmware stops compositing the (now-stale) scoreboard onto the preview.
const _clearOverlayLayout = OverlayLayout(
  canvasWidth: 1280,
  canvasHeight: 720,
  elements: [],
  templates: [],
);

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
    // Resume, don't reset: a live match restored by the connect handshake
    // (rejoin after an app kill, U2) is still listed as upcoming — selecting
    // it re-enters the running session; loadFromUpcoming would wipe the
    // restored scoreboard.
    final live = ref.read(liveMatchProvider);
    if (isLiveMatchRunning(live) &&
        ref.read(liveMatchProvider.notifier).matchId == up.match.id) {
      setState(() {
        _selected = up;
        _setupConfirmed = true;
      });
      return;
    }
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
    _clearCameraOverlay();
    ref.read(liveMatchProvider.notifier).reset();
    setState(() {
      _selected = null;
      _setupConfirmed = false;
    });
  }

  /// Tell the camera to drop the scoreboard when the user leaves the match —
  /// the firmware caches the last rendered overlay and would otherwise keep it
  /// on the preview after the match ends and into the next match.
  void _clearCameraOverlay() {
    final deviceId = ref.read(activeCameraIdProvider);
    if (deviceId == null) return;
    unawaited(
      ref
          .read(bleServiceProvider)
          .pushOverlayLayout(deviceId, _clearOverlayLayout)
          .catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep the firmware→live-match sync (2 s clock correction + poll-truth
    // runtime flags) alive for the whole app session — MatchPage stays
    // mounted in the shell's IndexedStack.
    ref.watch(liveMatchFirmwareSyncProvider);

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

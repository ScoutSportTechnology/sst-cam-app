// U2 seam — persisted live-match scoreboard, keyed by device.
//
// The connect handshake's reconcile step needs the app's persisted match
// (scores keyed by `(device_id, match_uuid)`) to decide between "push app
// scores via SetMatchState" and "adopt the firmware-derived view". U1 ships
// this interface with a no-store default (nothing persisted → every running
// session is adopted); U2 replaces the default with the Drift-backed store
// that persists LiveMatchState on every mutation and restores it on rejoin.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app-owned match facts the reconcile step pushes back to the firmware.
/// Scores are the app's authority — deltas made while disconnected never
/// reached the firmware. The clock is deliberately absent: the firmware clock
/// is the only clock that ran through the disconnect, so it wins (the app
/// adopts it from the snapshot instead).
class PersistedLiveMatch {
  const PersistedLiveMatch({
    required this.matchUuid,
    required this.scoreA,
    required this.scoreB,
  });

  /// The PushSessionConfig `match_uuid` this scoreboard belongs to. Reconcile
  /// only pushes when it equals the running session's uuid — one match's data
  /// must never hydrate against another's session.
  final String matchUuid;
  final int scoreA;
  final int scoreB;
}

/// Port for the persisted live-match store (U2 fills it with Drift).
abstract class PersistedMatchStore {
  /// The persisted scoreboard for [deviceId], or null when nothing was
  /// persisted (first run, cleared store, or the match already finalized).
  Future<PersistedLiveMatch?> load(String deviceId);
}

/// U1 default: nothing is ever persisted, so reconcile always adopts the
/// firmware-derived view. Replaced (via provider override in U2's store
/// wiring) with the Drift-backed implementation.
class NoPersistedMatchStore implements PersistedMatchStore {
  const NoPersistedMatchStore();

  @override
  Future<PersistedLiveMatch?> load(String deviceId) async => null;
}

final persistedMatchStoreProvider = Provider<PersistedMatchStore>(
  (_) => const NoPersistedMatchStore(),
);

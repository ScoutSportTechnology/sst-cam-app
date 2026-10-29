// DriftPersistedMatchStore (U2) — save/load round-trip, device keying, and
// the idempotent uuid-keyed clear the "cleared exactly once" invariant
// leans on.

import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/state/persisted_match_store.dart';

import '../../test_helpers.dart';

void main() {
  final db = useInMemoryDb();
  late DriftPersistedMatchStore store;

  setUp(() => store = DriftPersistedMatchStore(db.value));

  const record = PersistedLiveMatch(
    matchUuid: 'match-1',
    scoreA: 2,
    scoreB: 1,
    libraryMatchId: 'match-1',
    homeName: 'NRA',
    awayName: 'EFC',
    phase: PersistedMatchPhase.period,
    timerRunning: true,
    recPaused: false,
    currentPeriod: 2,
    numPeriods: 2,
    periodLengthSeconds: 2100,
    elapsedSeconds: 754,
    anchorEpochMs: 1780000000000,
    eventsJson:
        '[{"clock":"12:34","label":"Goal · NRA","kind":"event",'
        '"params":{}}]',
    homeColorHex: '#FF0000',
    updatedAtEpochMs: 1780000000000,
  );

  test('save → load round-trips every field', () async {
    await store.save('dev-a', record);
    final loaded = await store.load('dev-a');
    expect(loaded, isNotNull);
    expect(loaded!.matchUuid, 'match-1');
    expect(loaded.scoreA, 2);
    expect(loaded.scoreB, 1);
    expect(loaded.libraryMatchId, 'match-1');
    expect(loaded.homeName, 'NRA');
    expect(loaded.awayName, 'EFC');
    expect(loaded.phase, PersistedMatchPhase.period);
    expect(loaded.timerRunning, isTrue);
    expect(loaded.recPaused, isFalse);
    expect(loaded.currentPeriod, 2);
    expect(loaded.numPeriods, 2);
    expect(loaded.periodLengthSeconds, 2100);
    expect(loaded.elapsedSeconds, 754);
    expect(loaded.anchorEpochMs, 1780000000000);
    expect(loaded.eventsJson, record.eventsJson);
    expect(loaded.homeColorHex, '#FF0000');
    expect(loaded.awayColorHex, isNull);
    expect(loaded.isMidMatch, isTrue);
  });

  test('save is an upsert — the newest snapshot wins per device', () async {
    await store.save('dev-a', record);
    await store.save(
      'dev-a',
      const PersistedLiveMatch(
        matchUuid: 'match-1',
        scoreA: 3,
        scoreB: 1,
        phase: PersistedMatchPhase.period,
      ),
    );
    final loaded = await store.load('dev-a');
    expect(loaded!.scoreA, 3);
  });

  test('device keying — camera A\'s match never loads for camera B', () async {
    await store.save('dev-a', record);
    expect(await store.load('dev-b'), isNull);
  });

  test('clear is keyed by match_uuid — a stale clear never wipes a newer '
      'session\'s row', () async {
    await store.save('dev-a', record);
    await store.clear('dev-a', 'some-older-match');
    expect(await store.load('dev-a'), isNotNull);
    await store.clear('dev-a', 'match-1');
    expect(await store.load('dev-a'), isNull);
    // Idempotent: clearing again (or with no row at all) is a no-op.
    await store.clear('dev-a', 'match-1');
    expect(await store.load('dev-a'), isNull);
  });

  test('effectiveElapsedSeconds counts wall time while running', () {
    const running = PersistedLiveMatch(
      matchUuid: 'm',
      scoreA: 0,
      scoreB: 0,
      timerRunning: true,
      elapsedSeconds: 100,
      anchorEpochMs: 1000000,
    );
    expect(running.effectiveElapsedSeconds(1000000 + 42000), 142);
    // Paused (or no anchor) → frozen.
    const paused = PersistedLiveMatch(
      matchUuid: 'm',
      scoreA: 0,
      scoreB: 0,
      elapsedSeconds: 100,
    );
    expect(paused.effectiveElapsedSeconds(999999999), 100);
  });
}

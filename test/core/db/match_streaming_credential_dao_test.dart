// U5 — per-match streaming credential DAO contract (R19).
//
// getMatchById + setMatchStreamingCredential back both the setup-time write and
// the mid-match read/prompt path. Synthetic credentials only.
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

void main() {
  final db = useInMemoryDb();

  test('credential round-trips and clears; unknown id is null', () async {
    final dao = db.value.teamsDao;
    final match =
        (await db.value.select(db.value.teamMatchesTable).get()).first;

    // Initially no credential.
    final initial = await dao.getMatchById(match.id);
    expect(initial?.id, match.id);
    expect(initial?.rtmpUrl, isNull);
    expect(initial?.streamKey, isNull);

    // Set (saved-destination shape: base url + key).
    await dao.setMatchStreamingCredential(
      match.id,
      rtmpUrl: 'rtmp://test.invalid/app',
      streamKey: 'TEST_KEY_DO_NOT_USE',
    );
    final set = await dao.getMatchById(match.id);
    expect(set?.rtmpUrl, 'rtmp://test.invalid/app');
    expect(set?.streamKey, 'TEST_KEY_DO_NOT_USE');

    // Clear (record-without-streaming).
    await dao.setMatchStreamingCredential(
      match.id,
      rtmpUrl: null,
      streamKey: null,
    );
    final cleared = await dao.getMatchById(match.id);
    expect(cleared?.rtmpUrl, isNull);
    expect(cleared?.streamKey, isNull);

    // Unknown id.
    expect(await dao.getMatchById('no-such-match'), isNull);
  });
}

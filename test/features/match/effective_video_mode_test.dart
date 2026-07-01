// effectiveVideoMode reconciles a held quality pick against the current
// firmware-advertised modes so the DropdownButton value is always in its items
// (a stale value crashes DropdownButton). U12 review follow-up.

import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/models/video_mode.dart';
import 'package:sst_cam_app/features/match/setup_screen.dart';

const _1080p30 = VideoMode(width: 1920, height: 1080, fps: 30);
const _720p60 = VideoMode(width: 1280, height: 720, fps: 60);
const _720p30 = VideoMode(width: 1280, height: 720, fps: 30);
const _advertised = [_1080p30, _720p60, _720p30];

void main() {
  test('empty modes → null (no selection possible)', () {
    expect(effectiveVideoMode(_1080p30, const []), isNull);
    expect(effectiveVideoMode(null, const []), isNull);
  });

  test('held pick is kept while still advertised', () {
    expect(effectiveVideoMode(_720p60, _advertised), _720p60);
  });

  test('no held pick → default (preferred 1080p30 when advertised)', () {
    expect(effectiveVideoMode(null, _advertised), _1080p30);
  });

  test(
    'STALE held pick (no longer advertised) → default, never the stale value',
    () {
      // The crash path: operator picked 1080p60, firmware then re-advertises a set
      // without it. effectiveVideoMode must NOT return the stale value.
      const stale = VideoMode(width: 1920, height: 1080, fps: 60);
      final result = effectiveVideoMode(stale, _advertised);
      expect(result, isNot(stale));
      expect(_advertised.contains(result), isTrue);
      expect(result, _1080p30); // preferred is advertised
    },
  );

  test('default falls back to first when preferred not advertised', () {
    const modes = [_720p60, _720p30]; // no 1080p30
    expect(effectiveVideoMode(null, modes), _720p60);
    // A stale 1080p30 also falls back to first here.
    expect(effectiveVideoMode(_1080p30, modes), _720p60);
  });
}

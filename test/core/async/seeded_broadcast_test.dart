import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/async/seeded_broadcast.dart';

void main() {
  group('SeededBroadcast', () {
    test('replays the initial seed to a subscriber', () async {
      final sb = SeededBroadcast<int>(0);
      expect(sb.stream.first, completion(0));
    });

    test('has no value and replays nothing when unseeded', () async {
      final sb = SeededBroadcast<int>();
      expect(sb.hasValue, isFalse);
      final events = <int>[];
      final sub = sb.stream.listen(events.add);
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      await sub.cancel();
    });

    test(
      'late subscriber receives the current value, not just future events',
      () async {
        final sb = SeededBroadcast<int>(0);
        sb.add(1);
        sb.add(2);
        // Subscribes AFTER the events above were emitted — the bug class this
        // primitive fixes. It must still see the current value (2).
        expect(sb.stream.first, completion(2));
        expect(sb.value, 2);
      },
    );

    test(
      'pre-existing subscriber receives the replay then live events',
      () async {
        final sb = SeededBroadcast<int>(0);
        final events = <int>[];
        final sub = sb.stream.listen(events.add);
        await Future<void>.delayed(Duration.zero);
        sb.add(1);
        sb.add(2);
        await Future<void>.delayed(Duration.zero);
        expect(events, [0, 1, 2]);
        await sub.cancel();
      },
    );

    test('multiple subscribers each get their own replay', () async {
      final sb = SeededBroadcast<String>('a');
      expect(sb.stream.first, completion('a'));
      expect(sb.stream.first, completion('a'));
      sb.add('b');
      expect(sb.stream.first, completion('b'));
    });

    test('add after close is a no-op and does not throw', () async {
      final sb = SeededBroadcast<int>(0);
      await sb.close();
      expect(sb.isClosed, isTrue);
      expect(() => sb.add(1), returnsNormally);
    });
  });
}

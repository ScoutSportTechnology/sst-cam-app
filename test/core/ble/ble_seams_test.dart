import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_seams.dart';

void main() {
  group('ScanLifecycleTracker', () {
    test('a stale `false` before any `true` does not signal "ended"', () {
      final t = ScanLifecycleTracker();
      expect(t.onScanningChanged(false), isFalse);
    });

    test('a `false` after an observed `true` signals "ended"', () {
      final t = ScanLifecycleTracker();
      expect(t.onScanningChanged(true), isFalse); // scan started
      expect(t.onScanningChanged(false), isTrue); // scan ended → teardown
    });

    test(
      'repeated `true`s never signal "ended"; the trailing `false` does',
      () {
        final t = ScanLifecycleTracker();
        expect(t.onScanningChanged(true), isFalse);
        expect(t.onScanningChanged(true), isFalse);
        expect(t.onScanningChanged(false), isTrue);
      },
    );
  });

  group('classifyInboundFrame', () {
    test('total_chunks 0 is an ack frame', () {
      expect(classifyInboundFrame(0), InboundFrameKind.ack);
    });
    test('total_chunks 1 is a single-chunk payload', () {
      expect(classifyInboundFrame(1), InboundFrameKind.singlePayload);
    });
    test('total_chunks >= 2 is a multi-chunk payload', () {
      expect(classifyInboundFrame(2), InboundFrameKind.multiPayload);
      expect(classifyInboundFrame(7), InboundFrameKind.multiPayload);
    });
  });
}

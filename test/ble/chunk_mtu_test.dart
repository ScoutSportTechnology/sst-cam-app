// Host-side chunk-sizing + reassembly across realistic negotiated MTUs. This is
// the #1 hardware bring-up risk (a fixed 400-byte chunk overflows a sub-512 MTU
// GATT write) converted from on-device debugging into a closed-box CI test.

import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_protocol.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/models/proto/bluetooth.pb.dart' as proto;

void main() {
  group('chunkBudgetForMtu', () {
    test('caps at 400 for the default 512 MTU and above', () {
      expect(BleProtocol.chunkBudgetForMtu(512), 400);
      expect(BleProtocol.chunkBudgetForMtu(1024), 400);
    });

    test('scales down with the negotiated MTU', () {
      expect(BleProtocol.chunkBudgetForMtu(247), 247 - 60);
      expect(BleProtocol.chunkBudgetForMtu(185), 185 - 60);
    });

    test('floors at minChunkDataBytes for a tiny MTU (e.g. 23)', () {
      // A 23-byte MTU cannot even carry the 36-byte UUID envelope; the budget
      // floors rather than going negative. Such a link is unworkable and should
      // surface as a connect error, not silent corruption.
      expect(BleProtocol.chunkBudgetForMtu(23), BleProtocol.minChunkDataBytes);
    });
  });

  group('encode + reassemble round-trip at each MTU', () {
    // A command large enough to span many chunks even at a 400-byte budget.
    final bigCommand = DownloadRequestCommand(recordingId: 'r' * 3000);

    for (final mtu in [185, 247, 512]) {
      test('MTU $mtu: multi-chunk frames reassemble to the original', () {
        const corrId = 'mtu-test';
        final budget = BleProtocol.chunkBudgetForMtu(mtu);
        final frames = BleProtocol.encodeCommandFrames(
          bigCommand,
          corrId,
          maxDataBytes: budget,
        );

        expect(frames.length, greaterThan(1), reason: 'should split');

        final chunks = frames.map(proto.ChunkedPayload.fromBuffer).toList();

        // Every frame's data fits the budget; indices are sequential; totals agree.
        for (var i = 0; i < chunks.length; i++) {
          expect(chunks[i].data.length, lessThanOrEqualTo(budget));
          expect(chunks[i].chunkIndex, i);
          expect(chunks[i].totalChunks, chunks.length);
          expect(chunks[i].correlationId, corrId);
        }

        // Reassemble OUT OF ORDER (reversed) — index-addressed, so it still works.
        final reassembler = ChunkReassembler();
        List<int>? assembled;
        for (final chunk in chunks.reversed) {
          assembled = reassembler.add(chunk) ?? assembled;
        }
        expect(assembled, isNotNull);

        final decoded = proto.Command.fromBuffer(assembled!);
        expect(decoded.correlationId, corrId);
        expect(decoded.downloadRequest.recordingId, 'r' * 3000);
      });
    }
  });

  test('a single small command at a low MTU still produces valid frames', () {
    final frames = BleProtocol.encodeCommandFrames(
      GetTelemetryCommand(),
      'c',
      maxDataBytes: BleProtocol.chunkBudgetForMtu(185),
    );
    final reassembler = ChunkReassembler();
    List<int>? assembled;
    for (final f in frames) {
      assembled =
          reassembler.add(proto.ChunkedPayload.fromBuffer(f)) ?? assembled;
    }
    expect(proto.Command.fromBuffer(assembled!).hasGetTelemetry(), isTrue);
  });
}

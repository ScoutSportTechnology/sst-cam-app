import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_protocol.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/telemetry.dart';
import 'package:sst_cam_app/models/proto/bluetooth.pb.dart' as proto;

void main() {
  group('BleProtocol.encodeCommand', () {
    test(
      'GetTelemetryCommand produces non-empty bytes decodable as Command',
      () {
        const corrId = 'test-corr-id-001';
        final bytes = BleProtocol.encodeCommand(GetTelemetryCommand(), corrId);
        expect(bytes, isNotEmpty);

        final chunk = proto.ChunkedPayload.fromBuffer(bytes);
        expect(chunk.correlationId, corrId);
        expect(chunk.chunkIndex, 0);
        expect(chunk.totalChunks, 1);

        final cmd = proto.Command.fromBuffer(chunk.data);
        expect(cmd.hasGetTelemetry(), isTrue);
      },
    );

    test('GetMatchStateCommand sets getMatchState oneof field', () {
      final bytes = BleProtocol.encodeCommand(GetMatchStateCommand(), 'cid');
      final chunk = proto.ChunkedPayload.fromBuffer(bytes);
      final cmd = proto.Command.fromBuffer(chunk.data);
      expect(cmd.hasGetMatchState(), isTrue);
    });

    test('correlationId is preserved through the ChunkedPayload wrapper', () {
      const corrId = 'unique-corr-id-abc123';
      final bytes = BleProtocol.encodeCommand(GetTelemetryCommand(), corrId);
      final chunk = proto.ChunkedPayload.fromBuffer(bytes);
      expect(chunk.correlationId, corrId);
    });
  });

  group('BleProtocol.decodeResponse', () {
    test(
      'valid telemetry response decodes to BleCommandResponse<DeviceTelemetry>',
      () {
        const corrId = 'test-corr-id';
        final protoResp = proto.CommandResponse(
          correlationId: corrId,
          status: proto.ResponseStatus.OK,
          telemetry: proto.DeviceTelemetry(
            storageFreeBytes: Int64(100 * 1024 * 1024),
            storageTotalBytes: Int64(256 * 1024 * 1024),
            wifiState: proto.WifiState.WIFI_CONNECTED,
            tempCelsius: 48.5,
            ramUsedPct: 0.5,
            cpuUsedPct: 0.3,
            uptimeSeconds: Int64(3600),
            internetReachable: true,
            isRecording: false,
            isStreaming: false,
          ),
        );
        final chunk = proto.ChunkedPayload(
          correlationId: corrId,
          chunkIndex: 0,
          totalChunks: 1,
          data: protoResp.writeToBuffer(),
        );
        final bytes = chunk.writeToBuffer();

        final resp = BleProtocol.decodeResponse<DeviceTelemetry>(
          bytes,
          GetTelemetryCommand(),
          corrId,
        );
        expect(resp.isOk, isTrue);
        final t = resp.payload!;
        expect(t.storageTotalBytes, 256 * 1024 * 1024);
        expect(t.tempCelsius, closeTo(48.5, 0.1));
        expect(t.wifiState, WifiState.connected);
      },
    );

    test('malformed bytes produce a BleCommandResponse with error status', () {
      final resp = BleProtocol.decodeResponse<DeviceTelemetry>(
        [0x00, 0xFF, 0xAB, 0xCD], // garbage bytes
        GetTelemetryCommand(),
        'any-id',
      );
      expect(resp.isOk, isFalse);
      expect(resp.status, BleResponseStatus.error);
      expect(resp.errorMessage, isNotNull);
    });

    test('correlation_id mismatch produces error status', () {
      final protoResp = proto.CommandResponse(
        correlationId: 'original-id',
        status: proto.ResponseStatus.OK,
        telemetry: proto.DeviceTelemetry(storageTotalBytes: Int64(1024)),
      );
      final chunk = proto.ChunkedPayload(
        correlationId: 'original-id',
        chunkIndex: 0,
        totalChunks: 1,
        data: protoResp.writeToBuffer(),
      );
      final bytes = chunk.writeToBuffer();

      final resp = BleProtocol.decodeResponse<DeviceTelemetry>(
        bytes,
        GetTelemetryCommand(),
        'different-id', // mismatch
      );
      expect(resp.isOk, isFalse);
      expect(resp.status, BleResponseStatus.error);
    });

    test('TIMEOUT response status maps to BleResponseStatus.timeout', () {
      const corrId = 'timeout-test';
      final protoResp = proto.CommandResponse(
        correlationId: corrId,
        status: proto.ResponseStatus.TIMEOUT,
      );
      final chunk = proto.ChunkedPayload(
        correlationId: corrId,
        chunkIndex: 0,
        totalChunks: 1,
        data: protoResp.writeToBuffer(),
      );
      final bytes = chunk.writeToBuffer();

      final resp = BleProtocol.decodeResponse<DeviceTelemetry>(
        bytes,
        GetTelemetryCommand(),
        corrId,
      );
      expect(resp.isOk, isFalse);
      expect(resp.status, BleResponseStatus.timeout);
    });
  });
}

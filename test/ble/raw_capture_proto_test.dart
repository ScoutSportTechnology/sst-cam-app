import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_protocol.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/recording.dart';
import 'package:sst_cam_app/core/models/telemetry.dart';
import 'package:sst_cam_app/models/proto/bluetooth.pb.dart' as proto;

proto.Command _decodeCommand(List<int> frame) {
  final chunk = proto.ChunkedPayload.fromBuffer(frame);
  return proto.Command.fromBuffer(chunk.data);
}

List<int> _wrap(proto.CommandResponse resp, String corrId) {
  return proto.ChunkedPayload(
    correlationId: corrId,
    chunkIndex: 0,
    totalChunks: 1,
    data: resp.writeToBuffer(),
  ).writeToBuffer();
}

void main() {
  group('RawCaptureControlCommand encode', () {
    test('start carries action + app-minted captureGroupId', () {
      final cmd = _decodeCommand(
        BleProtocol.encodeCommandFrames(
          RawCaptureControlCommand(
            action: RecordingControlAction.start,
            captureGroupId: 'grp-abc',
          ),
          'c1',
        ).first,
      );
      expect(cmd.hasRawCapture(), isTrue);
      expect(cmd.rawCapture.action, proto.RecordingAction.RECORDING_START);
      expect(cmd.rawCapture.hasCaptureGroupId(), isTrue);
      expect(cmd.rawCapture.captureGroupId, 'grp-abc');
    });

    test('stop carries STOP and no captureGroupId', () {
      final cmd = _decodeCommand(
        BleProtocol.encodeCommandFrames(
          RawCaptureControlCommand(action: RecordingControlAction.stop),
          'c2',
        ).first,
      );
      expect(cmd.rawCapture.action, proto.RecordingAction.RECORDING_STOP);
      expect(cmd.rawCapture.hasCaptureGroupId(), isFalse);
    });
  });

  group('telemetry isRawCapturing decode', () {
    DeviceTelemetry decode(proto.DeviceTelemetry t) {
      const corrId = 'c';
      final resp = BleProtocol.decodeResponse<DeviceTelemetry>(
        _wrap(
          proto.CommandResponse(
            correlationId: corrId,
            status: proto.ResponseStatus.OK,
            telemetry: t,
          ),
          corrId,
        ),
        corrId,
      );
      return resp.payload!;
    }

    test('present true decodes to true', () {
      expect(
        decode(proto.DeviceTelemetry(isRawCapturing: true)).isRawCapturing,
        isTrue,
      );
    });

    test('absent decodes to false', () {
      expect(decode(proto.DeviceTelemetry()).isRawCapturing, isFalse);
    });
  });

  group('raw RecordingMetadata decode (not compiler-guarded)', () {
    List<RecordingMetadata> decodeList(List<proto.RecordingMetadata> recs) {
      const corrId = 'c';
      final resp = BleProtocol.decodeResponse<List<RecordingMetadata>>(
        _wrap(
          proto.CommandResponse(
            correlationId: corrId,
            status: proto.ResponseStatus.OK,
            recordingList: proto.RecordingListResponse(recordings: recs),
          ),
          corrId,
        ),
        corrId,
      );
      return resp.payload!;
    }

    test('raw file decodes identity; final leaves them null/false', () {
      final list = decodeList([
        proto.RecordingMetadata(
          id: 'raw__grp__cam1',
          isRaw: true,
          cameraIndex: 1,
          captureGroupId: 'grp',
        ),
        proto.RecordingMetadata(id: 'match-x'),
      ]);
      final raw = list.firstWhere((r) => r.isRaw);
      expect(raw.cameraIndex, 1);
      expect(raw.captureGroupId, 'grp');

      final fin = list.firstWhere((r) => !r.isRaw);
      expect(fin.cameraIndex, isNull);
      expect(fin.captureGroupId, isNull);
    });
  });
}

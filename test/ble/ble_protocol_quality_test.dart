import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_protocol.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/video_mode.dart';
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
  group('record/stream quality encode (U12/R15)', () {
    test('recording start carries record quality on the wire', () {
      final cmd = _decodeCommand(
        BleProtocol.encodeCommandFrames(
          RecordingControlCommand(
            action: RecordingControlAction.start,
            quality: const VideoMode(width: 1920, height: 1080, fps: 30),
          ),
          'c1',
        ).first,
      );
      expect(cmd.recordingControl.hasQuality(), isTrue);
      expect(cmd.recordingControl.quality.width, 1920);
      expect(cmd.recordingControl.quality.height, 1080);
      expect(cmd.recordingControl.quality.fps, 30);
    });

    test('streaming start carries an independent stream quality', () {
      final cmd = _decodeCommand(
        BleProtocol.encodeCommandFrames(
          StreamingControlCommand(
            action: StreamingControlAction.start,
            rtmpUrl: 'rtmp://ingest/live/k',
            quality: const VideoMode(width: 1280, height: 720, fps: 60),
          ),
          'c2',
        ).first,
      );
      expect(cmd.streamingControl.hasQuality(), isTrue);
      expect(cmd.streamingControl.quality.width, 1280);
      expect(cmd.streamingControl.quality.height, 720);
      expect(cmd.streamingControl.quality.fps, 60);
      expect(cmd.streamingControl.destination, 'rtmp://ingest/live/k');
    });

    test('no quality → the optional wire field stays unset', () {
      final rec = _decodeCommand(
        BleProtocol.encodeCommandFrames(
          RecordingControlCommand(action: RecordingControlAction.stop),
          'c3',
        ).first,
      );
      expect(rec.recordingControl.hasQuality(), isFalse);

      final stream = _decodeCommand(
        BleProtocol.encodeCommandFrames(
          StreamingControlCommand(action: StreamingControlAction.stop),
          'c4',
        ).first,
      );
      expect(stream.streamingControl.hasQuality(), isFalse);
    });
  });

  group('DeviceInfo supported_modes decode (U12/R16)', () {
    test('advertised modes decode into the DeviceInfoResponse model', () {
      const corrId = 'c';
      final resp = BleProtocol.decodeResponse<DeviceInfoResponse>(
        _wrap(
          proto.CommandResponse(
            correlationId: corrId,
            status: proto.ResponseStatus.OK,
            deviceInfo: proto.DeviceInfoResponse(
              deviceId: 'dev',
              protocolVersion: kAppProtocolVersion,
              supportedModes: [
                proto.VideoQuality(width: 1920, height: 1080, fps: 60),
                proto.VideoQuality(width: 1280, height: 720, fps: 30),
              ],
            ),
          ),
          corrId,
        ),
        corrId,
      );
      final modes = resp.payload!.supportedModes;
      expect(modes, hasLength(2));
      expect(modes[0], const VideoMode(width: 1920, height: 1080, fps: 60));
      expect(modes[1], const VideoMode(width: 1280, height: 720, fps: 30));
    });

    test('empty supported_modes → empty list, no crash', () {
      const corrId = 'c';
      final resp = BleProtocol.decodeResponse<DeviceInfoResponse>(
        _wrap(
          proto.CommandResponse(
            correlationId: corrId,
            status: proto.ResponseStatus.OK,
            deviceInfo: proto.DeviceInfoResponse(
              deviceId: 'dev',
              protocolVersion: kAppProtocolVersion,
            ),
          ),
          corrId,
        ),
        corrId,
      );
      expect(resp.payload!.supportedModes, isEmpty);
    });
  });
}

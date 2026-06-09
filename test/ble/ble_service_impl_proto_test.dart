import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_protocol.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/telemetry.dart';
import 'package:sst_cam_app/core/models/wifi.dart';
import 'package:sst_cam_app/models/proto/bluetooth.pb.dart' as proto;

// Reassembles a list of ChunkedPayload frames (sharing a correlation id) into
// the inner Command, mirroring the firmware's index-addressed reassembly.
proto.Command _reassembleCommand(List<Uint8List> frames) {
  final byIndex = <int, List<int>>{};
  var total = 1;
  for (final f in frames) {
    final c = proto.ChunkedPayload.fromBuffer(f);
    byIndex[c.chunkIndex] = c.data;
    total = c.totalChunks;
  }
  final assembled = <int>[];
  for (var i = 0; i < total; i++) {
    assembled.addAll(byIndex[i]!);
  }
  return proto.Command.fromBuffer(assembled);
}

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
        corrId,
      );
      expect(resp.isOk, isFalse);
      expect(resp.status, BleResponseStatus.timeout);
    });
  });

  // ===========================================================================
  // U1 — push_session_config encoding
  // ===========================================================================
  group('BleProtocol.encodeSessionConfig (U1)', () {
    PushSessionConfig fullConfig({String? rtmpUrl, String? streamKey}) =>
        PushSessionConfig(
          matchUuid: 'match-1',
          userUuid: 'user-1',
          sport: 'soccer',
          numPeriods: 2,
          periodLengthSeconds: 2700,
          rtmpUrl: rtmpUrl,
          streamKey: streamKey,
          videoOutputPath: '/data/video/user-1/match-1/',
          thumbnailOutputPath: '/data/thumbnail/user-1/match-1/',
          teamAId: 'team-a',
          teamBId: 'team-b',
          teamAName: 'North Rovers',
          teamBName: 'East FC',
          teamAColorHex: '#FF5733',
          teamBColorHex: '#33A1FF',
        );

    test('happy path — every contract field is present on the wire', () {
      const corrId = 'sc-1';
      final bytes = BleProtocol.encodeSessionConfig(fullConfig(), corrId);
      final chunk = proto.ChunkedPayload.fromBuffer(bytes);
      expect(chunk.correlationId, corrId);
      final cmd = proto.Command.fromBuffer(chunk.data);
      expect(cmd.hasPushSessionConfig(), isTrue);

      final c = cmd.pushSessionConfig;
      expect(c.matchUuid, 'match-1');
      expect(c.userUuid, 'user-1');
      expect(c.sport, 'soccer');
      expect(c.numPeriods, 2);
      expect(c.periodLengthSeconds, 2700);
      expect(c.videoOutputPath, '/data/video/user-1/match-1/');
      expect(c.thumbnailOutputPath, '/data/thumbnail/user-1/match-1/');
      expect(c.teamAId, 'team-a');
      expect(c.teamBId, 'team-b');
      expect(c.teamAName, 'North Rovers');
      expect(c.teamBName, 'East FC');
      expect(c.teamAColorHex, '#FF5733');
      expect(c.teamBColorHex, '#33A1FF');
    });

    test('edge — absent rtmp_url/stream_key encode as unset (not empty)', () {
      final bytes = BleProtocol.encodeSessionConfig(fullConfig(), 'sc-2');
      final cmd = proto.Command.fromBuffer(
        proto.ChunkedPayload.fromBuffer(bytes).data,
      );
      final c = cmd.pushSessionConfig;
      expect(c.hasRtmpUrl(), isFalse);
      expect(c.hasStreamKey(), isFalse);
    });

    test('present rtmp_url/stream_key are set on the wire', () {
      final bytes = BleProtocol.encodeSessionConfig(
        fullConfig(rtmpUrl: 'rtmp://x/y', streamKey: 'key-123'),
        'sc-3',
      );
      final cmd = proto.Command.fromBuffer(
        proto.ChunkedPayload.fromBuffer(bytes).data,
      );
      final c = cmd.pushSessionConfig;
      expect(c.hasRtmpUrl(), isTrue);
      expect(c.rtmpUrl, 'rtmp://x/y');
      expect(c.hasStreamKey(), isTrue);
      expect(c.streamKey, 'key-123');
    });

    test('frames reassemble to a push_session_config Command', () {
      final frames =
          BleProtocol.encodeSessionConfigFrames(fullConfig(), 'sc-4');
      final cmd = _reassembleCommand(frames);
      expect(cmd.hasPushSessionConfig(), isTrue);
      expect(cmd.pushSessionConfig.matchUuid, 'match-1');
    });
  });

  // ===========================================================================
  // U2 — banner_event params + player_id
  // ===========================================================================
  group('BleProtocol banner_event params/player_id (U2)', () {
    test('happy path — jersey populates params + player_id', () {
      final frames = BleProtocol.encodeCommandFrames(
        BannerEventCommand(
          templateId: 'goal',
          durationSeconds: 5,
          params: const {'jersey': '10'},
          playerId: '10',
        ),
        'b-1',
      );
      final cmd = _reassembleCommand(frames);
      expect(cmd.hasBannerEvent(), isTrue);
      expect(cmd.bannerEvent.templateId, 'goal');
      expect(cmd.bannerEvent.params['jersey'], '10');
      expect(cmd.bannerEvent.playerId, '10');
    });

    test('edge — no params encodes empty map + empty player_id, no crash', () {
      final frames = BleProtocol.encodeCommandFrames(
        BannerEventCommand(templateId: 'red_card', durationSeconds: 4),
        'b-2',
      );
      final cmd = _reassembleCommand(frames);
      expect(cmd.bannerEvent.params, isEmpty);
      expect(cmd.bannerEvent.playerId, isEmpty);
    });
  });

  // ===========================================================================
  // U3 — outbound chunking over MTU
  // ===========================================================================
  group('BleProtocol.encodeCommandFrames chunking (U3)', () {
    test('sub-MTU command emits exactly one frame {0, 1}', () {
      final frames =
          BleProtocol.encodeCommandFrames(GetTelemetryCommand(), 'c-1');
      expect(frames.length, 1);
      final chunk = proto.ChunkedPayload.fromBuffer(frames.single);
      expect(chunk.chunkIndex, 0);
      expect(chunk.totalChunks, 1);
    });

    test('command just over chunk size emits 2 ordered frames, same corrId', () {
      // Build a banner event whose serialized form exceeds maxChunkDataBytes.
      final big = 'x' * (BleProtocol.maxChunkDataBytes + 50);
      final frames = BleProtocol.encodeCommandFrames(
        BannerEventCommand(
          templateId: big,
          durationSeconds: 1,
        ),
        'c-2',
      );
      expect(frames.length, 2);
      final f0 = proto.ChunkedPayload.fromBuffer(frames[0]);
      final f1 = proto.ChunkedPayload.fromBuffer(frames[1]);
      expect(f0.chunkIndex, 0);
      expect(f1.chunkIndex, 1);
      expect(f0.totalChunks, 2);
      expect(f1.totalChunks, 2);
      expect(f0.correlationId, 'c-2');
      expect(f1.correlationId, 'c-2');
      // Each frame's data within the budget.
      expect(f0.data.length, lessThanOrEqualTo(BleProtocol.maxChunkDataBytes));
      // Reassembly reproduces the command.
      expect(_reassembleCommand(frames).bannerEvent.templateId, big);
    });

    test('large overlay layout splits into the expected frame count', () {
      // A push_overlay_layout payload built from the default scoreboard has
      // many elements/templates and exceeds a single frame.
      final frames = BleProtocol.encodeCommandFrames(
        BannerEventCommand(
          templateId: 'y' * (BleProtocol.maxChunkDataBytes * 3),
          durationSeconds: 1,
        ),
        'c-3',
      );
      expect(frames.length, greaterThanOrEqualTo(3));
      for (var i = 0; i < frames.length; i++) {
        final c = proto.ChunkedPayload.fromBuffer(frames[i]);
        expect(c.chunkIndex, i);
        expect(c.totalChunks, frames.length);
      }
    });

    test('encodeChunkAck builds an ack frame with total_chunks == 0', () {
      final ackBytes = BleProtocol.encodeChunkAck('c-4', 2);
      final ack = proto.ChunkedPayload.fromBuffer(ackBytes);
      expect(ack.correlationId, 'c-4');
      expect(ack.chunkIndex, 2);
      expect(ack.totalChunks, 0);
    });
  });

  // ===========================================================================
  // U5 — parse by payload variant; version + status handling
  // ===========================================================================
  group('BleProtocol.decodeResponse by payload variant (U5)', () {
    Uint8List wrap(proto.CommandResponse resp) {
      return Uint8List.fromList(
        proto.ChunkedPayload(
          correlationId: resp.correlationId,
          chunkIndex: 0,
          totalChunks: 1,
          data: resp.writeToBuffer(),
        ).writeToBuffer(),
      );
    }

    test('device_info decodes with all fields when version matches', () {
      const corrId = 'd-1';
      final bytes = wrap(
        proto.CommandResponse(
          correlationId: corrId,
          status: proto.ResponseStatus.OK,
          deviceInfo: proto.DeviceInfoResponse(
            deviceId: 'dev-1',
            name: 'sst-cam-1',
            firmwareVersion: '1.2.3',
            model: 'jetson',
            protocolVersion: kAppProtocolVersion,
          ),
        ),
      );
      final resp = BleProtocol.decodeResponse<DeviceInfoResponse>(
        bytes,
        corrId,
      );
      expect(resp.isOk, isTrue);
      final info = resp.payload!;
      expect(info.deviceId, 'dev-1');
      expect(info.name, 'sst-cam-1');
      expect(info.firmwareVersion, '1.2.3');
      expect(info.model, 'jetson');
      expect(info.protocolVersion, kAppProtocolVersion);
    });

    test('protocol_version mismatch raises a version-skew error', () {
      const corrId = 'd-2';
      final bytes = wrap(
        proto.CommandResponse(
          correlationId: corrId,
          status: proto.ResponseStatus.OK,
          deviceInfo: proto.DeviceInfoResponse(
            deviceId: 'dev-2',
            protocolVersion: kAppProtocolVersion + 99,
          ),
        ),
      );
      final resp = BleProtocol.decodeResponse<DeviceInfoResponse>(
        bytes,
        corrId,
      );
      expect(resp.isOk, isFalse);
      expect(resp.status, BleResponseStatus.error);
      expect(resp.errorMessage, contains('Protocol version mismatch'));
    });

    test('telemetry decode includes battery_level_pct', () {
      const corrId = 't-1';
      final bytes = wrap(
        proto.CommandResponse(
          correlationId: corrId,
          status: proto.ResponseStatus.OK,
          telemetry: proto.DeviceTelemetry(
            storageTotalBytes: Int64(1024),
            batteryLevelPct: 77,
          ),
        ),
      );
      final resp = BleProtocol.decodeResponse<DeviceTelemetry>(
        bytes,
        corrId,
      );
      expect(resp.isOk, isTrue);
      expect(resp.payload!.batteryLevelPct, 77);
    });

    test('telemetry without battery_level_pct decodes as null', () {
      const corrId = 't-2';
      final bytes = wrap(
        proto.CommandResponse(
          correlationId: corrId,
          status: proto.ResponseStatus.OK,
          telemetry: proto.DeviceTelemetry(storageTotalBytes: Int64(1)),
        ),
      );
      final resp = BleProtocol.decodeResponse<DeviceTelemetry>(
        bytes,
        corrId,
      );
      expect(resp.payload!.batteryLevelPct, isNull);
    });

    test('wifi_direct_group decodes from its own payload', () {
      const corrId = 'w-1';
      final bytes = wrap(
        proto.CommandResponse(
          correlationId: corrId,
          status: proto.ResponseStatus.OK,
          wifiDirectGroup: proto.WifiDirectGroupResponse(
            ssid: 'cam-ap',
            psk: 'secret',
            groupOwnerIp: '192.168.49.1',
            previewPort: 8554,
            downloadPort: 8080,
            role: 'go',
          ),
        ),
      );
      final resp = BleProtocol.decodeResponse<WifiDirectGroup>(
        bytes,
        corrId,
      );
      expect(resp.isOk, isTrue);
      expect(resp.payload!.ssid, 'cam-ap');
      expect(resp.payload!.role, 'go');
    });

    test('parsing is driven by payload, not outbound command type', () {
      // Outbound command says GetTelemetry, but firmware actually returned
      // a device_info payload — decode must follow the payload.
      const corrId = 'p-1';
      final bytes = wrap(
        proto.CommandResponse(
          correlationId: corrId,
          status: proto.ResponseStatus.OK,
          deviceInfo: proto.DeviceInfoResponse(
            deviceId: 'mismatch',
            protocolVersion: kAppProtocolVersion,
          ),
        ),
      );
      final resp = BleProtocol.decodeResponse<DeviceInfoResponse>(
        bytes,
        corrId,
      );
      expect(resp.isOk, isTrue);
      expect(resp.payload, isA<DeviceInfoResponse>());
      expect(resp.payload!.deviceId, 'mismatch');
    });

    test('UNSUPPORTED surfaces distinctly from generic ERROR', () {
      const corrId = 'u-1';
      final bytes = wrap(
        proto.CommandResponse(
          correlationId: corrId,
          status: proto.ResponseStatus.UNSUPPORTED,
          errorMessage: 'no can do',
        ),
      );
      final resp = BleProtocol.decodeResponse<void>(
        bytes,
        corrId,
      );
      expect(resp.status, BleResponseStatus.unsupported);
      expect(resp.isOk, isFalse);
      expect(resp.errorMessage, 'no can do');
    });

    test('ERROR maps to error status, preserving error_message', () {
      const corrId = 'e-1';
      final bytes = wrap(
        proto.CommandResponse(
          correlationId: corrId,
          status: proto.ResponseStatus.ERROR,
          errorMessage: 'boom',
        ),
      );
      final resp = BleProtocol.decodeResponse<void>(
        bytes,
        corrId,
      );
      expect(resp.status, BleResponseStatus.error);
      expect(resp.errorMessage, 'boom');
    });

    test('OK control response with no payload decodes to ok(null)', () {
      const corrId = 'ok-1';
      final bytes = wrap(
        proto.CommandResponse(
          correlationId: corrId,
          status: proto.ResponseStatus.OK,
        ),
      );
      final resp = BleProtocol.decodeResponse<Object>(
        bytes,
        corrId,
      );
      expect(resp.isOk, isTrue);
      expect(resp.payload, isNull);
    });

    test('session-config OK response decodes via dedicated decoder', () {
      const corrId = 'sok-1';
      final bytes = wrap(
        proto.CommandResponse(
          correlationId: corrId,
          status: proto.ResponseStatus.OK,
        ),
      );
      final resp =
          BleProtocol.decodeSessionConfigResponse(bytes, corrId);
      expect(resp.isOk, isTrue);
    });

    test('session-config UNSUPPORTED decodes distinctly', () {
      const corrId = 'sok-2';
      final bytes = wrap(
        proto.CommandResponse(
          correlationId: corrId,
          status: proto.ResponseStatus.UNSUPPORTED,
        ),
      );
      final resp =
          BleProtocol.decodeSessionConfigResponse(bytes, corrId);
      expect(resp.status, BleResponseStatus.unsupported);
    });
  });

  // ===========================================================================
  // U4 — inbound chunk reassembly by index
  // ===========================================================================
  group('ChunkReassembler (U4)', () {
    proto.ChunkedPayload frame(int index, int total, List<int> data) =>
        proto.ChunkedPayload(
          correlationId: 'r-1',
          chunkIndex: index,
          totalChunks: total,
          data: data,
        );

    test('happy path — 3 in-order chunks reassemble to the full payload', () {
      final r = ChunkReassembler();
      expect(r.add(frame(0, 3, [1, 2])), isNull);
      expect(r.add(frame(1, 3, [3, 4])), isNull);
      expect(r.add(frame(2, 3, [5, 6])), [1, 2, 3, 4, 5, 6]);
    });

    test('edge — out-of-order arrival reassembles by index, not arrival', () {
      final r = ChunkReassembler();
      expect(r.add(frame(2, 3, [5, 6])), isNull);
      expect(r.add(frame(0, 3, [1, 2])), isNull);
      expect(r.add(frame(1, 3, [3, 4])), [1, 2, 3, 4, 5, 6]);
    });

    test('edge — duplicate chunk index is ignored, not double-counted', () {
      final r = ChunkReassembler();
      r.add(frame(0, 2, [1, 2]));
      r.add(frame(0, 2, [1, 2])); // duplicate
      expect(r.received, 1);
      expect(r.add(frame(1, 2, [3, 4])), [1, 2, 3, 4]);
    });

    test('does not complete until all indices present', () {
      final r = ChunkReassembler();
      expect(r.add(frame(0, 3, [1])), isNull);
      expect(r.add(frame(2, 3, [3])), isNull);
      expect(r.total, 3);
      expect(r.received, 2);
    });

    test('integration — multi-chunk response decodes end-to-end', () {
      // Build a large recording_list response, split it the way the firmware
      // would, then reassemble via ChunkReassembler and decode.
      final big = proto.CommandResponse(
        correlationId: 'rl-1',
        status: proto.ResponseStatus.OK,
        recordingList: proto.RecordingListResponse(
          recordings: List.generate(
            40,
            (i) => proto.RecordingMetadata(
              id: 'rec-$i',
              durationS: Int64(120),
              sizeBytes: Int64(1024 * 1024),
              startedAt: Int64(1700000000),
              sport: 'soccer',
              teams: 'A vs B',
            ),
          ),
        ),
      );
      final data = big.writeToBuffer();
      const chunkSize = 100;
      final total = (data.length + chunkSize - 1) ~/ chunkSize;
      final r = ChunkReassembler();
      List<int>? assembled;
      for (var i = 0; i < total; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize).clamp(0, data.length);
        assembled = r.add(
          proto.ChunkedPayload(
            correlationId: 'rl-1',
            chunkIndex: i,
            totalChunks: total,
            data: data.sublist(start, end),
          ),
        );
      }
      expect(assembled, isNotNull);
      final decoded = proto.CommandResponse.fromBuffer(assembled!);
      expect(decoded.recordingList.recordings.length, 40);
      expect(decoded.recordingList.recordings.first.id, 'rec-0');
    });
  });
}

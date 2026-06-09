import 'dart:math' as math;
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/command.dart';
import '../models/device.dart';
import '../models/match.dart';
import '../models/overlay_layout.dart';
import '../models/recording.dart';
import '../models/telemetry.dart';
import '../models/wifi.dart';
import '../../models/proto/bluetooth.pb.dart' as proto;

const _uuid = Uuid();

/// Stateless proto encode/decode helpers for the BLE control plane.
///
/// Encodes [BleCommand] → ChunkedPayload-wrapped [proto.Command] bytes and
/// decodes ChunkedPayload bytes → [BleCommandResponse<T>]. Keeping this logic
/// separate from [BleServiceImpl] allows unit tests to verify the wire format
/// without a real GATT connection.
class BleProtocol {
  BleProtocol._();

  /// Maximum number of serialized-[proto.Command] bytes carried in a single
  /// [proto.ChunkedPayload] frame's `data` field. Commands whose serialized
  /// form exceeds this are split across multiple ordered frames.
  ///
  /// The BLE link negotiates a 512-byte ATT MTU (see [BleServiceImpl.connect]).
  /// We keep a conservative payload budget below that to leave room for the
  /// ChunkedPayload envelope overhead (correlation_id, indices, field tags).
  static const int maxChunkDataBytes = 400;

  /// Generates a new correlation ID (UUID v4).
  static String newCorrelationId() => _uuid.v4();

  /// Encodes [cmd] into one or more ChunkedPayload frames. A command whose
  /// serialized form fits within [maxChunkDataBytes] yields exactly one frame
  /// `{chunk_index: 0, total_chunks: 1}` (the single-chunk fast path); a larger
  /// command is split into N ordered frames sharing [correlationId], each with
  /// sequential `chunk_index` and `total_chunks = N`.
  static List<Uint8List> encodeCommandFrames(
    BleCommand cmd,
    String correlationId,
  ) {
    final protoCmd = _toProtoCommand(cmd, correlationId);
    return _splitIntoFrames(protoCmd.writeToBuffer(), correlationId);
  }

  /// Encodes [cmd] into a single ChunkedPayload-wrapped [proto.Command] and
  /// returns the serialized bytes of that frame.
  ///
  /// Retained for callers/tests that assert the single-frame envelope shape.
  /// Transport code should use [encodeCommandFrames] so large commands chunk.
  static Uint8List encodeCommand(BleCommand cmd, String correlationId) {
    return encodeCommandFrames(cmd, correlationId).first;
  }

  /// Splits serialized command [data] into ordered ChunkedPayload frames,
  /// each carrying at most [maxChunkDataBytes] of `data`.
  static List<Uint8List> _splitIntoFrames(
    List<int> data,
    String correlationId,
  ) {
    final total = data.isEmpty
        ? 1
        : (data.length + maxChunkDataBytes - 1) ~/ maxChunkDataBytes;
    final frames = <Uint8List>[];
    for (var i = 0; i < total; i++) {
      final start = i * maxChunkDataBytes;
      final end = math.min(start + maxChunkDataBytes, data.length);
      final chunk = proto.ChunkedPayload(
        correlationId: correlationId,
        chunkIndex: i,
        totalChunks: total,
        data: data.sublist(start, end),
      );
      frames.add(Uint8List.fromList(chunk.writeToBuffer()));
    }
    return frames;
  }

  /// Builds a [proto.ChunkAck] frame for the given [correlationId] and
  /// [chunkIndex], serialized for writing back to the peer. A ChunkAck is
  /// distinguished from a ChunkedPayload response on the wire by
  /// `total_chunks == 0` (a ChunkedPayload always carries `total_chunks >= 1`).
  static Uint8List encodeChunkAck(String correlationId, int chunkIndex) {
    final ack = proto.ChunkedPayload(
      correlationId: correlationId,
      chunkIndex: chunkIndex,
      totalChunks: 0,
      data: const [],
    );
    return Uint8List.fromList(ack.writeToBuffer());
  }

  /// Encodes a [PushSessionConfig] into a ChunkedPayload-wrapped
  /// [proto.Command] (with the `push_session_config` oneof set) and returns the
  /// serialized bytes.
  ///
  /// Deliberately bypasses [_toProtoCommand]: per "Fix 14", [PushSessionConfig]
  /// is NOT part of the [BleCommand] sealed hierarchy — it is sent via the
  /// dedicated [BleService.pushSessionConfig] API. This helper is the single
  /// place that translates the session config to the wire.
  ///
  /// Optional fields (`rtmp_url` / `stream_key`) are only set when present;
  /// when null they are left unset on the wire (not encoded as empty strings).
  static List<Uint8List> encodeSessionConfigFrames(
    PushSessionConfig config,
    String correlationId,
  ) {
    final protoCmd = _sessionConfigToProtoCommand(config, correlationId);
    return _splitIntoFrames(protoCmd.writeToBuffer(), correlationId);
  }

  /// Encodes [config] into a single ChunkedPayload frame's bytes. Retained for
  /// tests asserting the envelope shape; transport uses
  /// [encodeSessionConfigFrames].
  static Uint8List encodeSessionConfig(
    PushSessionConfig config,
    String correlationId,
  ) {
    return encodeSessionConfigFrames(config, correlationId).first;
  }

  static proto.Command _sessionConfigToProtoCommand(
    PushSessionConfig config,
    String correlationId,
  ) {
    final pb = proto.PushSessionConfigCommand(
      matchUuid: config.matchUuid,
      userUuid: config.userUuid,
      sport: config.sport,
      numPeriods: config.numPeriods,
      periodLengthSeconds: config.periodLengthSeconds,
      videoOutputPath: config.videoOutputPath,
      thumbnailOutputPath: config.thumbnailOutputPath,
      teamAId: config.teamAId ?? '',
      teamBId: config.teamBId ?? '',
      teamAName: config.teamAName ?? '',
      teamBName: config.teamBName ?? '',
      teamAColorHex: config.teamAColorHex ?? '',
      teamBColorHex: config.teamBColorHex ?? '',
    );
    // proto3 `optional` fields: leave unset when null so the receiver can
    // distinguish "no streaming" from an empty-string destination.
    if (config.rtmpUrl != null) pb.rtmpUrl = config.rtmpUrl!;
    if (config.streamKey != null) pb.streamKey = config.streamKey!;

    return proto.Command(
      correlationId: correlationId,
      pushSessionConfig: pb,
    );
  }

  /// Decodes a CommandResponse for a [PushSessionConfig] push (which carries no
  /// typed payload — only a status). Returns an OK response on
  /// [proto.ResponseStatus.OK], a distinct unsupported response on
  /// [proto.ResponseStatus.UNSUPPORTED], otherwise an error/timeout response.
  static BleCommandResponse<void> decodeSessionConfigResponse(
    List<int> chunkPayloadBytes,
    String expectedCorrelationId,
  ) {
    try {
      final chunk = proto.ChunkedPayload.fromBuffer(chunkPayloadBytes);
      final resp = proto.CommandResponse.fromBuffer(chunk.data);
      if (resp.correlationId != expectedCorrelationId) {
        return BleCommandResponse.error(
          'Correlation ID mismatch: expected $expectedCorrelationId, '
          'got ${resp.correlationId}',
        );
      }
      return _statusToResponse<void>(resp, () => BleCommandResponse.ok(null));
    } catch (e) {
      return BleCommandResponse.error('Proto decode error: $e');
    }
  }

  /// Decodes [chunkPayloadBytes] (a serialized [proto.ChunkedPayload]) into a
  /// [BleCommandResponse<T>].
  ///
  /// Returns [BleCommandResponse.error] if:
  /// - the bytes are not parseable as a valid ChunkedPayload + CommandResponse
  /// - the response's correlation_id does not match [expectedCorrelationId]
  /// - the response status is not OK
  ///
  /// Never throws — all errors are returned as error responses.
  static BleCommandResponse<T> decodeResponse<T>(
    List<int> chunkPayloadBytes,
    String expectedCorrelationId,
  ) {
    try {
      final chunk = proto.ChunkedPayload.fromBuffer(chunkPayloadBytes);
      final resp = proto.CommandResponse.fromBuffer(chunk.data);

      if (resp.correlationId != expectedCorrelationId) {
        return BleCommandResponse.error(
          'Correlation ID mismatch: expected $expectedCorrelationId, '
          'got ${resp.correlationId}',
        );
      }

      // Parse by the actual response payload variant — not by the outbound
      // command type — so the decode reflects what the firmware truly sent.
      return _statusToResponse<T>(resp, () => _mapOkResponse<T>(resp));
    } catch (e) {
      return BleCommandResponse.error('Proto decode error: $e');
    }
  }

  /// Maps a [proto.CommandResponse]'s status to a [BleCommandResponse], invoking
  /// [onOk] to build the OK payload. UNSUPPORTED is surfaced distinctly from a
  /// generic ERROR (preserving any `error_message`); TIMEOUT maps to timeout.
  static BleCommandResponse<T> _statusToResponse<T>(
    proto.CommandResponse resp,
    BleCommandResponse<T> Function() onOk,
  ) {
    switch (resp.status) {
      case proto.ResponseStatus.OK:
        return onOk();
      case proto.ResponseStatus.TIMEOUT:
        return BleCommandResponse<T>.timeout();
      case proto.ResponseStatus.UNSUPPORTED:
        return BleCommandResponse<T>(
          status: BleResponseStatus.unsupported,
          errorMessage: resp.errorMessage.isNotEmpty
              ? resp.errorMessage
              : 'Command not supported by firmware',
        );
      default:
        return BleCommandResponse.error(
          resp.errorMessage.isNotEmpty
              ? resp.errorMessage
              : 'Command failed with status ${resp.status}',
        );
    }
  }

  static proto.Command _toProtoCommand(
    BleCommand cmd,
    String correlationId,
  ) => switch (cmd) {
    GetDeviceInfoCommand() => proto.Command(
      correlationId: correlationId,
      getDeviceInfo: proto.GetDeviceInfoCommand(),
    ),
    GetTelemetryCommand() => proto.Command(
      correlationId: correlationId,
      getTelemetry: proto.GetTelemetryCommand(),
    ),
    GetMatchStateCommand() => proto.Command(
      correlationId: correlationId,
      getMatchState: proto.GetMatchStateCommand(),
    ),
    ListRecordingsCommand() => proto.Command(
      correlationId: correlationId,
      listRecordings: proto.ListRecordingsCommand(),
    ),
    DownloadRequestCommand(:final recordingId) => proto.Command(
      correlationId: correlationId,
      downloadRequest: proto.DownloadRequestCommand(recordingId: recordingId),
    ),
    RequestThumbnailCommand(:final width, :final height, :final quality) =>
      proto.Command(
        correlationId: correlationId,
        thumbnail: proto.ThumbnailRequest(
          width: width,
          height: height,
          quality: quality,
        ),
      ),
    RecordingControlCommand(:final action) => proto.Command(
      correlationId: correlationId,
      recordingControl: proto.RecordingControlCommand(
        action: switch (action) {
          RecordingControlAction.start => proto.RecordingAction.RECORDING_START,
          RecordingControlAction.stop => proto.RecordingAction.RECORDING_STOP,
          RecordingControlAction.pause => proto.RecordingAction.RECORDING_PAUSE,
          RecordingControlAction.resume =>
            proto.RecordingAction.RECORDING_RESUME,
        },
      ),
    ),
    StreamingControlCommand(:final action, :final rtmpUrl) => proto.Command(
      correlationId: correlationId,
      streamingControl: proto.StreamingControlCommand(
        action: switch (action) {
          StreamingControlAction.start => proto.StreamingAction.STREAMING_START,
          StreamingControlAction.stop => proto.StreamingAction.STREAMING_STOP,
        },
        destination: rtmpUrl ?? '',
      ),
    ),
    MatchControlCommand(:final action, :final period) => proto.Command(
      correlationId: correlationId,
      matchControl: proto.MatchControlCommand(
        action: switch (action) {
          BleMatchControlAction.kickoff =>
            proto.MatchControlAction.MATCH_KICKOFF,
          BleMatchControlAction.periodEnd =>
            proto.MatchControlAction.MATCH_PERIOD_END,
          BleMatchControlAction.periodStart =>
            proto.MatchControlAction.MATCH_PERIOD_START,
          BleMatchControlAction.finalWhistle =>
            proto.MatchControlAction.MATCH_FINAL_WHISTLE,
          BleMatchControlAction.clockPause =>
            proto.MatchControlAction.MATCH_CLOCK_PAUSE,
          BleMatchControlAction.clockResume =>
            proto.MatchControlAction.MATCH_CLOCK_RESUME,
        },
        period: period,
      ),
    ),
    ScoreUpdateCommand(:final teamId, :final delta) => proto.Command(
      correlationId: correlationId,
      scoreUpdate: proto.ScoreUpdateCommand(teamId: teamId, delta: delta),
    ),
    BannerEventCommand(
      :final templateId,
      :final params,
      :final durationSeconds,
      :final playerId,
    ) =>
      proto.Command(
        correlationId: correlationId,
        bannerEvent: proto.BannerEventCommand(
          templateId: templateId,
          params: params,
          durationS: durationSeconds,
          playerId: playerId ?? '',
        ),
      ),
    PushOverlayLayoutCommand(:final layout) => proto.Command(
      correlationId: correlationId,
      pushOverlayLayout: proto.PushOverlayLayoutCommand(
        layout: _dartLayoutToProto(layout),
      ),
    ),
    StartWifiDirectCommand() => proto.Command(
      correlationId: correlationId,
      startWifiDirect: proto.StartWifiDirectCommand(),
    ),
    StopWifiDirectCommand() => proto.Command(
      correlationId: correlationId,
      stopWifiDirect: proto.StopWifiDirectCommand(),
    ),
  };

  /// Maps an OK [proto.CommandResponse] to a typed [BleCommandResponse] by
  /// switching on the actual `whichPayload()` variant the firmware sent. A
  /// `notSet` payload is a valid result for the control commands that carry no
  /// data (they OK with a null payload); for payload-bearing variants the
  /// firmware's chosen oneof determines the decode.
  ///
  /// For DeviceInfo, the firmware's `protocol_version` is checked against
  /// [kAppProtocolVersion]; a mismatch returns an error response carrying the
  /// version-skew message so callers can refuse the session.
  static BleCommandResponse<T> _mapOkResponse<T>(proto.CommandResponse resp) {
    switch (resp.whichPayload()) {
      case proto.CommandResponse_Payload.deviceInfo:
        final info = resp.deviceInfo;
        if (info.protocolVersion != kAppProtocolVersion) {
          return BleCommandResponse.error(
            'Protocol version mismatch: firmware ${info.protocolVersion}, '
            'app $kAppProtocolVersion',
          );
        }
        return BleCommandResponse.ok(
          DeviceInfoResponse(
                deviceId: info.deviceId,
                name: info.name,
                firmwareVersion: info.firmwareVersion,
                model: info.model,
                protocolVersion: info.protocolVersion,
              )
              as T?,
        );
      case proto.CommandResponse_Payload.telemetry:
        return BleCommandResponse.ok(_dartTelemetry(resp.telemetry) as T?);
      case proto.CommandResponse_Payload.matchState:
        return BleCommandResponse.ok(_dartMatchState(resp.matchState) as T?);
      case proto.CommandResponse_Payload.recordingList:
        return BleCommandResponse.ok(
          resp.recordingList.recordings
                  .map(
                    (r) => RecordingMetadata(
                      id: r.id,
                      durationSeconds: r.durationS.toInt(),
                      sizeBytes: r.sizeBytes.toInt(),
                      startedAt: DateTime.fromMillisecondsSinceEpoch(
                        r.startedAt.toInt() * 1000,
                      ),
                      sport: r.sport,
                      teams: r.teams,
                    ),
                  )
                  .toList()
              as T?,
        );
      case proto.CommandResponse_Payload.downloadToken:
        return BleCommandResponse.ok(
          DownloadToken(
                recordingId: resp.downloadToken.recordingId,
                httpUrl: resp.downloadToken.httpUrl,
                authToken: resp.downloadToken.authToken,
                expiresAt: DateTime.fromMillisecondsSinceEpoch(
                  resp.downloadToken.expiresAt.toInt() * 1000,
                ),
              )
              as T?,
        );
      case proto.CommandResponse_Payload.thumbnail:
        return BleCommandResponse.ok(
          ThumbnailResult(
                jpegBytes: Uint8List.fromList(resp.thumbnail.jpegBytes),
                capturedAt: DateTime.fromMillisecondsSinceEpoch(
                  resp.thumbnail.captureTimestamp.toInt(),
                ),
              )
              as T?,
        );
      case proto.CommandResponse_Payload.wifiDirectGroup:
        return BleCommandResponse.ok(
          WifiDirectGroup(
                ssid: resp.wifiDirectGroup.ssid,
                psk: resp.wifiDirectGroup.psk,
                groupOwnerIp: resp.wifiDirectGroup.groupOwnerIp,
                previewPort: resp.wifiDirectGroup.previewPort,
                downloadPort: resp.wifiDirectGroup.downloadPort,
                role: resp.wifiDirectGroup.role,
              )
              as T?,
        );
      case proto.CommandResponse_Payload.notSet:
        // No typed payload — valid for control commands (recording/streaming/
        // match control, score/banner events, overlay/session push). If T is a
        // value type the caller expected a payload that the firmware omitted;
        // we still OK with null and let the caller's null-check surface it.
        return BleCommandResponse.ok(null as T?);
    }
  }

  static DeviceTelemetry _dartTelemetry(proto.DeviceTelemetry p) =>
      DeviceTelemetry(
        storageFreeBytes: p.storageFreeBytes.toInt(),
        storageTotalBytes: p.storageTotalBytes.toInt(),
        wifiState: _dartWifiState(p.wifiState),
        wifiSsid: p.wifiSsid.isEmpty ? null : p.wifiSsid,
        wifiSignalDbm: p.wifiSignalDbm,
        internetReachable: p.internetReachable,
        tempCelsius: p.tempCelsius,
        ramUsedPct: p.ramUsedPct,
        cpuUsedPct: p.cpuUsedPct,
        uptimeSeconds: p.uptimeSeconds.toInt(),
        isRecording: p.isRecording,
        isStreaming: p.isStreaming,
        batteryLevelPct: p.hasBatteryLevelPct() ? p.batteryLevelPct : null,
      );

  static WifiState _dartWifiState(proto.WifiState s) => switch (s) {
    proto.WifiState.WIFI_DISABLED => WifiState.disabled,
    proto.WifiState.WIFI_DISCONNECTED => WifiState.disconnected,
    proto.WifiState.WIFI_CONNECTED => WifiState.connected,
    _ => WifiState.unknown,
  };

  // ---------------------------------------------------------------------------
  // Overlay layout → proto helpers
  // ---------------------------------------------------------------------------

  static proto.OverlayLayout _dartLayoutToProto(OverlayLayout layout) {
    return proto.OverlayLayout(
      canvasWidth: layout.canvasWidth,
      canvasHeight: layout.canvasHeight,
      elements: layout.elements.map(_dartElementToProto).toList(),
      templates: layout.templates
          .map(
            (t) => proto.OverlayTemplate(
              eventType: t.eventType,
              durationMs: t.durationMs,
              elements: t.elements.map(_dartElementToProto).toList(),
            ),
          )
          .toList(),
    );
  }

  static proto.OverlayElement _dartElementToProto(OverlayElement el) {
    return proto.OverlayElement(
      id: el.id,
      shape: _dartShapeToProto(el.shape),
      bounds: proto.OverlayRect(
        x1: el.bounds.x1,
        y1: el.bounds.y1,
        z: el.bounds.z,
        x2: el.bounds.x2,
        y2: el.bounds.y2,
      ),
      style: proto.OverlayStyle(
        fillColor: el.style.fillColor ?? '',
        textColor: el.style.textColor ?? '',
        opacity: el.style.opacity,
        cornerRadius: el.style.cornerRadius,
        fontFamily: el.style.fontFamily ?? '',
        fontSize: el.style.fontSize,
        textAlign: _dartTextAlignToProto(el.style.textAlign),
        fontWeight: _dartFontWeightToProto(el.style.fontWeight),
        staticText: el.style.staticText ?? '',
      ),
      binding: _dartBindingToProto(el.binding),
      visible: el.visible,
    );
  }

  static proto.OverlayShape _dartShapeToProto(OverlayShape s) => switch (s) {
    OverlayShape.rect => proto.OverlayShape.SHAPE_RECT,
    OverlayShape.text => proto.OverlayShape.SHAPE_TEXT,
    OverlayShape.circle => proto.OverlayShape.SHAPE_CIRCLE,
  };

  static proto.OverlayBinding _dartBindingToProto(OverlayBinding b) =>
      switch (b) {
        OverlayBinding.static => proto.OverlayBinding.BINDING_STATIC,
        OverlayBinding.scoreA => proto.OverlayBinding.BINDING_SCORE_A,
        OverlayBinding.scoreB => proto.OverlayBinding.BINDING_SCORE_B,
        OverlayBinding.scoreVs => proto.OverlayBinding.BINDING_SCORE_VS,
        OverlayBinding.teamAName => proto.OverlayBinding.BINDING_TEAM_A_NAME,
        OverlayBinding.teamBName => proto.OverlayBinding.BINDING_TEAM_B_NAME,
        OverlayBinding.matchClock => proto.OverlayBinding.BINDING_MATCH_CLOCK,
        OverlayBinding.periodLabel => proto.OverlayBinding.BINDING_PERIOD_LABEL,
      };

  static proto.TextAlign _dartTextAlignToProto(OverlayTextAlign a) =>
      switch (a) {
        OverlayTextAlign.left => proto.TextAlign.TEXT_ALIGN_LEFT,
        OverlayTextAlign.center => proto.TextAlign.TEXT_ALIGN_CENTER,
        OverlayTextAlign.right => proto.TextAlign.TEXT_ALIGN_RIGHT,
      };

  static proto.FontWeight _dartFontWeightToProto(OverlayFontWeight w) =>
      switch (w) {
        OverlayFontWeight.normal => proto.FontWeight.FONT_WEIGHT_NORMAL,
        OverlayFontWeight.bold => proto.FontWeight.FONT_WEIGHT_BOLD,
      };

  static MatchState _dartMatchState(proto.MatchState s) => MatchState(
    status: switch (s.status) {
      proto.MatchStatus.MATCH_NOT_STARTED => MatchStatus.notStarted,
      proto.MatchStatus.MATCH_ACTIVE => MatchStatus.active,
      proto.MatchStatus.MATCH_PAUSED => MatchStatus.paused,
      proto.MatchStatus.MATCH_HALF_TIME => MatchStatus.halfTime,
      proto.MatchStatus.MATCH_FINISHED => MatchStatus.finished,
      _ => MatchStatus.unknown,
    },
    currentPeriod: s.currentPeriod,
    timeRemainingSeconds: s.timeRemainingS,
    scoreA: s.scoreA,
    scoreB: s.scoreB,
    teamAId: s.teamAId,
    teamBId: s.teamBId,
    updatedAt: s.hasUpdatedAt()
        ? DateTime.fromMillisecondsSinceEpoch(s.updatedAt.toInt() * 1000)
        : DateTime.now(),
  );
}

/// Index-addressed reassembler for an inbound multi-chunk response on a single
/// correlation id. Unlike a naive arrival-order concatenation, it places each
/// chunk's `data` at its `chunk_index`, so out-of-order or duplicate frames
/// reassemble correctly. Completes once every index in `[0, total_chunks)` is
/// present.
///
/// One instance per correlation id. The transport ([_ConnectedDevice]) holds a
/// map of these keyed by correlation id and clears them on completion/timeout.
class ChunkReassembler {
  final Map<int, List<int>> _byIndex = {};
  int? _total;

  /// Number of distinct chunk indices received so far.
  int get received => _byIndex.length;

  /// Total chunks expected (set from the first frame seen), or null if none yet.
  int? get total => _total;

  /// Adds [chunk]. Duplicate indices overwrite (not double-count). Returns the
  /// fully reassembled byte sequence once all indices are present, else null.
  List<int>? add(proto.ChunkedPayload chunk) {
    _total = chunk.totalChunks;
    _byIndex[chunk.chunkIndex] = chunk.data;
    return _tryAssemble();
  }

  List<int>? _tryAssemble() {
    final total = _total;
    if (total == null || _byIndex.length < total) return null;
    for (var i = 0; i < total; i++) {
      if (!_byIndex.containsKey(i)) return null;
    }
    final out = <int>[];
    for (var i = 0; i < total; i++) {
      out.addAll(_byIndex[i]!);
    }
    return out;
  }
}

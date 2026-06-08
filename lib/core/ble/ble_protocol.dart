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

  /// Generates a new correlation ID (UUID v4).
  static String newCorrelationId() => _uuid.v4();

  /// Encodes [cmd] into a ChunkedPayload-wrapped [proto.Command] and returns
  /// the serialized bytes. Uses [correlationId] as the envelope ID.
  static Uint8List encodeCommand(BleCommand cmd, String correlationId) {
    final protoCmd = _toProtoCommand(cmd, correlationId);
    final chunk = proto.ChunkedPayload(
      correlationId: correlationId,
      chunkIndex: 0,
      totalChunks: 1,
      data: protoCmd.writeToBuffer(),
    );
    return Uint8List.fromList(chunk.writeToBuffer());
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
    BleCommand originalCommand,
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

      return switch (resp.status) {
        proto.ResponseStatus.OK => _mapOkResponse<T>(resp, originalCommand),
        proto.ResponseStatus.TIMEOUT => BleCommandResponse<T>.timeout(),
        _ => BleCommandResponse.error(
          resp.errorMessage.isNotEmpty
              ? resp.errorMessage
              : 'Command failed with status ${resp.status}',
        ),
      };
    } catch (e) {
      return BleCommandResponse.error('Proto decode error: $e');
    }
  }

  static proto.Command _toProtoCommand(BleCommand cmd, String correlationId) =>
      switch (cmd) {
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
          downloadRequest: proto.DownloadRequestCommand(
            recordingId: recordingId,
          ),
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
              RecordingControlAction.start =>
                proto.RecordingAction.RECORDING_START,
              RecordingControlAction.stop =>
                proto.RecordingAction.RECORDING_STOP,
              RecordingControlAction.pause =>
                proto.RecordingAction.RECORDING_PAUSE,
              RecordingControlAction.resume =>
                proto.RecordingAction.RECORDING_RESUME,
            },
          ),
        ),
        StreamingControlCommand(:final action, :final rtmpUrl) => proto.Command(
          correlationId: correlationId,
          streamingControl: proto.StreamingControlCommand(
            action: switch (action) {
              StreamingControlAction.start =>
                proto.StreamingAction.STREAMING_START,
              StreamingControlAction.stop =>
                proto.StreamingAction.STREAMING_STOP,
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
          scoreUpdate: proto.ScoreUpdateCommand(
            teamId: teamId,
            delta: delta,
          ),
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
      };

  static BleCommandResponse<T> _mapOkResponse<T>(
    proto.CommandResponse resp,
    BleCommand cmd,
  ) {
    return switch (cmd) {
      GetDeviceInfoCommand() => BleCommandResponse.ok(
        DeviceInfoResponse(deviceId: resp.deviceInfo.deviceId) as T?,
      ),
      GetTelemetryCommand() => BleCommandResponse.ok(
        _dartTelemetry(resp.telemetry) as T?,
      ),
      GetMatchStateCommand() => BleCommandResponse.ok(
        _dartMatchState(resp.matchState) as T?,
      ),
      ListRecordingsCommand() => BleCommandResponse.ok(
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
      ),
      DownloadRequestCommand() => BleCommandResponse.ok(
        DownloadToken(
              recordingId: resp.downloadToken.recordingId,
              httpUrl: resp.downloadToken.httpUrl,
              authToken: resp.downloadToken.authToken,
              expiresAt: DateTime.fromMillisecondsSinceEpoch(
                resp.downloadToken.expiresAt.toInt() * 1000,
              ),
            )
            as T?,
      ),
      RequestThumbnailCommand() => BleCommandResponse.ok(
        ThumbnailResult(
          jpegBytes: Uint8List.fromList(resp.thumbnail.jpegBytes),
          capturedAt: DateTime.fromMillisecondsSinceEpoch(
            resp.thumbnail.captureTimestamp.toInt(),
          ),
        ) as T?,
      ),
      RecordingControlCommand() => BleCommandResponse.ok(null as T?),
      StreamingControlCommand() => BleCommandResponse.ok(null as T?),
      MatchControlCommand() => BleCommandResponse.ok(null as T?),
      ScoreUpdateCommand() => BleCommandResponse.ok(null as T?),
      BannerEventCommand() => BleCommandResponse.ok(null as T?),
      PushOverlayLayoutCommand() => BleCommandResponse.ok(null as T?),
      StartWifiDirectCommand() => BleCommandResponse.ok(
        WifiDirectGroup(
          ssid: resp.wifiDirectGroup.ssid,
          psk: resp.wifiDirectGroup.psk,
          groupOwnerIp: resp.wifiDirectGroup.groupOwnerIp,
          previewPort: resp.wifiDirectGroup.previewPort,
          downloadPort: resp.wifiDirectGroup.downloadPort,
          role: resp.wifiDirectGroup.role,
        ) as T?,
      ),
    };
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
        OverlayBinding.periodLabel =>
          proto.OverlayBinding.BINDING_PERIOD_LABEL,
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

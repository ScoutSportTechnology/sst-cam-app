import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:uuid/uuid.dart';

import '../models/command.dart';
import '../models/match.dart';
import '../models/recording.dart';
import '../models/telemetry.dart';
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
      _ => BleCommandResponse.error(
        'No response mapping for command type ${cmd.runtimeType}',
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

/// Encodes a proto [DeviceTelemetry] value for use in test fixtures and the
/// emulator. Returns the proto message (not serialized).
proto.DeviceTelemetry encodeProtoTelemetry({
  required int storageFreeBytes,
  required int storageTotalBytes,
  proto.WifiState wifiState = proto.WifiState.WIFI_CONNECTED,
  String wifiSsid = '',
  int wifiSignalDbm = 0,
  bool internetReachable = true,
  double tempCelsius = 48.0,
  double ramUsedPct = 0.45,
  double cpuUsedPct = 0.30,
  int uptimeSeconds = 0,
  bool isRecording = false,
  bool isStreaming = false,
}) =>
    proto.DeviceTelemetry(
      storageFreeBytes: Int64(storageFreeBytes),
      storageTotalBytes: Int64(storageTotalBytes),
      wifiState: wifiState,
      wifiSsid: wifiSsid,
      wifiSignalDbm: wifiSignalDbm,
      internetReachable: internetReachable,
      tempCelsius: tempCelsius,
      ramUsedPct: ramUsedPct,
      cpuUsedPct: cpuUsedPct,
      uptimeSeconds: Int64(uptimeSeconds),
      isRecording: isRecording,
      isStreaming: isStreaming,
    );

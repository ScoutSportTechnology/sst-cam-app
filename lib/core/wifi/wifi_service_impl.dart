import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

import '../ble/ble_service.dart';
import '../models/command.dart';
import '../models/overlay.dart';
import '../models/recording.dart';
import '../models/wifi.dart';
import '../services/video_path_service.dart';
import 'wifi_p2p_channel.dart';
import 'wifi_service.dart';

/// Real WiFi Direct implementation.
///
/// Pending firmware wiring:
///   * RTSP H.264 playback via `flutter_vlc_player` driven by
///     [previewDescriptor]; the heartbeat stream is generated locally on
///     keyframe arrival so the UI's liveness badge has a tick source.
///   * a chunked HTTP download client for `startDownload`, with byte-range
///     resume support against the Jetson's recording HTTP server.
class WifiServiceImpl implements WifiService {
  WifiServiceImpl({required BleService ble, Dio? dio})
      : _ble = ble,
        _dio = dio ?? Dio();

  final BleService _ble;
  final Dio _dio;
  final WifiP2pChannel _channel = WifiP2pChannel();

  final _rng = Random();
  final _videoPathService = VideoPathService();
  final Map<String, _DownloadState> _downloads = {};
  final _allProgressController =
      StreamController<VideoDownloadProgress>.broadcast();

  // Per-device state stream controllers — created on demand.
  final Map<String, StreamController<WifiDirectState>> _stateControllers = {};

  // Per-device EventChannel subscriptions — one per active connectGroup call.
  final Map<String, StreamSubscription<int>> _stateSubscriptions = {};

  // Per-device current group (null when disconnected).
  final Map<String, WifiDirectGroup> _currentGroups = {};

  // In-flight connectGroup calls — second caller awaits the same Completer
  // rather than racing with an already-running connect sequence.
  final Map<String, Completer<WifiDirectGroup>> _inflightConnects = {};

  /// Returns (creating if absent) the broadcast controller for [deviceId].
  StreamController<WifiDirectState> _stateController(String deviceId) {
    return _stateControllers.putIfAbsent(
      deviceId,
      () => StreamController<WifiDirectState>.broadcast(),
    );
  }

  void _emitState(String deviceId, WifiDirectState state) {
    final ctrl = _stateController(deviceId);
    if (!ctrl.isClosed) ctrl.add(state);
  }

  /// Whether [role] designates the camera as the WiFi Direct group owner.
  /// Accepts the common spellings firmware may use, plus an empty value
  /// (firmware that predates the role field).
  static bool _isGroupOwnerRole(String role) {
    final r = role.trim().toLowerCase();
    return r.isEmpty ||
        r == 'go' ||
        r == 'group_owner' ||
        r == 'group-owner' ||
        r == 'groupowner' ||
        r == 'owner';
  }

  WifiDirectState _codeToState(int code) => switch (code) {
    0 => WifiDirectState.idle,
    1 => WifiDirectState.starting,
    2 => WifiDirectState.connected,
    3 => WifiDirectState.failed,
    4 => WifiDirectState.stopping,
    _ => WifiDirectState.failed,
  };

  @override
  Future<WifiDirectGroup> connectGroup(String deviceId) async {
    // Serialize concurrent calls for the same device — second caller awaits the
    // already-running connect sequence instead of starting a duplicate.
    final existing = _inflightConnects[deviceId];
    if (existing != null) return existing.future;

    final completer = Completer<WifiDirectGroup>();
    _inflightConnects[deviceId] = completer;
    // The completer exists only so a concurrent second caller can await the
    // same connect. The primary caller gets its result via the return below /
    // the rethrow, so the completer's own future may have no listener; mark it
    // ignored so an error completion is not reported as an unhandled async
    // error. A real second awaiter still receives the value/error.
    completer.future.ignore();

    try {
      final group = await _connectGroupInternal(deviceId);
      completer.complete(group);
      return group;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _inflightConnects.remove(deviceId);
    }
  }

  Future<WifiDirectGroup> _connectGroupInternal(String deviceId) async {
    // iOS guard — P2P group negotiation is not supported on iOS.
    if (Platform.isIOS) {
      _emitState(deviceId, WifiDirectState.failed);
      throw const WifiDirectException('local preview not supported on iOS');
    }

    _emitState(deviceId, WifiDirectState.starting);

    // Subscribe to the EventChannel BEFORE invoking connect so that the first
    // WifiDirectState.connected event from the Kotlin BroadcastReceiver is
    // never dropped.
    await _stateSubscriptions[deviceId]?.cancel();
    _stateSubscriptions[deviceId] = _channel.stateStream.listen(
      (code) => _emitState(deviceId, _codeToState(code)),
      onError: (Object e) {
        _stateSubscriptions.remove(deviceId)?.cancel();
        _emitState(deviceId, WifiDirectState.failed);
      },
    );

    // BLE round-trip — ask the camera for group credentials.
    final BleCommandResponse<WifiDirectGroup> response;
    try {
      response = await _ble.sendCommand<WifiDirectGroup>(
        deviceId,
        StartWifiDirectCommand(),
      );
    } catch (e) {
      await _stateSubscriptions.remove(deviceId)?.cancel();
      _emitState(deviceId, WifiDirectState.failed);
      throw WifiDirectException('BLE credential fetch failed: $e');
    }

    if (!response.isOk || response.payload == null) {
      await _stateSubscriptions.remove(deviceId)?.cancel();
      _emitState(deviceId, WifiDirectState.failed);
      throw WifiDirectException(
        'BLE credential fetch failed: ${response.errorMessage}',
      );
    }

    final group = response.payload!;

    if (group.ssid.isEmpty || group.psk.isEmpty) {
      await _stateSubscriptions.remove(deviceId)?.cancel();
      _emitState(deviceId, WifiDirectState.failed);
      throw const WifiDirectException('BLE credential fetch returned empty ssid/psk');
    }

    // Honor WifiDirectGroupResponse.role. The camera must be the WiFi Direct
    // group owner (GO) so the phone joins as a client at group.groupOwnerIp;
    // joining a group where the camera is itself a client would point the
    // preview/download URLs at the wrong host. An empty role is tolerated for
    // backward compatibility with firmware that does not report it yet.
    if (!_isGroupOwnerRole(group.role)) {
      await _stateSubscriptions.remove(deviceId)?.cancel();
      _emitState(deviceId, WifiDirectState.failed);
      throw WifiDirectException(
        'camera reported unexpected WiFi Direct role "${group.role}"; '
        'expected group owner',
      );
    }

    // Platform channel — join the P2P group on Android.
    try {
      await _channel.connect(ssid: group.ssid, psk: group.psk);
    } on Exception catch (e) {
      await _stateSubscriptions.remove(deviceId)?.cancel();
      _emitState(deviceId, WifiDirectState.failed);
      throw WifiDirectException('P2P connect failed: $e');
    }

    _currentGroups[deviceId] = group;
    return group;
  }

  @override
  Future<void> disconnectGroup(String deviceId) async {
    // Nothing to tear down if we never connected and nothing is in flight.
    if (_currentGroups[deviceId] == null &&
        _inflightConnects[deviceId] == null) {
      return;
    }

    await _stateSubscriptions.remove(deviceId)?.cancel();
    _emitState(deviceId, WifiDirectState.stopping);

    if (!Platform.isIOS) {
      // Tell firmware to release its P2P group before tearing down the Android side.
      try {
        await _ble.sendCommand<void>(deviceId, StopWifiDirectCommand());
      } catch (_) {
        // Best-effort — firmware may already be idle.
      }
      try {
        await _channel.disconnect();
      } catch (_) {
        // Best-effort — ignore native-side errors on disconnect.
      }
    }

    _currentGroups.remove(deviceId);
    _emitState(deviceId, WifiDirectState.idle);
  }

  @override
  WifiDirectGroup? currentGroup(String deviceId) => _currentGroups[deviceId];

  @override
  Stream<WifiDirectState> connectionStateStream(String deviceId) =>
      _stateController(deviceId).stream;

  @override
  PreviewStreamDescriptor? previewDescriptor(String deviceId) {
    final group = _currentGroups[deviceId];
    if (group == null) {
      return null; // no group up → LivePreviewView shows "Not connected"
    }
    // Real firmware (U4) serves RTSP H.264 at /preview on the group-owner IP +
    // preview port; geometry/bitrate match the firmware AppStreamConfig demo
    // defaults (854x480@30, 1500 kbps). Confirm the mount/transport on-device.
    return PreviewStreamDescriptor(
      url: group.previewUrl(),
      codec: PreviewCodec.rtspH264,
      width: 854,
      height: 480,
      fps: 30,
      bitrateKbps: 1500,
    );
  }

  @override
  Stream<PreviewFrame> previewFrames(String deviceId) => const Stream.empty();

  @override
  Stream<PreviewStats> previewStats(String deviceId) => const Stream.empty();

  @override
  Future<VideoDownloadHandle> startDownload(
    String deviceId,
    DownloadToken token, {
    String? saveAs,
  }) async {
    return _runDownload(
      token: token,
      savePath:
          saveAs ?? await _videoPathService.recordingPath(token.recordingId),
    );
  }

  // ---------------------------------------------------------------------------
  // Recordings
  // ---------------------------------------------------------------------------

  @override
  Future<bool> checkCameraHasRecording(String uuid) => Future.value(true);

  @override
  Future<VideoDownloadHandle> downloadRecording(
    String deviceId,
    String uuid,
  ) async {
    final savePath = await _videoPathService.recordingPath(uuid);
    // Mint a fresh download token over BLE, then stream the file over WiFi.
    final tokenResp = await _ble.sendCommand<DownloadToken>(
      deviceId,
      DownloadRequestCommand(recordingId: uuid),
    );
    final token = tokenResp.payload;
    if (!tokenResp.isOk || token == null) {
      throw WifiDirectException(
        'could not obtain a download token for $uuid: ${tokenResp.errorMessage ?? 'unknown error'}',
      );
    }
    return _runDownload(token: token, savePath: savePath);
  }

  @override
  Future<VideoDownloadHandle> downloadRecordingWithOverlays(
    String deviceId,
    String uuid,
    List<OverlayState> overlays,
    OverlayConfig config,
  ) async {
    // Mock: overlays ignored — camera-side rendering is not implemented
    return downloadRecording(deviceId, uuid);
  }

  @override
  Stream<OverlayState> overlayStateStream(String deviceId) => Stream.periodic(
    const Duration(seconds: 1),
    (i) => const OverlayState(
      timeSeconds: 0,
      homeScore: 0,
      awayScore: 0,
      period: 1,
      recentEventLabel: null,
    ),
  );

  // ---------------------------------------------------------------------------
  // Real streamed-to-disk HTTP download (Bearer + Content-Length progress)
  // ---------------------------------------------------------------------------

  Future<VideoDownloadHandle> _runDownload({
    required DownloadToken token,
    required String savePath,
  }) async {
    final downloadId =
        'dl-${DateTime.now().millisecondsSinceEpoch}-${_rng.nextInt(0xFFFF)}';
    final controller = StreamController<VideoDownloadProgress>.broadcast();
    final cancelToken = CancelToken();

    final initial = VideoDownloadProgress(
      downloadId: downloadId,
      recordingId: token.recordingId,
      status: DownloadStatus.queued,
      bytesReceived: 0,
      bytesTotal: 0,
      kbps: 0,
    );
    final entry = _DownloadState(
      progress: initial,
      controller: controller,
      timer: null,
      cancelToken: cancelToken,
    );
    _downloads[downloadId] = entry;
    _publishProgress(entry, initial);

    // Stream in the background; progress flows through the controller.
    unawaited(_streamToDisk(entry, token, savePath, downloadId));

    return VideoDownloadHandle(
      downloadId: downloadId,
      recordingId: token.recordingId,
      savePath: savePath,
      progress: controller.stream,
      cancel: () async {
        if (entry.progress.isTerminal) return;
        if (!cancelToken.isCancelled) cancelToken.cancel('cancelled by user');
      },
    );
  }

  /// Streams [token.httpUrl] to [savePath] with a `Bearer` auth header,
  /// emitting byte-count progress derived from `Content-Length`. The whole body
  /// is NOT buffered in memory. Resume on interruption is out of scope for the
  /// demo (a failed download restarts). The auth token is never logged.
  Future<void> _streamToDisk(
    _DownloadState entry,
    DownloadToken token,
    String savePath,
    String downloadId,
  ) async {
    final file = File(savePath);
    IOSink? sink;
    try {
      await file.parent.create(recursive: true);
      final resp = await _dio.get<ResponseBody>(
        token.httpUrl,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Authorization': 'Bearer ${token.authToken}'},
          // Treat any status as a response so 401/410 surface as a clear error
          // rather than a thrown DioException with no body context.
          validateStatus: (s) => s != null && s < 500,
        ),
        cancelToken: entry.cancelToken,
      );

      if (resp.statusCode != null && resp.statusCode! >= 400) {
        _publishProgress(
          entry,
          _progress(downloadId, token.recordingId, DownloadStatus.failed,
              0, 0, 0, error: 'download rejected (HTTP ${resp.statusCode})'),
        );
        return;
      }

      final total = int.tryParse(
            resp.headers.value(Headers.contentLengthHeader) ?? '',
          ) ??
          0;
      sink = file.openWrite();
      var received = 0;
      final sw = Stopwatch()..start();
      await for (final chunk in resp.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        final kbps = sw.elapsedMilliseconds > 0
            ? received * 8 / sw.elapsedMilliseconds
            : 0.0;
        _publishProgress(
          entry,
          _progress(downloadId, token.recordingId, DownloadStatus.running,
              received, total, kbps),
        );
      }
      await sink.flush();
      await sink.close();
      sink = null;
      _publishProgress(
        entry,
        _progress(downloadId, token.recordingId, DownloadStatus.completed,
            received, total == 0 ? received : total, 0),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _publishProgress(
          entry,
          _progress(downloadId, token.recordingId, DownloadStatus.cancelled,
              entry.progress.bytesReceived, entry.progress.bytesTotal, 0),
        );
      } else {
        _publishProgress(
          entry,
          _progress(downloadId, token.recordingId, DownloadStatus.failed,
              entry.progress.bytesReceived, entry.progress.bytesTotal, 0,
              error: e.message ?? 'network error'),
        );
      }
    } catch (e) {
      _publishProgress(
        entry,
        _progress(downloadId, token.recordingId, DownloadStatus.failed,
            entry.progress.bytesReceived, entry.progress.bytesTotal, 0,
            error: e.toString()),
      );
    } finally {
      try {
        await sink?.close();
      } catch (_) {/* already closing */}
      if (!entry.controller.isClosed) await entry.controller.close();
    }
  }

  VideoDownloadProgress _progress(
    String downloadId,
    String recordingId,
    DownloadStatus status,
    int received,
    int total,
    double kbps, {
    String? error,
  }) =>
      VideoDownloadProgress(
        downloadId: downloadId,
        recordingId: recordingId,
        status: status,
        bytesReceived: received,
        bytesTotal: total,
        kbps: kbps,
        errorMessage: error,
      );

  void _publishProgress(_DownloadState entry, VideoDownloadProgress p) {
    entry.progress = p;
    if (!entry.controller.isClosed) entry.controller.add(p);
    if (!_allProgressController.isClosed) _allProgressController.add(p);
  }

  @override
  List<VideoDownloadProgress> activeDownloads() =>
      _downloads.values.map((e) => e.progress).toList(growable: false);

  @override
  Stream<VideoDownloadProgress> allDownloadProgress() =>
      _allProgressController.stream;

  @override
  Future<void> dispose() async {
    // Cancel all EventChannel subscriptions.
    for (final sub in _stateSubscriptions.values) {
      await sub.cancel();
    }
    _stateSubscriptions.clear();

    // Close per-device state controllers.
    for (final ctrl in _stateControllers.values) {
      if (!ctrl.isClosed) await ctrl.close();
    }
    _stateControllers.clear();
    _currentGroups.clear();

    for (final d in _downloads.values) {
      d.timer?.cancel();
      if (!d.controller.isClosed) await d.controller.close();
    }
    _downloads.clear();
    await _allProgressController.close();
  }
}

class _DownloadState {
  _DownloadState({
    required this.progress,
    required this.controller,
    required this.timer,
    this.cancelToken,
  });

  VideoDownloadProgress progress;
  final StreamController<VideoDownloadProgress> controller;
  Timer? timer;
  final CancelToken? cancelToken;
}

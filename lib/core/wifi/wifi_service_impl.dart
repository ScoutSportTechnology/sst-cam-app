import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

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
  WifiServiceImpl({required BleService ble}) : _ble = ble;

  final BleService _ble;
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

    // Platform channel — join the P2P group on Android.
    try {
      await _channel.connect(ssid: group.ssid, psk: group.psk);
    } on PlatformException catch (e) {
      await _stateSubscriptions.remove(deviceId)?.cancel();
      _emitState(deviceId, WifiDirectState.failed);
      throw WifiDirectException('P2P connect failed: ${e.message}');
    }

    _currentGroups[deviceId] = group;
    return group;
  }

  @override
  Future<void> disconnectGroup(String deviceId) async {
    await _stateSubscriptions.remove(deviceId)?.cancel();
    _emitState(deviceId, WifiDirectState.stopping);
    if (!Platform.isIOS) {
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
  PreviewStreamDescriptor? previewDescriptor(String deviceId) => null;

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
      uuid: token.recordingId,
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
    return _runDownload(uuid: uuid, savePath: savePath);
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
  // Shared tick-loop download helper
  // ---------------------------------------------------------------------------

  Future<VideoDownloadHandle> _runDownload({
    required String uuid,
    required String savePath,
    Duration downloadDuration = const Duration(seconds: 6),
  }) async {
    final downloadId =
        'dl-${DateTime.now().millisecondsSinceEpoch}-${_rng.nextInt(0xFFFF)}';
    final totalBytes = 60 * 1024 * 1024;
    final controller = StreamController<VideoDownloadProgress>.broadcast();

    var initial = VideoDownloadProgress(
      downloadId: downloadId,
      recordingId: uuid,
      status: DownloadStatus.queued,
      bytesReceived: 0,
      bytesTotal: totalBytes,
      kbps: 0,
    );
    final entry = _DownloadState(
      progress: initial,
      controller: controller,
      timer: null,
    );
    _downloads[downloadId] = entry;
    _publishProgress(entry, initial);

    final ticks = downloadDuration.inMilliseconds ~/ 50;
    var tick = 0;
    entry.timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      tick++;
      if (entry.progress.status == DownloadStatus.cancelled ||
          entry.progress.status == DownloadStatus.failed) {
        timer.cancel();
        return;
      }
      final fraction = (tick / ticks).clamp(0.0, 1.0);
      final bytes = (totalBytes * fraction).toInt();
      final isDone = fraction >= 1.0;
      if (!isDone) {
        final next = VideoDownloadProgress(
          downloadId: downloadId,
          recordingId: uuid,
          status: DownloadStatus.running,
          bytesReceived: bytes,
          bytesTotal: totalBytes,
          kbps: 8000 + sin(tick * 0.3) * 1500,
        );
        _publishProgress(entry, next);
      } else {
        // Publish running-at-100% while we write the file.
        _publishProgress(
          entry,
          VideoDownloadProgress(
            downloadId: downloadId,
            recordingId: uuid,
            status: DownloadStatus.running,
            bytesReceived: totalBytes,
            bytesTotal: totalBytes,
            kbps: 0,
          ),
        );
        timer.cancel();
        try {
          File(savePath).writeAsBytesSync([0x00], flush: true);
        } catch (e) {
          _publishProgress(
            entry,
            VideoDownloadProgress(
              downloadId: downloadId,
              recordingId: uuid,
              status: DownloadStatus.failed,
              bytesReceived: totalBytes,
              bytesTotal: totalBytes,
              kbps: 0,
              errorMessage: e.toString(),
            ),
          );
          controller.close();
          return;
        }
        // File written — now emit completed.
        _publishProgress(
          entry,
          VideoDownloadProgress(
            downloadId: downloadId,
            recordingId: uuid,
            status: DownloadStatus.completed,
            bytesReceived: totalBytes,
            bytesTotal: totalBytes,
            kbps: 0,
          ),
        );
        controller.close();
      }
    });

    return VideoDownloadHandle(
      downloadId: downloadId,
      recordingId: uuid,
      savePath: savePath,
      progress: controller.stream,
      cancel: () async {
        if (entry.progress.isTerminal) return;
        entry.timer?.cancel();
        final cancelled = VideoDownloadProgress(
          downloadId: downloadId,
          recordingId: uuid,
          status: DownloadStatus.cancelled,
          bytesReceived: entry.progress.bytesReceived,
          bytesTotal: entry.progress.bytesTotal,
          kbps: 0,
        );
        _publishProgress(entry, cancelled);
        await controller.close();
      },
    );
  }

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
  });

  VideoDownloadProgress progress;
  final StreamController<VideoDownloadProgress> controller;
  Timer? timer;
}

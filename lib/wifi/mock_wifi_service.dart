import 'dart:async';
import 'dart:math';

import '../core/models/recording.dart';
import '../core/models/wifi.dart';
import '../services/video_path_service.dart';
import 'wifi_service.dart';

class _GroupState {
  _GroupState()
    : connController = StreamController<WifiDirectState>.broadcast(),
      previewController = StreamController<PreviewFrame>.broadcast(),
      statsController = StreamController<PreviewStats>.broadcast();

  final StreamController<WifiDirectState> connController;
  final StreamController<PreviewFrame> previewController;
  final StreamController<PreviewStats> statsController;

  WifiDirectState state = WifiDirectState.idle;
  WifiDirectGroup? group;
  PreviewStreamDescriptor? previewDescriptor;
  Timer? frameTimer;
  Timer? statsTimer;
  int sequence = 0;
  int statsTick = 0;

  void dispose() {
    frameTimer?.cancel();
    statsTimer?.cancel();
    connController.close();
    previewController.close();
    statsController.close();
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

/// Test double for [WifiService]. Fakes WiFi Direct pairing, emits a steady
/// preview-heartbeat stream at ~15 fps with synthetic sequence numbers, and
/// drives mock recording downloads to completion at a configurable speed.
///
/// Frames carry no pixel data — RTSP H.264 frames live inside the VLC
/// pipeline. The heartbeat is just a "frames flowing" signal for the UI's
/// liveness badge / frame counter.
class MockWifiService implements WifiService {
  MockWifiService({
    this.pairingDelay = const Duration(milliseconds: 900),
    this.previewFps = 15,
    this.downloadDuration = const Duration(seconds: 6),
    this.downloadFailureRate = 0.0,
    int? randomSeed,
  }) : _rng = Random(randomSeed);

  final Duration pairingDelay;
  final int previewFps;
  final Duration downloadDuration;
  final double downloadFailureRate;

  final Random _rng;
  final Map<String, _GroupState> _groups = {};
  final Map<String, _DownloadState> _downloads = {};
  final _allProgressController =
      StreamController<VideoDownloadProgress>.broadcast();

  // ---------------------------------------------------------------------------
  // Group lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<WifiDirectGroup> connectGroup(String deviceId) async {
    final state = _state(deviceId);
    if (state.state == WifiDirectState.connected && state.group != null) {
      return state.group!;
    }
    if (state.state == WifiDirectState.starting) {
      // Wait for the in-flight pairing to finish, then return its group.
      final result = await state.connController.stream
          .firstWhere(
            (s) => s != WifiDirectState.starting,
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => WifiDirectState.failed,
          );
      if (result == WifiDirectState.failed) {
        throw const WifiDirectException('Pairing timed out');
      }
      if (state.group != null) return state.group!;
    }
    state.state = WifiDirectState.starting;
    state.connController.add(WifiDirectState.starting);

    await Future.delayed(pairingDelay);

    final group = WifiDirectGroup(
      ssid: 'DIRECT-${deviceId.substring(deviceId.length - 4)}',
      psk: 'mock-${_rng.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
      groupOwnerIp: '192.168.49.1',
      previewPort: 8554,
      downloadPort: 8080,
      role: 'GROUP_OWNER',
    );
    state.group = group;
    state.previewDescriptor = PreviewStreamDescriptor(
      url: group.previewUrl(),
      codec: PreviewCodec.rtspH264,
      width: 640,
      height: 360,
      fps: previewFps,
      bitrateKbps: 1500,
    );
    state.state = WifiDirectState.connected;
    state.connController.add(WifiDirectState.connected);

    _startPreview(deviceId);
    return group;
  }

  @override
  Future<void> disconnectGroup(String deviceId) async {
    final state = _groups[deviceId];
    if (state == null) return;
    state.frameTimer?.cancel();
    state.statsTimer?.cancel();
    state.frameTimer = null;
    state.statsTimer = null;
    state.state = WifiDirectState.stopping;
    state.connController.add(WifiDirectState.stopping);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    state.state = WifiDirectState.idle;
    state.group = null;
    state.previewDescriptor = null;
    state.connController.add(WifiDirectState.idle);
  }

  @override
  WifiDirectGroup? currentGroup(String deviceId) => _groups[deviceId]?.group;

  @override
  Stream<WifiDirectState> connectionStateStream(String deviceId) =>
      _state(deviceId).connController.stream;

  // ---------------------------------------------------------------------------
  // Preview
  // ---------------------------------------------------------------------------

  @override
  PreviewStreamDescriptor? previewDescriptor(String deviceId) =>
      _groups[deviceId]?.previewDescriptor;

  @override
  Stream<PreviewFrame> previewFrames(String deviceId) =>
      _state(deviceId).previewController.stream;

  @override
  Stream<PreviewStats> previewStats(String deviceId) =>
      _state(deviceId).statsController.stream;

  void _startPreview(String deviceId) {
    final state = _groups[deviceId];
    if (state == null) return;
    state.frameTimer?.cancel();
    state.statsTimer?.cancel();

    final periodMs = (1000 / previewFps).round();
    state.frameTimer = Timer.periodic(Duration(milliseconds: periodMs), (_) {
      if (state.state != WifiDirectState.connected) return;
      state.previewController.add(
        PreviewFrame(sequence: state.sequence++, capturedAt: DateTime.now()),
      );
    });

    state.statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.state != WifiDirectState.connected) return;
      final t = state.statsTick++;
      // Slight sinusoidal jitter so the diagnostics readout looks alive.
      final fps = previewFps + sin(t * 0.4) * 0.6;
      final kbps = 1500 + sin(t * 0.2) * 200;
      final latency = (90 + sin(t * 0.3) * 25).round();
      state.statsController.add(
        PreviewStats(
          fps: fps,
          kbps: kbps,
          latencyMs: latency,
          framesReceived: state.sequence,
          framesDropped: 0,
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Downloads
  // ---------------------------------------------------------------------------

  @override
  Future<VideoDownloadHandle> startDownload(
    String deviceId,
    DownloadToken token, {
    String? saveAs,
  }) async {
    final group = _groups[deviceId]?.group;
    if (group == null) {
      throw const WifiDirectException(
        'WiFi Direct group not connected — call connectGroup first',
      );
    }

    final downloadId =
        'dl-${DateTime.now().millisecondsSinceEpoch}-${_rng.nextInt(0xFFFF)}';
    final savePath =
        saveAs ?? await VideoPathService().recordingPath(token.recordingId);
    // Pretend the recording is around 60 MB; matches a few minutes of 1080p.
    final totalBytes = 60 * 1024 * 1024;
    final controller = StreamController<VideoDownloadProgress>.broadcast();

    var initial = VideoDownloadProgress(
      downloadId: downloadId,
      recordingId: token.recordingId,
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
    _publish(entry, initial);

    // Tick at 50 ms intervals; ramp to 100% over `downloadDuration`.
    final ticks = downloadDuration.inMilliseconds ~/ 50;
    var tick = 0;
    entry.timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      tick++;
      if (entry.progress.status == DownloadStatus.cancelled ||
          entry.progress.status == DownloadStatus.failed) {
        timer.cancel();
        return;
      }
      // Inject a one-shot failure if configured.
      if (tick == ticks ~/ 2 && _rng.nextDouble() < downloadFailureRate) {
        timer.cancel();
        final failed = VideoDownloadProgress(
          downloadId: downloadId,
          recordingId: token.recordingId,
          status: DownloadStatus.failed,
          bytesReceived: entry.progress.bytesReceived,
          bytesTotal: totalBytes,
          kbps: 0,
          errorMessage: 'Simulated network drop',
        );
        _publish(entry, failed);
        controller.close();
        return;
      }
      final fraction = (tick / ticks).clamp(0.0, 1.0);
      final bytes = (totalBytes * fraction).toInt();
      final isDone = fraction >= 1.0;
      final next = VideoDownloadProgress(
        downloadId: downloadId,
        recordingId: token.recordingId,
        status: isDone ? DownloadStatus.completed : DownloadStatus.running,
        bytesReceived: bytes,
        bytesTotal: totalBytes,
        // 1 MB / second-ish, with a little jitter so the chart looks real.
        kbps: 8000 + sin(tick * 0.3) * 1500,
      );
      _publish(entry, next);
      if (isDone) {
        timer.cancel();
        controller.close();
      }
    });

    return VideoDownloadHandle(
      downloadId: downloadId,
      recordingId: token.recordingId,
      savePath: savePath,
      progress: controller.stream,
      cancel: () async {
        if (entry.progress.isTerminal) return;
        entry.timer?.cancel();
        final cancelled = VideoDownloadProgress(
          downloadId: downloadId,
          recordingId: token.recordingId,
          status: DownloadStatus.cancelled,
          bytesReceived: entry.progress.bytesReceived,
          bytesTotal: entry.progress.bytesTotal,
          kbps: 0,
        );
        _publish(entry, cancelled);
        await controller.close();
      },
    );
  }

  @override
  List<VideoDownloadProgress> activeDownloads() =>
      _downloads.values.map((e) => e.progress).toList(growable: false);

  @override
  Stream<VideoDownloadProgress> allDownloadProgress() =>
      _allProgressController.stream;

  void _publish(_DownloadState entry, VideoDownloadProgress p) {
    entry.progress = p;
    if (!entry.controller.isClosed) entry.controller.add(p);
    if (!_allProgressController.isClosed) _allProgressController.add(p);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> dispose() async {
    for (final s in _groups.values) {
      s.dispose();
    }
    _groups.clear();
    for (final d in _downloads.values) {
      d.timer?.cancel();
      if (!d.controller.isClosed) await d.controller.close();
    }
    _downloads.clear();
    await _allProgressController.close();
  }

  _GroupState _state(String deviceId) =>
      _groups.putIfAbsent(deviceId, () => _GroupState());
}

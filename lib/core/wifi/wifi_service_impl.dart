import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';

import '../async/seeded_broadcast.dart';
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

  // Per-device state stream controllers — created on demand. Seeded so a late
  // subscriber (LivePreviewView subscribes only when preview is toggled on,
  // after the group is already connecting/connected) replays the current state
  // immediately instead of being stuck until the next transition.
  final Map<String, SeededBroadcast<WifiDirectState>> _stateControllers = {};

  // Per-device EventChannel subscriptions — one per active connectGroup call.
  final Map<String, StreamSubscription<int>> _stateSubscriptions = {};

  // Per-device current group (null when disconnected).
  final Map<String, WifiDirectGroup> _currentGroups = {};

  // In-flight connectGroup calls — second caller awaits the same Completer
  // rather than racing with an already-running connect sequence.
  final Map<String, Completer<WifiDirectGroup>> _inflightConnects = {};

  // Monotonic per-device connect generation. _connectGroupInternal captures the
  // value at entry; disconnectGroup bumps it. A bumped generation means a
  // disconnect (or a newer connect) superseded the in-flight attempt while it
  // was awaiting the BLE round-trip or the permission dialog — the attempt must
  // abort before touching the platform channel so it can never run
  // _channel.connect AFTER a _channel.disconnect.
  final Map<String, int> _connectGen = {};

  // Device ids whose connect retry loop is currently running. While present,
  // the shared state listener suppresses transient `failed`/`idle` codes (a
  // formation attempt that didn't take) so the hero card doesn't flash
  // "WIFI · FAILED" between retries — the loop emits the final outcome itself.
  final Set<String> _connecting = {};

  // Android P2P state codes (mirror WifiDirectChannel.kt / wifi_p2p_channel).
  static const _kStateConnected = 2;
  static const _kStateFailed = 3;

  /// Returns (creating if absent) the seeded broadcast controller for [deviceId].
  SeededBroadcast<WifiDirectState> _stateController(String deviceId) {
    return _stateControllers.putIfAbsent(
      deviceId,
      SeededBroadcast<WifiDirectState>.new,
    );
  }

  void _emitState(String deviceId, WifiDirectState state) {
    final ctrl = _stateController(deviceId);
    if (!ctrl.isClosed) ctrl.add(state);
  }

  /// Best-effort: tell the firmware to release its P2P group. Called on connect
  /// failures that occur after StartWifiDirect already brought the group up, so a
  /// failed/aborted join doesn't leave the camera's group orphaned — that orphan
  /// made the next connect race a still-up group and surfaced as intermittent
  /// "wifi failed".
  Future<void> _releaseFirmwareGroup(String deviceId) async {
    try {
      await _ble.sendCommand<void>(deviceId, StopWifiDirectCommand());
    } catch (_) {
      // ignore — firmware may already be idle, or BLE may be down.
    }
  }

  /// True if a disconnect (or a newer connect) superseded the attempt that
  /// captured [gen] for [deviceId] — checked after each await in
  /// [_connectGroupInternal] before the platform join.
  bool _connectSuperseded(String deviceId, int gen) =>
      _connectGen[deviceId] != gen;

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

    // Capture this attempt's generation. disconnectGroup bumps it; if it no
    // longer matches after an await, a disconnect superseded us and we must
    // stop before the platform join (see _connectGen).
    final gen = (_connectGen[deviceId] ?? 0) + 1;
    _connectGen[deviceId] = gen;

    _emitState(deviceId, WifiDirectState.starting);

    // Android 13+ requires the NEARBY_WIFI_DEVICES runtime permission for
    // WifiP2pManager.connect(). Request it BEFORE StartWifiDirect so a denial
    // fails fast without bringing the camera's P2P group up — the old order asked
    // after StartWifiDirect, so a denial left the firmware group orphaned and the
    // next attempt raced a still-up group ("wifi failed"). permission_handler
    // reports granted on iOS / older Android where the permission doesn't gate.
    if (Platform.isAndroid) {
      final status = await Permission.nearbyWifiDevices.request();
      if (!status.isGranted && !status.isLimited) {
        _emitState(deviceId, WifiDirectState.failed);
        throw const WifiDirectException(
          'Nearby Wi-Fi devices permission denied — grant it to join the '
          'camera preview network.',
        );
      }
    }

    // Subscribe to the EventChannel BEFORE invoking connect so that the first
    // WifiDirectState.connected event from the Kotlin BroadcastReceiver is
    // never dropped. Events from a superseded attempt (a late native broadcast
    // after a disconnect/new connect) are gated out so a stale `failed` from a
    // prior teardown can't flash the hero card.
    await _stateSubscriptions[deviceId]?.cancel();
    _stateSubscriptions[deviceId] = _channel.stateStream.listen(
      (code) {
        if (_connectSuperseded(deviceId, gen)) return;
        final st = _codeToState(code);
        // While the connect retry loop is running, a single formation attempt
        // can briefly report idle/failed before the group settles (or before
        // the next retry). Suppress those transients; the loop drives the final
        // state. Let `connected`/`starting` through so a successful formation
        // still updates the hero card immediately.
        if (_connecting.contains(deviceId) &&
            (st == WifiDirectState.failed || st == WifiDirectState.idle)) {
          return;
        }
        _emitState(deviceId, st);
      },
      onError: (Object e) {
        if (_connectSuperseded(deviceId, gen)) return;
        _stateSubscriptions.remove(deviceId)?.cancel();
        _emitState(deviceId, WifiDirectState.failed);
      },
    );

    // BLE round-trip — ask the camera for group credentials.
    debugPrint('WIFI: requesting group credentials over BLE (StartWifiDirect)');
    final BleCommandResponse<WifiDirectGroup> response;
    try {
      response = await _ble.sendCommand<WifiDirectGroup>(
        deviceId,
        StartWifiDirectCommand(),
      );
    } catch (e) {
      debugPrint('WIFI: BLE credential fetch threw: $e');
      await _stateSubscriptions.remove(deviceId)?.cancel();
      await _releaseFirmwareGroup(deviceId);
      _emitState(deviceId, WifiDirectState.failed);
      throw WifiDirectException('BLE credential fetch failed: $e');
    }

    if (!response.isOk || response.payload == null) {
      await _stateSubscriptions.remove(deviceId)?.cancel();
      await _releaseFirmwareGroup(deviceId);
      _emitState(deviceId, WifiDirectState.failed);
      debugPrint(
        'WIFI: BLE credential fetch not OK: ${response.errorMessage} → FAILED',
      );
      throw WifiDirectException(
        'BLE credential fetch failed: ${response.errorMessage}',
      );
    }

    final group = response.payload!;
    debugPrint(
      'WIFI: credentials received ssid=${group.ssid} role="${group.role}" '
      'goIp=${group.groupOwnerIp}',
    );

    if (group.ssid.isEmpty || group.psk.isEmpty) {
      await _stateSubscriptions.remove(deviceId)?.cancel();
      await _releaseFirmwareGroup(deviceId);
      _emitState(deviceId, WifiDirectState.failed);
      throw const WifiDirectException(
        'BLE credential fetch returned empty ssid/psk',
      );
    }

    // Honor WifiDirectGroupResponse.role. The camera must be the WiFi Direct
    // group owner (GO) so the phone joins as a client at group.groupOwnerIp;
    // joining a group where the camera is itself a client would point the
    // preview/download URLs at the wrong host. An empty role is tolerated for
    // backward compatibility with firmware that does not report it yet.
    if (!_isGroupOwnerRole(group.role)) {
      await _stateSubscriptions.remove(deviceId)?.cancel();
      await _releaseFirmwareGroup(deviceId);
      _emitState(deviceId, WifiDirectState.failed);
      throw WifiDirectException(
        'camera reported unexpected WiFi Direct role "${group.role}"; '
        'expected group owner',
      );
    }

    // A disconnect may have arrived while we awaited the BLE round-trip. Bail
    // before the platform join so we never connect on top of a disconnect (which
    // leaves a phantom group + dropped failed state). A disconnect runs its own
    // firmware StopWifiDirect, so we don't duplicate the teardown here.
    if (_connectSuperseded(deviceId, gen)) {
      await _stateSubscriptions.remove(deviceId)?.cancel();
      throw const WifiDirectException(
        'WiFi Direct connect superseded by a disconnect',
      );
    }

    // Platform channel — join the P2P group on Android. Android's P2P
    // connect() is flaky on reconnect (a freshly cycled group, lingering state
    // after a force-close mid-preview) and frequently fails the first attempt
    // with BUSY, then succeeds on a retry — which is the manual "stop/start until
    // it works" loop. Automate it: each attempt clears the stale phone-side group
    // first (see WifiDirectChannel.connect), so a short retry turns the
    // intermittent failure into transparent recovery.
    // A negotiation that the framework *accepts* does not mean the group
    // actually forms: on a cold start a stale group, or the phone being made
    // group owner, leaves connect() resolved-OK while CONNECTION_CHANGED never
    // reaches the client-connected state — the intermittent "wifi failed" after
    // a reinstall. So each attempt is judged on real formation: accept the
    // negotiation, then wait for STATE_CONNECTED (ignoring transient idle). A
    // timeout or STATE_FAILED (e.g. phone-became-GO) retries the whole join —
    // the next attempt's removeGroup clears the offending phone-side group.
    _connecting.add(deviceId);
    Object? lastError;
    try {
      for (var attempt = 1; attempt <= _maxP2pConnectAttempts; attempt++) {
        // A disconnect (or newer connect) may have superseded us between retries.
        if (_connectSuperseded(deviceId, gen)) {
          await _stateSubscriptions.remove(deviceId)?.cancel();
          throw const WifiDirectException(
            'WiFi Direct connect superseded by a disconnect',
          );
        }
        try {
          debugPrint(
            'WIFI: P2P join attempt $attempt/$_maxP2pConnectAttempts '
            'ssid=${group.ssid}',
          );
          await _channel.connect(ssid: group.ssid, psk: group.psk);
          debugPrint(
            'WIFI: attempt $attempt negotiation accepted — '
            'awaiting group formation',
          );
          final formed = await _awaitGroupFormation(deviceId, gen);
          if (formed) {
            lastError = null;
            debugPrint('WIFI: attempt $attempt formed group');
            break;
          }
          lastError = const WifiDirectException(
            'group did not form (timeout or phone became group owner)',
          );
          debugPrint('WIFI: attempt $attempt did not form a usable group');
        } on Exception catch (e) {
          lastError = e;
          debugPrint('WIFI: P2P join attempt $attempt failed: $e');
        }
        if (attempt < _maxP2pConnectAttempts) {
          await Future<void>.delayed(_p2pConnectRetryDelay);
        }
      }
    } finally {
      _connecting.remove(deviceId);
    }
    if (lastError != null) {
      await _stateSubscriptions.remove(deviceId)?.cancel();
      await _releaseFirmwareGroup(deviceId);
      _emitState(deviceId, WifiDirectState.failed);
      debugPrint(
        'WIFI: all $_maxP2pConnectAttempts P2P join attempts failed → FAILED',
      );
      throw WifiDirectException(
        'P2P connect failed after $_maxP2pConnectAttempts attempts: $lastError',
      );
    }

    debugPrint('WIFI: P2P group joined ssid=${group.ssid}');
    _currentGroups[deviceId] = group;
    return group;
  }

  // Android P2P connect retry budget — see _connectGroupInternal.
  static const _maxP2pConnectAttempts = 3;
  static const _p2pConnectRetryDelay = Duration(milliseconds: 800);
  // How long to wait for CONNECTION_CHANGED to reach the client-connected state
  // after a negotiation is accepted. Observed real formation is ~4–5s; allow
  // margin before declaring the attempt failed and retrying.
  static const _p2pFormationTimeout = Duration(seconds: 9);

  // Waits for the native layer to report the group actually formed (client
  // connected) after a negotiation was accepted. Resolves true on
  // STATE_CONNECTED, false on STATE_FAILED, a formation timeout, or if the
  // attempt is superseded. Transient idle/starting codes during formation are
  // ignored. Listens on the shared broadcast [stateStream] independently of the
  // hero-card subscription.
  Future<bool> _awaitGroupFormation(String deviceId, int gen) async {
    final completer = Completer<bool>();
    void done(bool ok) {
      if (!completer.isCompleted) completer.complete(ok);
    }

    StreamSubscription<int>? sub;
    final timer = Timer(_p2pFormationTimeout, () => done(false));
    sub = _channel.stateStream.listen((code) {
      if (_connectSuperseded(deviceId, gen)) return done(false);
      if (code == _kStateConnected) return done(true);
      if (code == _kStateFailed) return done(false);
      // idle/starting/stopping → transient mid-formation; keep waiting.
    }, onError: (Object _) => done(false));

    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  @override
  Future<void> disconnectGroup(String deviceId) async {
    // Supersede any in-flight connect attempt: bumping the generation makes
    // _connectGroupInternal abort at its next checkpoint instead of running
    // _channel.connect after the disconnect below.
    _connectGen[deviceId] = (_connectGen[deviceId] ?? 0) + 1;

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
    // Real firmware serves RTSP H.264 at /preview on the group-owner IP +
    // preview port; geometry matches the firmware AppStreamConfig, which is tied
    // to the postprocess output (1280x720@30, 1500 kbps). Only used to size the
    // preview box; VLC decodes at the stream's actual resolution.
    return PreviewStreamDescriptor(
      url: group.previewUrl(),
      codec: PreviewCodec.rtspH264,
      width: 1280,
      height: 720,
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
  Future<String?> fetchThumbnail(String deviceId, String uuid) async {
    final group = _currentGroups[deviceId];
    if (group == null) return null; // not joined — can't reach the camera
    final url = '${group.downloadBaseUrl()}/thumbnails/$uuid';
    try {
      final resp = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          // 404 (no thumbnail) is an expected miss, not an exception.
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final bytes = resp.data;
      if (resp.statusCode != 200 || bytes == null || bytes.isEmpty) {
        return null;
      }
      final savePath = await _videoPathService.thumbnailPath(uuid);
      await File(savePath).writeAsBytes(bytes, flush: true);
      debugPrint('WIFI: cached thumbnail for $uuid (${bytes.length} bytes)');
      return savePath;
    } catch (e) {
      debugPrint('WIFI: thumbnail fetch failed for $uuid: $e');
      return null;
    }
  }

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
          _progress(
            downloadId,
            token.recordingId,
            DownloadStatus.failed,
            0,
            0,
            0,
            error: 'download rejected (HTTP ${resp.statusCode})',
          ),
        );
        return;
      }

      final total =
          int.tryParse(resp.headers.value(Headers.contentLengthHeader) ?? '') ??
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
          _progress(
            downloadId,
            token.recordingId,
            DownloadStatus.running,
            received,
            total,
            kbps,
          ),
        );
      }
      await sink.flush();
      await sink.close();
      sink = null;
      _publishProgress(
        entry,
        _progress(
          downloadId,
          token.recordingId,
          DownloadStatus.completed,
          received,
          total == 0 ? received : total,
          0,
        ),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _publishProgress(
          entry,
          _progress(
            downloadId,
            token.recordingId,
            DownloadStatus.cancelled,
            entry.progress.bytesReceived,
            entry.progress.bytesTotal,
            0,
          ),
        );
      } else {
        _publishProgress(
          entry,
          _progress(
            downloadId,
            token.recordingId,
            DownloadStatus.failed,
            entry.progress.bytesReceived,
            entry.progress.bytesTotal,
            0,
            error: e.message ?? 'network error',
          ),
        );
      }
    } catch (e) {
      _publishProgress(
        entry,
        _progress(
          downloadId,
          token.recordingId,
          DownloadStatus.failed,
          entry.progress.bytesReceived,
          entry.progress.bytesTotal,
          0,
          error: e.toString(),
        ),
      );
    } finally {
      try {
        await sink?.close();
      } catch (_) {
        /* already closing */
      }
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
  }) => VideoDownloadProgress(
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

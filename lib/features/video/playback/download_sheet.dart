import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ble/ble_providers.dart' show bleServiceProvider;
import '../../../core/models/recording.dart' show RecordingMetadata;
import '../../../core/models/wifi.dart';
import '../../../core/services/clip_service.dart';
import '../../../core/services/gallery_service.dart';
import '../../../core/wifi/wifi_providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/wf_button.dart';
import '../../../core/state/db_providers.dart'
    show clipServiceProvider, videoPathServiceProvider;
import '../../camera/camera_state.dart' show activeCameraIdProvider;
import '../video_state.dart'
    show
        isOnDeviceProvider,
        liveSessionActiveProvider,
        LibraryMatch,
        LibraryEvent;

// Shown when retrieval is attempted (or rejected) during a live session.
const _kLiveSessionBlocked =
    "Can't retrieve videos while a match is live. End the session first.";

String _mapDownloadError(Object e) {
  // Firmware rejects mid-session retrieval with LIVE_SESSION_ACTIVE — surface
  // the same friendly message as the client-side gate.
  if (e.toString().contains('LIVE_SESSION_ACTIVE')) return _kLiveSessionBlocked;
  return e.toString();
}

/// Real recording metadata (size + duration) reported by the connected camera
/// for [matchId], or null when no camera is connected or it has no such
/// recording. The download sheet overlays these on top of the scheduled values
/// stored in the library row so size/duration/ETA reflect the actual file.
final deviceRecordingProvider =
    FutureProvider.family<RecordingMetadata?, String>((ref, matchId) async {
      final deviceId = ref.watch(activeCameraIdProvider);
      if (deviceId == null) return null;
      try {
        final recordings = await ref
            .watch(bleServiceProvider)
            .listRecordings(deviceId);
        for (final r in recordings) {
          if (r.id == matchId) return r;
        }
      } catch (_) {
        // Offline / BLE error — fall back to stored values.
      }
      return null;
    });

// Assumed sustained WiFi-Direct throughput for the download-time estimate.
const double _kWifiBytesPerSecond = 2.5 * 1024 * 1024;

// On-demand overlay burn (#6 A6c): how often to poll the camera's export job,
// and how long to wait before giving up (a software H.264 burn of a full match
// takes a while on the no-NVENC Orin Nano).
const Duration _kExportPollInterval = Duration(seconds: 1);
const Duration _kExportTimeout = Duration(minutes: 10);

/// Verify-before-action: how long to wait (polling reachability) for the phone
/// to rejoin the camera's saved WiFi network before giving up on a download.
const Duration _kReachablePollInterval = Duration(seconds: 1);
const Duration _kReachableWaitBudget = Duration(seconds: 20);
const _kUnreachable =
    "Couldn't reach the camera. Make sure you're near it and connected, then try again.";

/// How many consecutive poll round-trips may fail before we abandon an
/// in-flight overlay export. A single dropped BLE exchange over a multi-minute
/// burn is expected; only a sustained run of failures means the job is lost.
const int _kMaxConsecutivePollErrors = 5;

String _fmtSize(int bytes) {
  const mb = 1024 * 1024;
  if (bytes >= mb) {
    return '${(bytes / mb).toStringAsFixed(bytes >= 10 * mb ? 0 : 1)} MB';
  }
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}

String _fmtClock(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String _fmtEta(int bytes) {
  final secs = (bytes / _kWifiBytesPerSecond).ceil();
  if (secs < 60) return '~${secs}s';
  return '~${(secs / 60).ceil()} min';
}

class DownloadSheet extends ConsumerStatefulWidget {
  const DownloadSheet({
    super.key,
    required this.match,
    required this.selectedEvents,
    required this.allEvents,
  });
  final LibraryMatch match;

  /// Events the user has checked (for "Selected highlights" option).
  final List<LibraryEvent> selectedEvents;

  /// All events in the match (for "All highlights" option).
  final List<LibraryEvent> allEvents;

  @override
  ConsumerState<DownloadSheet> createState() => _DownloadSheetState();
}

enum _DownloadMode { full, all, selected }

class _DownloadSheetState extends ConsumerState<DownloadSheet> {
  VideoDownloadHandle? _handle;
  VideoDownloadProgress? _progress;
  String? _error;
  StreamSubscription<VideoDownloadProgress>? _subscription;
  _DownloadMode _mode = _DownloadMode.full;

  /// Full-game only (#6 A6c): burn the scoreboard overlay into the downloaded
  /// copy. The camera renders it on demand from the stored overlay timeline.
  bool _withOverlay = false;

  /// True while the camera is rendering the overlaid L2 (before the download
  /// itself starts). Drives the "Rendering overlay…" surface.
  bool _exporting = false;

  /// True while waiting for the phone to (re)join the camera's WiFi link before
  /// a download can start. Drives the "Reconnecting…" surface.
  bool _reconnecting = false;

  @override
  void dispose() {
    _subscription?.cancel();
    // Sheet is closing — if a download is mid-flight, leave it running.
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _error = null);

    // HARD INVARIANT — no past-video retrieval while a match is live.
    if (ref.read(liveSessionActiveProvider)) {
      setState(() => _error = _kLiveSessionBlocked);
      return;
    }

    if (_mode == _DownloadMode.full) {
      if (_withOverlay) {
        await _startOverlayDownload();
      } else {
        await _startFullDownload();
      }
    } else {
      await _startClips(
        _mode == _DownloadMode.all ? widget.allEvents : widget.selectedEvents,
      );
    }
  }

  /// Verify-before-action: confirm the camera link is up, waiting (polling) if
  /// the phone hasn't rejoined the saved network yet. Returns false (and sets a
  /// clear [_error]) if it never becomes reachable within the budget. The phone
  /// OS owns rejoining the saved network; we only observe whether it happened.
  Future<bool> _ensureReachable(String deviceId) async {
    final wifi = ref.read(wifiServiceProvider);
    if (await wifi.isCameraReachable(deviceId)) return true;
    if (!mounted) return false;
    setState(() => _reconnecting = true);
    // Count polls rather than wall-clock so the wait is driven purely by timers
    // (deterministic under fake-async tests; identical budget in production).
    final maxPolls =
        _kReachableWaitBudget.inMilliseconds ~/
        _kReachablePollInterval.inMilliseconds;
    try {
      for (var i = 0; i < maxPolls; i++) {
        await Future<void>.delayed(_kReachablePollInterval);
        if (!mounted) return false;
        if (await wifi.isCameraReachable(deviceId)) {
          setState(() => _reconnecting = false);
          return true;
        }
      }
    } finally {
      if (mounted && _reconnecting) setState(() => _reconnecting = false);
    }
    if (mounted) setState(() => _error = _kUnreachable);
    return false;
  }

  Future<void> _startFullDownload() async {
    final deviceId = ref.read(activeCameraIdProvider);
    if (deviceId == null) {
      setState(() => _error = 'Connect a camera first');
      return;
    }
    // Capture references before any await so the onDone callback can run
    // correctly even if the sheet has already been dismissed (mounted=false),
    // and so the BuildContext isn't used across the reachability wait.
    final matchId = widget.match.id;
    final pathSvc = ref.read(videoPathServiceProvider);
    final container = ProviderScope.containerOf(context);

    if (!await _ensureReachable(deviceId)) return;

    try {
      final handle = await ref
          .read(wifiServiceProvider)
          .downloadRecording(deviceId, matchId);
      setState(() => _handle = handle);
      _subscription = handle.progress.listen(
        (p) {
          if (mounted) setState(() => _progress = p);
        },
        onDone: () async {
          // Only invalidate and save if the download actually completed
          // (not cancelled or failed).
          if (_progress?.status != DownloadStatus.completed) return;
          // The file is now on device (MockWifiService publishes completed
          // only after _writePlaceholder finishes). Invalidate the provider
          // and save to gallery regardless of whether the sheet is still open.
          container.invalidate(isOnDeviceProvider(matchId));
          final path = await pathSvc.recordingPath(matchId);
          await GalleryService.saveVideo(
            sourcePath: path,
            displayName: '$matchId.mp4',
          );
        },
        onError: (e) {
          if (mounted) setState(() => _error = _mapDownloadError(e));
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _mapDownloadError(e));
    }
  }

  /// #6 A6c: ask the camera to burn the overlay into an L2, poll until ready,
  /// then download that overlaid copy (kept distinct from the clean L1).
  Future<void> _startOverlayDownload() async {
    final deviceId = ref.read(activeCameraIdProvider);
    if (deviceId == null) {
      setState(() => _error = 'Connect a camera first');
      return;
    }
    final matchId = widget.match.id;
    final ble = ref.read(bleServiceProvider);
    final wifi = ref.read(wifiServiceProvider);
    final pathSvc = ref.read(videoPathServiceProvider);
    final container = ProviderScope.containerOf(context);

    setState(() => _exporting = true);
    try {
      var job = await ble.requestOverlayExport(deviceId, matchId);
      final deadline = DateTime.now().add(_kExportTimeout);
      var consecutivePollErrors = 0;
      while (!job.isTerminal) {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('overlay render timed out', _kExportTimeout);
        }
        await Future<void>.delayed(_kExportPollInterval);
        // Stop polling if the sheet was dismissed mid-render — otherwise this
        // loop keeps firing a BLE round-trip every interval until the deadline.
        if (!mounted) return;
        try {
          job = await ble.pollOverlayExport(deviceId, job.jobId);
          consecutivePollErrors = 0;
        } on Exception {
          // Tolerate a few dropped polls before giving up — a momentary BLE
          // blip during a long burn should not abort the whole export.
          if (++consecutivePollErrors >= _kMaxConsecutivePollErrors) rethrow;
        }
      }
      if (job.isUnknown) {
        throw const WifiDirectException(
          'the camera lost track of the render job (did it restart?)',
        );
      }
      if (job.isFailed || job.token == null) {
        throw WifiDirectException(
          job.errorMessage ?? 'the camera could not render the overlay',
        );
      }

      final overlayPath = await pathSvc.overlayRecordingPath(matchId);
      // Burn done — drop the "rendering" surface, then make sure the link is up
      // before pulling the L2 (the long burn may have outlasted the WiFi join).
      if (mounted) setState(() => _exporting = false);
      if (!await _ensureReachable(deviceId)) return;
      final handle = await wifi.startDownload(
        deviceId,
        job.token!,
        saveAs: overlayPath,
      );
      if (!mounted) return;
      setState(() => _handle = handle);
      _subscription = handle.progress.listen(
        (p) {
          if (mounted) setState(() => _progress = p);
        },
        onDone: () async {
          if (_progress?.status != DownloadStatus.completed) return;
          container.invalidate(isOnDeviceProvider(matchId));
          await GalleryService.saveVideo(
            sourcePath: overlayPath,
            displayName: '${matchId}_overlay.mp4',
          );
        },
        onError: (e) {
          if (mounted) setState(() => _error = _mapDownloadError(e));
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _error = _mapDownloadError(e);
      });
    }
  }

  Future<void> _startClips(List<LibraryEvent> events) async {
    if (events.isEmpty) {
      setState(() => _error = 'No events selected');
      return;
    }
    final clipSvc = ref.read(clipServiceProvider);
    final videoPathSvc = ref.read(videoPathServiceProvider);
    // Clips are sliced locally from a full game already on device — the camera
    // has no per-clip burn. With the overlay option we slice from the overlaid
    // full game (L2, must be downloaded first); otherwise from the clean L1.
    final String sourcePath;
    if (_withOverlay) {
      sourcePath = await videoPathSvc.overlayRecordingPath(widget.match.id);
      if (!await File(sourcePath).exists()) {
        if (mounted) {
          setState(
            () => _error =
                'Download the full game with the overlay first, then clip it',
          );
        }
        return;
      }
    } else {
      final onDevice = await ref.read(
        isOnDeviceProvider(widget.match.id).future,
      );
      if (!onDevice) {
        if (mounted) setState(() => _error = 'Download the full game first');
        return;
      }
      sourcePath = await videoPathSvc.recordingPath(widget.match.id);
    }
    // Process every selected event independently — one clip failing must NOT
    // abort the rest (a goal near the end of the recording, etc.). Track trims
    // vs gallery saves separately so the report is honest, and collect the
    // per-event reasons for anything that didn't make it.
    var savedToGallery = 0;
    final failures = <String>[];
    for (final event in events) {
      try {
        final startSeconds = (event.timeSeconds - 15)
            .clamp(0, double.infinity)
            .toInt();
        final clipPath = await clipSvc.trim(
          matchId: widget.match.id,
          sourcePath: sourcePath,
          startSeconds: startSeconds,
          durationSeconds: 30,
          label: event.label,
        );
        // Export to the device gallery so the clip is actually visible — trim()
        // only writes it to app-private storage + the clips DB. A gallery-export
        // failure is reported (it was previously swallowed, so a clip could be
        // "saved" yet never appear in the gallery).
        final name =
            '${widget.match.opponent}_${event.label}_${savedToGallery + 1}.mp4'
                .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        // saveVideo swallows its own errors and returns null on failure — check
        // the result rather than relying on a throw, so a gallery-insert failure
        // is reported instead of silently counted as "saved".
        final savedUri = await GalleryService.saveVideo(
          sourcePath: clipPath,
          displayName: name,
        );
        if (savedUri != null) {
          savedToGallery++;
        } else {
          failures.add('${event.label}: clipped but not added to the gallery');
        }
      } on ClipTrimException catch (e) {
        failures.add('${event.label}: ${e.message}');
      } catch (e) {
        failures.add('${event.label}: $e');
      }
    }
    if (!mounted) return;
    // Nothing made it to the gallery — keep the sheet open and show why.
    if (savedToGallery == 0) {
      setState(
        () => _error = failures.isEmpty
            ? 'No clips could be saved'
            : 'No clips saved — ${failures.first}',
      );
      return;
    }
    Navigator.of(context).pop();
    final summary = failures.isEmpty
        ? '$savedToGallery clip${savedToGallery == 1 ? '' : 's'} saved to gallery'
        : '$savedToGallery of ${events.length} clipped · ${failures.length} failed';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(summary)));
  }

  @override
  Widget build(BuildContext context) {
    final running = _handle != null;
    if (_reconnecting) return _buildReconnecting();
    if (_exporting) return _buildExporting();
    if (running) return _buildProgress();
    // Overlay the camera-reported real size/duration when available; fall back
    // to the library row's scheduled values when offline.
    final deviceRec = ref
        .watch(deviceRecordingProvider(widget.match.id))
        .valueOrNull;
    final fullSize = deviceRec != null
        ? _fmtSize(deviceRec.sizeBytes)
        : '${widget.match.fullSizeMb} MB';
    final fullDuration = (deviceRec != null && deviceRec.durationSeconds > 0)
        ? _fmtClock(deviceRec.durationSeconds)
        : widget.match.fullDuration;
    final eta = deviceRec != null
        ? '${_fmtEta(deviceRec.sizeBytes)} @ WiFi'
        : '~— @ WiFi';
    final selectedCount = widget.selectedEvents.length;
    final allCount = widget.allEvents.length;
    final opts = <_Opt>[
      _Opt(
        key: _DownloadMode.full,
        label: 'Full game',
        sub: '$fullDuration · $fullSize · $eta',
      ),
      if (allCount > 0)
        _Opt(
          key: _DownloadMode.all,
          label: 'All highlights',
          sub:
              '$allCount event${allCount == 1 ? '' : 's'} · requires full game on device',
        ),
      if (selectedCount > 0)
        _Opt(
          key: _DownloadMode.selected,
          label: 'Selected highlights',
          sub:
              '$selectedCount event${selectedCount == 1 ? '' : 's'} selected · requires full game on device',
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: T.fillMid,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Download',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: T.ink,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.match.date} · ${widget.match.opponent}',
            style: const TextStyle(fontSize: 12, color: T.ink2),
          ),
          const SizedBox(height: 14),
          ...opts.map((o) {
            final selected = _mode == o.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GestureDetector(
                onTap: () => setState(() => _mode = o.key),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected ? T.accentSoft : T.fillSoft,
                    border: Border.all(
                      color: selected ? T.accent : T.hair,
                      width: selected ? 1.4 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      _Radio(on: selected),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              o.label,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: T.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              o.sub,
                              style: const TextStyle(
                                fontSize: 11,
                                color: T.ink2,
                                fontFamily: T.mono,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () => setState(() => _withOverlay = !_withOverlay),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Row(
                children: [
                  _CheckBox(on: _withOverlay),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _mode == _DownloadMode.full
                          ? 'Burn in scoreboard overlay'
                          : 'Clip from the overlaid game',
                      style: const TextStyle(fontSize: 13, color: T.ink),
                    ),
                  ),
                  const Text(
                    'rendered on camera',
                    style: TextStyle(
                      fontSize: 10,
                      color: T.ink3,
                      fontFamily: T.mono,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: WfButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: WfButton(
                  label: 'Start download',
                  variant: WfButtonVariant.primary,
                  onPressed: _start,
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: T.danger),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgress() {
    final p = _progress;
    final fraction = p?.fraction ?? 0;
    final received = ((p?.bytesReceived ?? 0) / 1024 / 1024).toStringAsFixed(1);
    final total = ((p?.bytesTotal ?? 0) / 1024 / 1024).toStringAsFixed(1);
    final kbps = (p?.kbps ?? 0).toStringAsFixed(0);
    final status = switch (p?.status) {
      DownloadStatus.queued => 'Queued',
      DownloadStatus.running => 'Downloading',
      DownloadStatus.paused => 'Paused',
      DownloadStatus.completed => 'Completed',
      DownloadStatus.failed => 'Failed',
      DownloadStatus.cancelled => 'Cancelled',
      null => 'Starting',
    };
    final terminal = p?.isTerminal ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: T.fillMid,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            status,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: T.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.match.date} · ${widget.match.opponent}',
            style: const TextStyle(fontSize: 12, color: T.ink2),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: T.fillMid,
              valueColor: const AlwaysStoppedAnimation<Color>(T.accent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$received / $total MB',
                style: const TextStyle(
                  fontFamily: T.mono,
                  fontSize: 11,
                  color: T.ink2,
                ),
              ),
              Text(
                '$kbps KB/s',
                style: const TextStyle(
                  fontFamily: T.mono,
                  fontSize: 11,
                  color: T.ink2,
                ),
              ),
              Text(
                '${(fraction * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontFamily: T.mono,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: T.ink,
                ),
              ),
            ],
          ),
          if (p?.errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              p!.errorMessage!,
              style: const TextStyle(fontSize: 12, color: T.danger),
            ),
          ] else if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: T.danger),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: WfButton(
                  label: terminal ? 'Close' : 'Cancel',
                  onPressed: () async {
                    if (!terminal) await _handle?.cancel();
                    if (mounted) Navigator.of(context).pop();
                  },
                ),
              ),
              if (terminal && p?.status == DownloadStatus.completed) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: WfButton(
                    label: 'Done',
                    variant: WfButtonVariant.primary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExporting() => _buildBusy(
    'Rendering overlay on camera…',
    'The camera is burning the scoreboard into a copy. This can take a '
        'few minutes for a full match.',
  );

  Widget _buildReconnecting() => _buildBusy(
    'Reconnecting to camera…',
    "Waiting for the WiFi link to come back. Make sure you're near the "
        'camera — this clears on its own once it reconnects.',
  );

  /// Shared spinner surface for the pre-download busy states (rendering an
  /// overlay, or waiting for the WiFi link). [title] is the bold headline,
  /// [subtitle] the muted explanation.
  Widget _buildBusy(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: T.fillMid,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(T.accent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: T.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: T.ink2)),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: T.danger),
            ),
          ],
          const SizedBox(height: 18),
          WfButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _Opt {
  const _Opt({required this.key, required this.label, required this.sub});
  final _DownloadMode key;
  final String label;
  final String sub;
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: on ? T.accent : Colors.transparent,
        border: Border.all(color: on ? T.accent : T.hair, width: 2),
      ),
      alignment: Alignment.center,
      child: on
          ? const Icon(Icons.check_rounded, size: 13, color: T.accentInk)
          : null,
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? T.accent : Colors.transparent,
        border: Border.all(color: on ? T.accent : T.hair, width: 2),
      ),
      alignment: Alignment.center,
      child: on
          ? Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: T.accentInk,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}

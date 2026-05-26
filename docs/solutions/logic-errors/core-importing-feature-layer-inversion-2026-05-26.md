---
title: Inverted layer dependency — core model importing from feature module
date: 2026-05-26
category: docs/solutions/logic-errors/
module: core/models
problem_type: logic_error
component: tooling
symptoms:
  - "lib/core/models/overlay.dart contained an import of lib/features/video/video_state.dart"
  - "Core layer could not be compiled or tested independently of the feature layer"
  - "Factory constructor OverlayState.fromEvents() lived in the core model but depended on feature-level types"
  - "DownloadStatus.completed emitted before the placeholder file was written to disk"
  - "StreamSubscription from handle.progress.listen() was not stored, preventing cancellation in dispose()"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags:
  - dependency-inversion
  - layer-architecture
  - core-features-boundary
  - flutter
  - async-timing
  - stream-subscription
  - download
  - overlay
---

# Inverted layer dependency — core model importing from feature module

## Problem

A `lib/core/` model (`OverlayState`) imported directly from a `lib/features/` file (`video_state.dart`) to satisfy a static factory method, inverting the intended core→feature dependency direction. The same code-review pass also uncovered an async race where `DownloadStatus.completed` was emitted before the file was physically written to disk, and a `StreamSubscription` leak in `DownloadSheet` because the subscription handle was never stored for cancellation. All three issues emerged from the same video-playback and download feature work.

## Symptoms

- `lib/core/models/overlay.dart` carried `import '../../features/video/video_state.dart'`, making core depend on a feature — any refactor of `video_state.dart` risked breaking core, and the core layer could not be independently tested or reused.
- In integration testing, `isOnDeviceProvider` could resolve to `true` immediately after `completed` was emitted, yet the placeholder file might not yet exist on disk, causing file-not-found errors in downstream gallery-save logic.
- Dismissing `DownloadSheet` mid-download left the `progress` stream listener alive because `dispose()` had no reference to cancel it; the `onDone` callback could then fire against a disposed widget.

## What Didn't Work

- Keeping `fromEvents` as a static method on `OverlayState` and moving `LibraryEvent` to core: `LibraryEvent` carries too much feature-layer context (match UI state, event kinds) to be a clean core type.
- Emitting `completed` and then writing the file in the same timer tick: the stream add is synchronous but subscribers run on the event loop, so any subscriber that immediately reads the file could race the `writeAsBytesSync` call depending on microtask scheduling.

## Solution

### 1. Inverted dependency — extract a feature-layer bridge function

The `fromEvents` static method was removed from `OverlayState` entirely. `lib/core/models/overlay.dart` now contains only pure data fields and the `atTime()` binary-search utility — no imports from any feature layer:

```dart
// lib/core/models/overlay.dart — no feature imports
class OverlayState {
  const OverlayState({
    required this.timeSeconds,
    required this.homeScore,
    required this.awayScore,
    required this.period,
    required this.recentEventLabel,
  });
  final int timeSeconds;
  final int homeScore;
  final int awayScore;
  final int period;
  final String? recentEventLabel;

  static OverlayState atTime(List<OverlayState> states, int timeSeconds) { ... }
}
```

A new feature-layer file `lib/features/video/overlay_helper.dart` owns the conversion logic and is the only place that imports both sides:

```dart
// lib/features/video/overlay_helper.dart
import '../../core/models/overlay.dart';
import 'video_state.dart' show LibraryEvent;

List<OverlayState> buildOverlayStates(
  List<LibraryEvent> events, {
  required int periodLengthSeconds,
  required String homeShortName,
}) {
  // periodLengthSeconds == 0 guard: default period to 1 to avoid divide-by-zero
  final period = periodLengthSeconds > 0
      ? event.timeSeconds ~/ periodLengthSeconds + 1
      : 1;
  // ...
}
```

All call sites updated from `OverlayState.fromEvents(...)` to `buildOverlayStates(...)`.

### 2. Async race — write before emitting completed

The timer callback in `wifi_service_impl.dart` was restructured so `DownloadStatus.completed` is only published after `writeAsBytesSync` returns successfully. While writing, status stays `running` at 100%:

```dart
} else {
  // 1. Publish running@100% while writing
  _publishProgress(entry, VideoDownloadProgress(
    status: DownloadStatus.running,
    bytesReceived: totalBytes,
    bytesTotal: totalBytes,
    kbps: 0,
    ...
  ));
  timer.cancel();
  try {
    File(savePath).writeAsBytesSync([0x00], flush: true);
  } catch (e) {
    _publishProgress(entry, VideoDownloadProgress(
      status: DownloadStatus.failed,
      errorMessage: e.toString(),
      ...
    ));
    controller.close();
    return;
  }
  // 2. File confirmed on disk — now emit completed
  _publishProgress(entry, VideoDownloadProgress(
    status: DownloadStatus.completed,
    bytesReceived: totalBytes,
    bytesTotal: totalBytes,
    kbps: 0,
    ...
  ));
  controller.close();
}
```

The same pattern was applied to `MockWifiService`.

### 3. StreamSubscription leak — store and cancel in dispose

`_DownloadSheetState` now declares a `StreamSubscription` field, assigns `handle.progress.listen(...)` to it, and cancels in `dispose()`. The `onDone` guard ensures gallery-save only fires on genuine completion:

```dart
StreamSubscription<VideoDownloadProgress>? _subscription;

@override
void dispose() {
  _subscription?.cancel();
  // Sheet closing — mid-flight download continues independently.
  super.dispose();
}

// In _startFullDownload:
_subscription = handle.progress.listen(
  (p) { if (mounted) setState(() => _progress = p); },
  onDone: () async {
    if (_progress?.status != DownloadStatus.completed) return;
    container.invalidate(isOnDeviceProvider(matchId));
    final path = await pathSvc.recordingPath(matchId);
    await GalleryService.saveVideo(sourcePath: path, displayName: '$matchId.mp4');
  },
  onError: (e) {
    if (mounted) setState(() => _error = e.toString());
  },
  cancelOnError: true,
);
```

## Why This Works

The core→feature inversion happened because `OverlayState.fromEvents` needed to consume `LibraryEvent`, a feature type, making the static method a construction-time coupling that pulled the wrong dependency direction. Extracting it as a free function in the feature layer lets each layer import only downward: features import core, core imports nothing from features.

The async race existed because `_publishProgress` adds to the stream synchronously, and a subscriber's `onDone` fires on the next event-loop turn — after `controller.close()` but potentially before the file write that was meant to precede it. Flipping the order (write → close → emit completed) removes the race entirely.

The subscription leak was an ownership gap: `listen()` returns a `StreamSubscription` the caller must hold and cancel; discarding the return value means the subscription lives until the stream closes on its own, ignoring widget lifecycle.

## Prevention

- **Enforce layer boundaries in CI**: add an import-lint rule (e.g., `dart_code_metrics` custom rule or a simple `grep` check in CI) that rejects any `import` in `lib/core/` that references a path under `lib/features/`. The Dart compiler does not enforce this.
- **Bridge pattern for cross-layer factory methods**: when a core model needs a constructor that consumes a feature-layer type, create a helper file in the feature layer (e.g., `overlay_helper.dart`) that imports both sides. Never pull the dependency downward into core.
- **Write before terminal status**: for any `StreamController` that emits a terminal status (`completed`, `failed`, `cancelled`), complete the side-effect (file write, DB update) before publishing the terminal event, then close the controller. Pattern: `do work → publish result → close`.
- **Always store `StreamSubscription` handles**: assign `listen()` return values to `State` fields and cancel them in `dispose()`. The `flutter_lints` `cancel_subscriptions` lint can catch unlisted subscriptions statically.
- **Guard `onDone` against non-success statuses**: `onDone` fires whether the stream ended cleanly, on error, or after cancel. Check `_progress?.status == DownloadStatus.completed` before running any success-only side-effects.

## Related Issues

- Commit `d39d4ed` — `fix(review): apply code-review fixes across playback, download, and overlay` — all three fixes applied together in a single code-review pass.
- `docs/solutions/architecture-patterns/app-source-of-truth-drift-sqlite-2026-05-06.md` — covers where business data lives (Drift vs BLE); mentions `ref.onDispose(sub.cancel)` in passing for Riverpod subscription teardown (different context, same lifecycle principle).

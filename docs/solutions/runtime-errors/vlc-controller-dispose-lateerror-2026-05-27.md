---
title: VlcPlayerController.dispose() throws async LateError when native view never attached
date: 2026-05-27
category: runtime-errors
module: lib/core/widgets/live_preview_view.dart
problem_type: runtime_error
component: frontend_stimulus
symptoms:
  - "LateInitializationError: Field '_viewId' has not been initialized."
  - "Widget test fails during teardown when a connected LivePreviewView is unmounted"
  - "synchronous try/catch around controller.dispose() does not catch the error"
root_cause: async_timing
resolution_type: code_fix
severity: medium
tags: [flutter, flutter-vlc-player, dispose, async-error, late-field, widget-test]
---

# VlcPlayerController.dispose() throws async LateError when native view never attached

## Problem
`VlcPlayerController.dispose()` (flutter_vlc_player) is an `async` method that
completes with a `LateInitializationError` on its `late _viewId` field when the
native platform view never attached. Because the error escapes into the
returned `Future`, a synchronous `try/catch` around the call cannot catch it —
it surfaces as an unhandled async error and fails widget tests on teardown.

## Symptoms
- `LateInitializationError: Field '_viewId@...' has not been initialized.`
- Stack: `VlcPlayerController._viewId` → `VlcPlayerController.dispose` → the
  widget's `State.dispose()`.
- Happens in the headless widget-test environment (no native view ever
  initializes), and is possible on a real device when the preview is torn down
  before the platform view finishes attaching (e.g. rapid enable→disable, or
  navigating away on the first frame).

## What Didn't Work
- Wrapping the call in a synchronous block:
  ```dart
  try {
    controller.dispose(); // returns a Future; LateError lands there, not here
  } catch (e) {
    // never runs — the error is async
  }
  ```
  The error is raised inside the async `dispose()` future, so the surrounding
  synchronous `try/catch` never sees it.

## Solution
Attach `.catchError` to the future returned by `dispose()` and swallow the
LateError (there is nothing to release when the native view never attached):

```dart
void _disposeVlc(VlcPlayerController? controller) {
  if (controller == null) return;
  controller.removeListener(_onVlcChange);
  // dispose() is async and completes with a LateError if its native view
  // never attached — handle it on the future, not via a sync try/catch.
  // ignore: discarded_futures
  controller.dispose().catchError((Object e) {
    debugPrint('LivePreviewView: VLC dispose skipped ($e)');
  });
}
```

Route every disposal site (the `State.dispose()` lifecycle method, the
teardown-on-preview-off path, and the controller swap when the URL changes)
through this single helper.

## Why This Works
In Dart, a `throw` inside an `async` function — even before the first `await` —
is captured into the returned `Future` rather than thrown synchronously to the
caller. So the only place to observe the error is on the future itself.
`.catchError` registers an error handler on that future, converting the
unhandled async error into a no-op. The guard is legitimate at the plugin
boundary: when `_viewId` was never set there is no native resource to free.

## Prevention
- Treat any plugin `dispose()`/`close()` that returns a `Future` as a source of
  async errors — guard with `.catchError`, never a bare synchronous `try/catch`.
- In widget tests that mount a platform-view-backed widget (VLC, webview,
  camera, maps), expect that the controller's `dispose()` cannot fully run
  headlessly; ensure the disposal path tolerates an uninitialized native view
  so teardown stays green.

## Related Issues
- Surfaced while fixing `live_preview_view.dart` (commit `789b027`) to play the
  mock-camera-wifi container RTSP stream in dev instead of a bundled clip.
- Test coverage: `test/core/widgets/live_preview_view_test.dart`.

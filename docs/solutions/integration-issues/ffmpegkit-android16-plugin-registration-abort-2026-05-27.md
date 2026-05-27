---
title: "ffmpeg_kit_flutter_new_full UnsatisfiedLinkError on Android 16 aborts all plugin registration"
date: 2026-05-27
category: integration-issues
module: android
problem_type: integration_issue
component: tooling
severity: critical
symptoms:
  - "App freezes on splash screen — runApp() is never called"
  - "App loads but data seeding fails with EXCEPTION CAUGHT BY APPLYDATAMODE"
  - "PlatformException(channel-error) on any plugin channel call (shared_preferences, path_provider, sqlite3)"
  - "SIGSEGV in libdartjni.so / FindClass when path_provider_android 2.3.x is installed"
  - "ADB logcat: FFmpegKit Error followed by MissingPluginException for every subsequent plugin"
  - "UnsatisfiedLinkError: cannot locate symbol _ZTINSt6__ndk117bad_function_callE referenced by libavfilter.so"
root_cause: third_party_incompatibility
resolution_type: config_change
tags: [android, android-16, ffmpeg-kit, plugin-registration, gradle, flutter, unsatisfiedlinkerror, abi-break]
---

# ffmpeg_kit_flutter_new_full UnsatisfiedLinkError on Android 16 aborts all plugin registration

## Problem

`ffmpeg_kit_flutter_new_full 2.0.0` bundles `libavfilter.so` compiled with LLVM/libc++ that references
the C++ RTTI symbol `_ZTINSt6__ndk117bad_function_callE` (`std::bad_function_call`). Android 16
(API 36) removed this symbol from the system runtime.

At startup, Android's dynamic linker attempts to resolve `libavfilter.so`. The symbol lookup fails,
causing `FFmpegKitFlutterPlugin.onAttachedToActivity()` to throw `java.lang.Error: FFmpegKit failed
to start` (wrapping `UnsatisfiedLinkError`).

Flutter auto-generates `GeneratedPluginRegistrant.java` with `catch (Exception e)` around each
plugin's registration block. `UnsatisfiedLinkError` extends `LinkageError extends Error` — not a
subclass of `java.lang.Exception` — so the `Error` escapes all catch blocks and aborts the entire
`registerWith()` method. Every plugin registered after FFmpegKit in the list is never registered.

## Symptoms

- App freezes on splash screen — `runApp()` is never called.
- App loads but all data is missing or seeding fails: `EXCEPTION CAUGHT BY APPLYDATAMODE`.
- Dart `PlatformException` on any plugin channel call:
  ```
  PlatformException(channel-error, Unable to establish connection on channel:
    "dev.flutter.pigeon.shared_preferences_android.SharedPreferencesApi.getAll".)
  ```
- SIGSEGV crash in `libdartjni.so` / `FindClass` when `path_provider_android` 2.3.x is installed
  (JNI bridge crashes when JNI is uninitialized, before Dart can catch anything).
- ADB logcat shows FFmpegKit failing, followed by every subsequent plugin also failing:
  ```
  E/GeneratedPluginRegistrant: Error registering plugin ffmpeg_kit_flutter_new_full
  W/FlutterBluePlus:    MissingPluginException(...)
  W/PathProvider:       MissingPluginException(...)
  W/SharedPreferences:  MissingPluginException(...)
  W/Sqlite3:            MissingPluginException(...)
  ```
- Root cause in logcat:
  ```
  java.lang.Error: FFmpegKit failed to start
    Caused by: java.lang.UnsatisfiedLinkError: cannot locate symbol
      "_ZTINSt6__ndk117bad_function_callE" referenced by "libavfilter.so"
  ```

The 9 plugins registered after FFmpegKit — FlutterBluePlus, FlutterNativeSplash, FlutterVlcPlayer,
IntegrationTest, PathProvider, PermissionHandler, SharedPreferences, Sqlite3, VideoPlayer — are all
unregistered.

## What Didn't Work

**Directly editing `GeneratedPluginRegistrant.java`** to use `catch (Throwable e)`: Flutter regenerates
this file on every `flutter run` / `flutter pub get`, reverting the change immediately.

**Wrapping `DevConfig.load()` in try-catch** (Dart-side fix): helped the app load past the splash
screen but plugin registration was still incomplete; data seeding still failed because
shared_preferences and sqlite3 channels were unregistered.

**Downgrading `path_provider_android` to 2.2.22 alone**: fixed the SIGSEGV but plugin registration
remained broken for all 9 downstream plugins.

**Adding `packaging { jniLibs { pickFirsts += "**/*.so" } }`**: was already present and addresses a
separate `libc++_shared.so` conflict; unrelated to the `_ZTINSt6__ndk117bad_function_callE` symbol
resolution failure.

## Solution

Three-part fix applied together.

**Fix 1 (core): Gradle patch task in `android/app/build.gradle.kts`**

Registers a task that rewrites `GeneratedPluginRegistrant.java` before every Java compilation,
replacing `catch (Exception e)` with `catch (Throwable e)`. Runs after Flutter regenerates the file
but before the compiler reads it — survives `flutter run` and `flutter pub get`.

```kotlin
val patchGeneratedPluginRegistrant by tasks.registering {
    val generatedFile = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
    doLast {
        if (generatedFile.exists()) {
            val original = generatedFile.readText()
            val patched = original.replace("} catch (Exception e) {", "} catch (Throwable e) {")
            if (patched != original) {
                generatedFile.writeText(patched)
                logger.lifecycle("Patched GeneratedPluginRegistrant.java: catch (Throwable)")
            }
        }
    }
}

tasks.configureEach {
    if (name.startsWith("compile") && name.endsWith("JavaWithJavac")) {
        dependsOn(patchGeneratedPluginRegistrant)
    }
}
```

After adding this task, run `flutter clean` once. Previously compiled `.class` files still contain the
old `catch (Exception e)` bytecode. A clean build forces recompilation against the patched source;
subsequent incremental builds work without cleaning.

**Fix 2: Pin `path_provider_android` to 2.2.22 in `pubspec.yaml`**

`path_provider_android` 2.3.x switched from pigeon method channels to direct JNI (`libdartjni.so`).
On Android 16 x86_64, JNI is uninitialized when `path_provider` is first called during startup
(because registration was aborted). 2.2.22 uses method channels — the failure degrades to a catchable
`PlatformException` instead of a fatal SIGSEGV.

```yaml
dependency_overrides:
  path_provider_android: 2.2.22
```

**Fix 3 (defense in depth): try-catch around `DevConfig.load()` in `lib/main.dart`**

If any channel-error reaches Dart during startup, fall back to safe defaults rather than freezing
before `runApp()`.

```dart
DevConfig devConfig;
try {
  devConfig = await DevConfig.load();
} catch (e) {
  debugPrint('DevConfig.load failed, using defaults: $e');
  devConfig = DevConfig.defaults;
}
```

## Why This Works

**`catch (Throwable e)` isolates each plugin registration.** `Throwable` is the common supertype of
both `Exception` (normal errors) and `Error` (JVM/native errors including `UnsatisfiedLinkError` and
`OutOfMemoryError`). With `Throwable`, FFmpegKit's registration failure is caught and logged per-entry;
the loop continues and all 9 downstream plugins register normally.

**The Gradle task approach survives regeneration** because it hooks into `compile*JavaWithJavac` tasks —
which run after `flutter pub get` writes the generated file but before the compiler reads it. The patch
is idempotent (no-op if already applied) and emits a `lifecycle` log line confirming it ran.

**Pinning `path_provider_android: 2.2.22` avoids the JNI crash path entirely.** The 2.2.22
method-channel implementation degrades gracefully to a `PlatformException` when unregistered, rather
than crashing the process via an uninitialized JNI `FindClass` call.

**The Dart try-catch** is defense in depth only — it does not fix plugin registration, but ensures that
if any channel-error reaches startup code the app reaches `runApp()` with safe defaults.

## Prevention

- **Check ADB logcat first** whenever any Flutter plugin appears broken from the Dart side. The
  registration abort is invisible from Dart — only logcat reveals which plugin threw `Error` and which
  subsequent plugins were skipped:
  ```bash
  adb logcat | grep -E "GeneratedPluginRegistrant|FFmpegKit|UnsatisfiedLinkError"
  ```

- **Test native plugins on Android 16 (API 36, x86_64) specifically.** Symbols present through API 35
  may be removed in API 36. FFmpeg-based and other native audio/video plugins are high-risk because
  they bundle their own `.so` files compiled against specific NDK/libc++ versions.

- **Any plugin that throws `java.lang.Error` (not `Exception`) will abort all subsequent plugin
  registrations** until Flutter generates `catch (Throwable)` by default. Track the upstream Flutter
  issue; remove the Gradle patch task and the `path_provider_android` override once: (a)
  `ffmpeg_kit_flutter_new_full` ships a compatible `.so` for Android 16, or (b) Flutter's
  `GeneratedPluginRegistrant` template is updated to use `catch (Throwable e)`.

- **Verify the generated registration order in `GeneratedPluginRegistrant.java`.** A plugin that can
  throw `Error` early in the list silently breaks every plugin that follows it.

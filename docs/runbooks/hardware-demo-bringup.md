# Hardware-demo bring-up runbook (M0 → M5)

Repeatable on-device steps to bring the SST Cam companion app up against **real
firmware** (Jetson Orin Nano) over BLE + WiFi Direct, plus the known footguns.
The whole app is contract-first and mock-tested; this runbook covers the paths
that only execute on hardware.

Build order across repos: **proto → firmware → app**. Bump `sst-cam-app/proto` to
the raw-capture contract commit and run `just gen-proto` before building.

---

## M0 — Prod build + pairing

1. **Build a RELEASE prod APK** — never a debug/profile build (debug leaks BLE
   payloads, incl. any stream key, to logcat):
   ```bash
   just build-android-prod      # release, real backend (single entry, APP_ENV=prod)
   ```
2. **Confirm the Android-16 ffmpeg-kit fix is intact.** `ffmpeg_kit_flutter_new`
   throws `UnsatisfiedLinkError` (a `java.lang.Error`) on API 36, which aborts
   plugin registration and silently kills FlutterBluePlus + sqlite3 — it looks
   like "BLE is broken" but isn't. The Gradle `patchGeneratedPluginRegistrant`
   task rewrites the registrant to `catch (Throwable)` on every build (it
   `dependsOn` the compile task; `flutter clean` regenerates the file, so
   checking the current file alone is not enough). First triage if plugins look
   dead:
   ```bash
   adb logcat | grep GeneratedPluginRegistrant
   ```
   `path_provider_android` is pinned to `2.2.22` for the same reason.
3. **Pair + telemetry.** Launch, scan, connect to `sst-cam-NNNN`. Expect device
   info + 1 Hz telemetry. A protocol-version skew surfaces as
   `BleProtocolVersionException` (the app disables unsupported features) — check
   `kAppProtocolVersion` (currently 1) vs the device's `protocol_version` first.
4. **Negotiated MTU.** The app requests a 512 ATT MTU but derives its chunk
   budget from the **actual** negotiated MTU (`chunkBudgetForMtu`). If multi-
   chunk commands fail, confirm the negotiated MTU; the host test
   `test/ble/chunk_mtu_test.dart` covers reassembly at MTU 185/247/512.

## M1 — Live RTSP preview

5. WiFi Direct connects on BLE connect (`WifiHandoffController`). Tap **Preview**
   on the main page. `LivePreviewView` plays
   `rtsp://<group-owner-ip>:<preview-port>/preview` via VLC.
   - **Confirm the firmware's actual mount/port/transport** match the descriptor
     (`/preview`, `rtpOverRtsp`); adjust `WifiServiceImpl.previewDescriptor` if
     they differ.
   - Reconnect repeatedly — `disconnectGroup` sends `StopWifiDirectCommand`, so a
     second connect must not hit a stale-group failure.

## M2 — Record + download

6. Start/stop a recording from the match session screen. After stop, download
   from the library: the app mints a token over BLE then streams the file to disk
   over WiFi (range + `Authorization: Bearer`, progress, cancel). Play it back.
   - Expired/invalid token → clear error. Cancel mid-download cleans up.

## M3 — Raw dual-camera capture

7. On the main page, tap **Record RAW (training)** (distinct red affordance). The
   app mints a `captureGroupId` and sends `RawCaptureControlCommand(start)`.
8. Tap **Stop RAW capture**. The app enumerates the pair (`ListRecordings`
   filtered by `isRaw` + `captureGroupId`), auto-downloads BOTH files, and
   persists them to the `raw_recordings` table. Both must land or the entry is
   marked incomplete (not saved as a single file). A disconnect mid-capture shows
   the "Raw capture interrupted" banner.

## M4 — Overlay parity

9. Author overlay state (scoreboard/banner) and start a match; the app pushes the
   layout + live `ScoreUpdate`/`BannerEvent`. Compare the recorded/streamed output
   against the in-app preview: uniform `min(sx,sy)` scale, Inter Regular+Bold both
   sides, opacity on every shape, `{{param}}` substitution. They must match within
   tolerance.

## M5 — Platform broadcast (YouTube RTMP)

10. Configure the YouTube RTMP target (Settings → Streaming). The URL/key flow to
    firmware via `PushSessionConfig` (proto3 optional — null is left unset, never
    encoded as `""`). Toggle the live broadcast with `StreamingControlCommand`.
    Confirm the platform shows the live overlaid cam-0 stream.

---

## Post-demo security steps (REQUIRED)

- **Revoke / regenerate the YouTube stream key.** It transits BLE as cleartext
  and sits unencrypted in Drift — treat it as **single-use**. Revoke immediately
  after the demo.
- **Remove the persistent Android WiFi Direct P2P group** to prevent credential
  reuse.
- **Confirm no token/key logging.** The auth token and stream key must never
  appear in any `toString()`, log line, or crash payload. (Audited: no
  `streamKey` in any toString/log; release build only.)

## "BLE looks dead" triage order

1. `adb logcat | grep GeneratedPluginRegistrant` — ffmpeg-kit registration abort.
2. Confirm release (not debug) build + `path_provider_android: 2.2.22`.
3. Check `protocol_version` skew (`BleProtocolVersionException`).
4. Check the negotiated MTU vs chunk sizing.

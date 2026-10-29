// U1 — hero card camera-state mapping (R3).
//
// cameraHeroState() replaces the old connection-only green "LIVE" dot with a
// real state derived from telemetry flags. Precedence (AE1/AE2):
//   Streaming > Recording > Preview > Standby > Disconnected.
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/models/telemetry.dart';
import 'package:sst_cam_app/core/theme/tokens.dart';
import 'package:sst_cam_app/features/camera/main_page.dart';

DeviceTelemetry _telemetry({bool recording = false, bool streaming = false}) =>
    DeviceTelemetry(
      storageFreeBytes: 1000,
      storageTotalBytes: 2000,
      wifiState: WifiState.connected,
      internetReachable: false,
      tempCelsius: 40,
      ramUsedPct: 10,
      cpuUsedPct: 10,
      uptimeSeconds: 100,
      isRecording: recording,
      isStreaming: streaming,
    );

void main() {
  test('AE1: connected + idle telemetry → Standby (not LIVE)', () {
    final (label, color) = cameraHeroState(
      connected: true,
      previewOn: false,
      telemetry: _telemetry(),
    );
    expect(label, 'Standby');
    expect(color, T.warn);
  });

  test('AE2: recording + streaming → Streaming (precedence)', () {
    final (label, color) = cameraHeroState(
      connected: true,
      previewOn: true,
      telemetry: _telemetry(recording: true, streaming: true),
    );
    expect(label, 'Streaming');
    expect(color, T.ok);
  });

  test('recording only → Recording', () {
    final (label, color) = cameraHeroState(
      connected: true,
      previewOn: false,
      telemetry: _telemetry(recording: true),
    );
    expect(label, 'Recording');
    expect(color, T.danger);
  });

  test('preview on, not recording/streaming → Preview', () {
    final (label, color) = cameraHeroState(
      connected: true,
      previewOn: true,
      telemetry: _telemetry(),
    );
    expect(label, 'Preview');
    expect(color, T.accent);
  });

  test('not connected → Disconnected regardless of stale flags', () {
    final (label, color) = cameraHeroState(
      connected: false,
      previewOn: true,
      // Inconsistent: telemetry claims recording but connection is gone.
      telemetry: _telemetry(recording: true, streaming: true),
    );
    expect(label, 'Disconnected');
    expect(color, T.ink3);
  });

  test('connected with null telemetry → Standby', () {
    final (label, _) = cameraHeroState(
      connected: true,
      previewOn: false,
      telemetry: null,
    );
    expect(label, 'Standby');
  });
}

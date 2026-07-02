// U12 — the mock (a second contract consumer) observes the record/stream
// quality carried on control commands, so app tests prove the wire shape
// (mock-must-mirror-real-firmware-contract).

import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/video_mode.dart';
import 'package:sst_cam_app/mock/emulator/mock_ble_service.dart';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 1,
);

void main() {
  test('mock advertises the firmware-mirrored supported modes', () async {
    final mock = _newMock();
    final info = await mock.getDeviceInfo('dev');
    expect(
      info.supportedModes,
      containsAll(const [
        VideoMode(width: 1920, height: 1080, fps: 30),
        VideoMode(width: 1280, height: 720, fps: 60),
      ]),
    );
    // Advertises a real ladder, not 4K.
    expect(info.supportedModes.any((m) => m.height >= 2160), isFalse);
  });

  test('mock captures independent record + stream quality on start', () async {
    final mock = _newMock();

    await mock.sendCommand<void>(
      'dev',
      RecordingControlCommand(
        action: RecordingControlAction.start,
        quality: const VideoMode(width: 1920, height: 1080, fps: 60),
      ),
    );
    await mock.sendCommand<void>(
      'dev',
      StreamingControlCommand(
        action: StreamingControlAction.start,
        rtmpUrl: 'rtmp://ingest/live/k',
        quality: const VideoMode(width: 1280, height: 720, fps: 30),
      ),
    );

    expect(
      mock.lastRecordingQuality,
      const VideoMode(width: 1920, height: 1080, fps: 60),
    );
    expect(
      mock.lastStreamingQuality,
      const VideoMode(width: 1280, height: 720, fps: 30),
    );
  });

  test('a start with no quality leaves the mock observer null', () async {
    final mock = _newMock();
    await mock.sendCommand<void>(
      'dev',
      RecordingControlCommand(action: RecordingControlAction.start),
    );
    expect(mock.lastRecordingQuality, isNull);
  });
}

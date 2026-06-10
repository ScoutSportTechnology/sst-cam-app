import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/ble/ble_service.dart';
import 'package:sst_cam_app/core/db/app_database.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/recording.dart';
import 'package:sst_cam_app/core/state/db_providers.dart';
import 'package:sst_cam_app/core/wifi/wifi_providers.dart';
import 'package:sst_cam_app/core/wifi/wifi_service.dart';
import 'package:sst_cam_app/core/models/wifi.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart';
import 'package:sst_cam_app/features/camera/raw_capture_state.dart';

class _FakeBle implements BleService {
  final List<BleCommand> sent = [];
  List<RecordingMetadata> recordings = const [];

  @override
  Future<BleCommandResponse<T>> sendCommand<T>(String deviceId, BleCommand command) async {
    sent.add(command);
    if (command is ListRecordingsCommand) {
      return BleCommandResponse.ok(recordings as T?);
    }
    return BleCommandResponse.ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWifi implements WifiService {
  final List<String> downloaded = [];

  /// Terminal status the simulated download reaches. Defaults to a successful
  /// transfer; set to failed/cancelled to exercise the partial-download path.
  DownloadStatus terminalStatus = DownloadStatus.completed;

  @override
  Future<VideoDownloadHandle> downloadRecording(String deviceId, String uuid) async {
    downloaded.add(uuid);
    return VideoDownloadHandle(
      downloadId: 'dl-$uuid',
      recordingId: uuid,
      savePath: '/videos/$uuid.nv12',
      // Emit a single terminal progress event, mirroring the real handle whose
      // stream runs until the transfer reaches a terminal state then closes.
      progress: Stream.value(VideoDownloadProgress(
        downloadId: 'dl-$uuid',
        recordingId: uuid,
        status: terminalStatus,
        bytesReceived: 100,
        bytesTotal: 100,
        kbps: 0,
      )),
      cancel: () async {},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RecordingMetadata _raw(String id, String group, int cam) => RecordingMetadata(
      id: id,
      durationSeconds: 0,
      sizeBytes: 100,
      startedAt: DateTime(2026, 6, 10),
      sport: '',
      teams: '',
      isRaw: true,
      cameraIndex: cam,
      captureGroupId: group,
    );

void main() {
  late AppDatabase db;
  late _FakeBle ble;
  late _FakeWifi wifi;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    ble = _FakeBle();
    wifi = _FakeWifi();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      bleServiceProvider.overrideWithValue(ble),
      wifiServiceProvider.overrideWithValue(wifi),
      activeCameraIdProvider.overrideWith((ref) => 'dev-1'),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  RawCaptureController ctrl() => container.read(rawCaptureProvider.notifier);
  RawCaptureState read() => container.read(rawCaptureProvider);

  test('start mints a group id, sends START, goes to capturing', () async {
    await ctrl().start();

    expect(read().phase, RawCapturePhase.capturing);
    expect(read().captureGroupId, isNotNull);
    final start = ble.sent.whereType<RawCaptureControlCommand>().single;
    expect(start.action, RecordingControlAction.start);
    expect(start.captureGroupId, read().captureGroupId);
  });

  test('start is ignored with no active camera', () async {
    container.read(activeCameraIdProvider.notifier).state = null;
    await ctrl().start();
    expect(read().phase, RawCapturePhase.idle);
    expect(ble.sent, isEmpty);
  });

  test('stop downloads + persists both files and completes the group', () async {
    await ctrl().start();
    final group = read().captureGroupId!;
    ble.recordings = [
      _raw('raw__a__cam0', group, 0),
      _raw('raw__a__cam1', group, 1),
      RecordingMetadata(
        id: 'final-x',
        durationSeconds: 1,
        sizeBytes: 1,
        startedAt: DateTime(2026, 6, 10),
        sport: '',
        teams: '',
      ),
    ];

    await ctrl().stop();

    expect(read().phase, RawCapturePhase.idle);
    expect(wifi.downloaded, ['raw__a__cam0', 'raw__a__cam1']);
    final rows = await db.rawRecordingsDao.getPair(group);
    expect(rows, hasLength(2));
    expect(rows.every((r) => r.isComplete), isTrue);
    expect(rows.map((r) => r.cameraIndex).toSet(), {0, 1});
  });

  test('stop does NOT complete the group when a download fails', () async {
    wifi.terminalStatus = DownloadStatus.failed;
    await ctrl().start();
    final group = read().captureGroupId!;
    ble.recordings = [
      _raw('raw__a__cam0', group, 0),
      _raw('raw__a__cam1', group, 1),
    ];

    await ctrl().stop();

    // Both files listed, but neither finished downloading → not complete.
    expect(read().phase, RawCapturePhase.error);
    expect(read().message, contains('incomplete'));
    final rows = await db.rawRecordingsDao.getPair(group);
    expect(rows.every((r) => !r.isComplete), isTrue);
    // A failed transfer must not record a playable local path.
    expect(rows.every((r) => r.localPath == null), isTrue);
  });

  test('stop with only one file surfaces an incomplete error', () async {
    await ctrl().start();
    final group = read().captureGroupId!;
    ble.recordings = [_raw('raw__a__cam0', group, 0)]; // missing cam1

    await ctrl().stop();

    expect(read().phase, RawCapturePhase.error);
    expect(read().message, contains('incomplete'));
  });

  test('onInterrupted while capturing resets with a banner', () async {
    await ctrl().start();
    ctrl().onInterrupted();
    expect(read().phase, RawCapturePhase.error);
    expect(read().message, contains('interrupted'));
  });
}

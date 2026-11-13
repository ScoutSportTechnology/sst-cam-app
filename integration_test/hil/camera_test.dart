import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sst_cam_app/app.dart';
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/ble/ble_service.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/core/models/network_config.dart';
import 'package:sst_cam_app/core/models/recording.dart';
import 'package:sst_cam_app/core/models/overlay_layout.dart';
import 'package:sst_cam_app/core/models/session_snapshot.dart';
import 'package:sst_cam_app/core/models/telemetry.dart';
import 'package:sst_cam_app/core/models/wifi.dart';
import 'package:sst_cam_app/core/wifi/wifi_handoff.dart';
import 'package:sst_cam_app/core/wifi/wifi_providers.dart';
import 'package:sst_cam_app/core/wifi/wifi_service_impl.dart';
import 'package:sst_cam_app/features/discovery/discovery_page.dart';
import 'package:sst_cam_app/core/widgets/live_preview_view.dart';
import 'package:sst_cam_app/core/widgets/wf_button.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

const _host = '10.10.1.30';
const _rtmp = String.fromEnvironment('HIL_RTMP_URL');
const _offline = bool.fromEnvironment('HIL_OFFLINE');

Future<T> _step<T>(
  String name,
  Duration limit,
  Future<T> Function() action,
) async {
  // ignore: avoid_print
  print('HIL_BEGIN $name');
  try {
    final value = await action().timeout(limit);
    // ignore: avoid_print
    print('HIL_PASS $name');
    return value;
  } catch (error) {
    // ignore: avoid_print
    print('HIL_FAIL $name: $error');
    rethrow;
  }
}

Future<SessionSnapshot> _snapshot(BleService ble, String id) async {
  final response = await ble.sendCommand<SessionSnapshot>(
    id,
    GetSessionSnapshotCommand(),
  );
  expect(
    response.isOk,
    isTrue,
    reason: 'GetSessionSnapshot rejected: ${response.errorMessage}',
  );
  expect(
    response.payload,
    isNotNull,
    reason: 'GetSessionSnapshot omitted payload',
  );
  return response.payload!;
}

Future<void> _until(
  WidgetTester tester,
  String description,
  Duration limit,
  bool Function() ready,
) async {
  final deadline = DateTime.now().add(limit);
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $description after ${limit.inSeconds}s');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

class _LanWifiService extends WifiServiceImpl {
  _LanWifiService({required super.ble}) : _ble = ble;

  final BleService _ble;
  WifiDirectGroup? _group;
  String? _credential;
  final _states = StreamController<WifiDirectState>.broadcast();

  @override
  Future<WifiDirectGroup> connectGroup(String deviceId) async {
    final response = await _ble.sendCommand<WifiDirectGroup>(
      deviceId,
      StartWifiDirectCommand(),
    );
    if (!response.isOk || response.payload == null) {
      throw StateError('StartWifiDirect failed: ${response.errorMessage}');
    }
    final config = await _ble.getNetworkConfig(deviceId);
    if (config.lanPath != LanPath.ethernet ||
        config.lanEndpoint != _host ||
        config.lanCredential.isEmpty) {
      throw StateError(
        'Ethernet LAN not committed or credential missing: ${config.lanPath} ${config.lanEndpoint}',
      );
    }
    _credential = config.lanCredential;
    final ok = await RtspDescribeProbe().probe(_host, _credential!);
    if (!ok) throw StateError('Authenticated LAN RTSP DESCRIBE failed');
    _group = WifiDirectGroup(
      ssid: response.payload!.ssid,
      psk: response.payload!.psk,
      groupOwnerIp: _host,
      previewPort: response.payload!.previewPort,
      downloadPort: response.payload!.downloadPort,
      role: response.payload!.role,
    );
    _states.add(WifiDirectState.connected);
    return _group!;
  }

  @override
  Future<void> disconnectGroup(String deviceId) async {
    _group = null;
    _states.add(WifiDirectState.idle);
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await super.dispose();
  }

  @override
  WifiDirectGroup? currentGroup(String deviceId) => _group;

  @override
  Stream<WifiDirectState> connectionStateStream(String deviceId) async* {
    yield _group == null ? WifiDirectState.idle : WifiDirectState.connected;
    yield* _states.stream;
  }

  @override
  PreviewStreamDescriptor? previewDescriptor(String deviceId) {
    final group = _group;
    final credential = _credential;
    if (group == null || credential == null) return null;
    final user = Uri.encodeComponent(credential.split(':').first);
    final password = Uri.encodeComponent(
      credential.substring(credential.indexOf(':') + 1),
    );
    return PreviewStreamDescriptor(
      url: 'rtsp://$user:$password@$_host:${group.previewPort}/preview',
      codec: PreviewCodec.rtspH264,
      width: 1280,
      height: 720,
      fps: 30,
      bitrateKbps: 1500,
    );
  }

  @override
  Future<bool> isCameraReachable(String deviceId) async {
    final group = _group;
    if (group == null) return false;
    try {
      final socket = await Socket.connect(
        _host,
        group.downloadPort,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    }
  }

  @override
  Future<VideoDownloadHandle> downloadRecording(
    String deviceId,
    String uuid,
  ) async {
    final token = await _ble.requestDownload(deviceId, uuid);
    final url = Uri.parse(token.httpUrl).replace(host: _host).toString();
    return startDownload(
      deviceId,
      DownloadToken(
        recordingId: token.recordingId,
        httpUrl: url,
        authToken: token.authToken,
        expiresAt: token.expiresAt,
      ),
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real camera HIL: BLE, LAN, record, preview, download, RTMP and shutdown',
    (tester) async {
      final container = ProviderContainer();
      final ble = container.read(bleServiceProvider);
      final wifi = _LanWifiService(ble: ble);
      final app = ProviderContainer(
        overrides: [
          bleServiceProvider.overrideWithValue(ble),
          wifiServiceProvider.overrideWithValue(wifi),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        app.dispose();
        container.dispose();
        await wifi.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(container: app, child: const SstCamApp()),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.text('Connect camera'));
      await tester.tap(find.text('Connect camera'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(DiscoveryPage), findsOneWidget);

      final device = await _step('scan', const Duration(seconds: 25), () async {
        await _until(
          tester,
          'sst-cam-* advertisement',
          const Duration(seconds: 22),
          () => (app.read(discoveredDevicesProvider).valueOrNull ?? []).any(
            (d) => d.name.startsWith('sst-cam-'),
          ),
        );
        final found = (app.read(discoveredDevicesProvider).valueOrNull ?? [])
            .firstWhere((d) => d.name.startsWith('sst-cam-'));
        expect(find.text(found.name), findsOneWidget);
        return found;
      });
      if (_offline) {
        fail('HIL_OFFLINE: scan unexpectedly found ${device.name}');
      }

      await _step(
        'connect_protocol_time_snapshot',
        const Duration(seconds: 80),
        () async {
          await tester.tap(find.widgetWithText(WfButton, 'Connect').first);
          await _until(
            tester,
            'connected handshake',
            const Duration(seconds: 75),
            () =>
                app.read(connectionStateProvider(device.id)).valueOrNull ==
                CameraConnectionState.connected,
          );
          final info = await ble.getDeviceInfo(device.id);
          expect(
            info?.protocolVersion,
            kAppProtocolVersion,
            reason: 'protocol gate',
          );
          final snap = await _snapshot(ble, device.id);
          expect(snap.components, isNotNull, reason: 'component health absent');
          expect(snap.camera0Health, CameraHealth.ok);
          expect(snap.camera1Health, CameraHealth.ok);
          expect(snap.components!.gpu, ComponentHealth.ok);
          expect(snap.components!.ethernet, ComponentHealth.ok);
          expect(snap.components!.bluetooth, ComponentHealth.ok);
          expect(snap.components!.storage, ComponentHealth.ok);
          expect(snap.isRecording, isFalse);
          expect(snap.isFinalizing, isFalse);
        },
      );

      final id = 'p14a-${DateTime.now().millisecondsSinceEpoch}';
      await _step('lan_preview', const Duration(seconds: 50), () async {
        final group = await wifi.connectGroup(device.id);
        expect(group.groupOwnerIp, _host);
        expect(wifi.previewDescriptor(device.id)?.url, contains('$_host:'));
        await tester.pump(const Duration(milliseconds: 400));
        final preview = find.widgetWithText(WfButton, 'Preview');
        await tester.ensureVisible(preview.first);
        await tester.tap(preview.first);
        await _until(
          tester,
          'VLC preview playback',
          const Duration(seconds: 25),
          () {
            final player = find.byType(VlcPlayer);
            return player.evaluate().isNotEmpty &&
                tester
                    .widget<VlcPlayer>(player.first)
                    .controller
                    .value
                    .isPlaying;
          },
        );
        expect(find.byType(LivePreviewView), findsWidgets);
      });

      await _step('configure_record', const Duration(seconds: 90), () async {
        await ble.pushSessionConfig(
          device.id,
          PushSessionConfig(
            matchUuid: id,
            userUuid: 'p14a',
            sport: 'soccer',
            numPeriods: 2,
            periodLengthSeconds: 60,
            videoOutputPath: '/var/lib/sst/cam/videos/p14a/$id/',
            thumbnailOutputPath: '/var/lib/sst/cam/thumbnails/p14a/$id/',
          ),
        );
        await ble.pushOverlayLayout(
          device.id,
          defaultScoreboardLayout(homeName: 'HOME', awayName: 'AWAY'),
        );
        final start = await ble.sendCommand<void>(
          device.id,
          RecordingControlCommand(action: RecordingControlAction.start),
        );
        expect(
          start.isOk,
          isTrue,
          reason: 'record start: ${start.errorMessage}',
        );
        expect((await _snapshot(ble, device.id)).isRecording, isTrue);
        await Future<void>.delayed(const Duration(seconds: 10));
        final stop = await ble.sendCommand<void>(
          device.id,
          RecordingControlCommand(action: RecordingControlAction.stop),
        );
        expect(
          stop.isOk,
          isTrue,
          reason: 'async stop ACK: ${stop.errorMessage}',
        );
      });

      await _step(
        'finalization_download',
        const Duration(seconds: 100),
        () async {
          var sawFinalizing = false;
          SessionSnapshot? completed;
          final deadline = DateTime.now().add(const Duration(seconds: 75));
          while (DateTime.now().isBefore(deadline)) {
            final snap = await _snapshot(ble, device.id);
            sawFinalizing |= snap.isFinalizing == true;
            if (sawFinalizing &&
                snap.isFinalizing == false &&
                snap.lastSession != null) {
              completed = snap;
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          expect(
            sawFinalizing,
            isTrue,
            reason: 'no async is_finalizing=true observed',
          );
          expect(
            completed?.lastSession?.fileValid,
            isTrue,
            reason: 'finalized file invalid/missing',
          );
          expect(completed?.lastSession?.matchUuid, id);
          final handle = await wifi.downloadRecording(device.id, id);
          final progress = await handle.progress
              .firstWhere((p) => p.isTerminal)
              .timeout(const Duration(seconds: 20));
          expect(
            progress.status,
            DownloadStatus.completed,
            reason: progress.errorMessage,
          );
          expect(progress.bytesReceived, greaterThan(1024));
          expect(await File(handle.savePath).length(), progress.bytesReceived);
        },
      );

      if (_rtmp.isEmpty) {
        fail('HIL_RTMP_URL missing; streaming cannot be verified');
      }
      await _step('rtmp_shutdown_ready', const Duration(seconds: 80), () async {
        await wifi.connectGroup(device.id);
        final config = PushSessionConfig(
          matchUuid: 'p14a-shutdown-${DateTime.now().millisecondsSinceEpoch}',
          userUuid: 'p14a',
          sport: 'soccer',
          numPeriods: 2,
          periodLengthSeconds: 60,
          videoOutputPath: '/var/lib/sst/cam/videos/p14a/shutdown/',
          thumbnailOutputPath: '/var/lib/sst/cam/thumbnails/p14a/shutdown/',
          rtmpUrl: _rtmp,
        );
        await ble.pushSessionConfig(device.id, config);
        await ble.pushOverlayLayout(
          device.id,
          defaultScoreboardLayout(homeName: 'HOME', awayName: 'AWAY'),
        );
        final start = await ble.sendCommand<void>(
          device.id,
          RecordingControlCommand(action: RecordingControlAction.start),
        );
        expect(start.isOk, isTrue, reason: start.errorMessage);
        final stream = await ble.sendCommand<void>(
          device.id,
          StreamingControlCommand(
            action: StreamingControlAction.start,
            rtmpUrl: _rtmp,
          ),
        );
        expect(stream.isOk, isTrue, reason: stream.errorMessage);
        expect((await _snapshot(ble, device.id)).isStreaming, isTrue);
        // ignore: avoid_print
        print('HIL_SHUTDOWN_READY');
        await _until(
          tester,
          'firmware shutdown disconnect',
          const Duration(seconds: 35),
          () =>
              app.read(connectionStateProvider(device.id)).valueOrNull ==
              CameraConnectionState.disconnected,
        );
      });
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

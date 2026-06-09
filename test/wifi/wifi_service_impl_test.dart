// U7 — WifiServiceImpl honors WifiDirectGroupResponse.role.
//
// connectGroup must read the camera-reported role and guard on it: when the
// camera is the WiFi Direct group owner (GO) the phone joins normally; an
// unexpected role surfaces a clear error instead of proceeding on a fixed
// assumption.
//
// The native MethodChannel ('connect'/'disconnect') and the EventChannel
// ('.../state') are mocked so the test exercises the Dart-side role logic
// without a real Android P2P stack. Runs on the Linux test host, where
// Platform.isIOS is false (so the iOS guard does not trip).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_service.dart';
import 'package:sst_cam_app/core/models/command.dart';
import 'package:sst_cam_app/core/models/wifi.dart';
import 'package:sst_cam_app/core/wifi/wifi_service_impl.dart';

/// Minimal fake BleService — only `sendCommand` is exercised by connectGroup.
/// Every other member throws via noSuchMethod (never called here).
class _FakeBle implements BleService {
  _FakeBle(this._group);
  final WifiDirectGroup _group;

  @override
  Future<BleCommandResponse<T>> sendCommand<T>(
    String deviceId,
    BleCommand command,
  ) async {
    if (command is StartWifiDirectCommand) {
      return BleCommandResponse.ok(_group as T?);
    }
    // StopWifiDirectCommand and others — OK with no payload.
    return BleCommandResponse.ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

WifiDirectGroup _group(String role) => WifiDirectGroup(
  ssid: 'cam-ap',
  psk: 'secret123',
  groupOwnerIp: '192.168.49.1',
  previewPort: 8554,
  downloadPort: 8080,
  role: role,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel('com.sst.sstcam/wifi');
  const eventChannelName = 'com.sst.sstcam/wifi/state';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  var connectCalls = 0;

  setUp(() {
    connectCalls = 0;
    messenger.setMockMethodCallHandler(method, (call) async {
      if (call.method == 'connect') connectCalls++;
      return null;
    });
    // EventChannel: respond to the listen handshake so receiveBroadcastStream
    // does not throw a MissingPluginException.
    messenger.setMockMethodCallHandler(
      const MethodChannel(eventChannelName),
      (call) async => null,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(method, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel(eventChannelName),
      null,
    );
  });

  test('happy path — GO role connects normally and joins the group', () async {
    final svc = WifiServiceImpl(ble: _FakeBle(_group('GO')));
    final group = await svc.connectGroup('dev-1');
    expect(group.role, 'GO');
    expect(svc.currentGroup('dev-1'), isNotNull);
    expect(connectCalls, 1);
    await svc.dispose();
  });

  test('group_owner spelling is accepted', () async {
    final svc = WifiServiceImpl(ble: _FakeBle(_group('group_owner')));
    final group = await svc.connectGroup('dev-2');
    expect(group.role, 'group_owner');
    expect(connectCalls, 1);
    await svc.dispose();
  });

  test('empty role tolerated (legacy firmware)', () async {
    final svc = WifiServiceImpl(ble: _FakeBle(_group('')));
    await svc.connectGroup('dev-3');
    expect(connectCalls, 1);
    await svc.dispose();
  });

  test('error path — unexpected client role surfaces a clear error', () async {
    final svc = WifiServiceImpl(ble: _FakeBle(_group('client')));
    await expectLater(
      svc.connectGroup('dev-4'),
      throwsA(
        isA<WifiDirectException>().having(
          (e) => e.message,
          'message',
          allOf(contains('unexpected'), contains('client')),
        ),
      ),
    );
    // The native join must NOT have been attempted on an unexpected role.
    expect(connectCalls, 0);
    expect(svc.currentGroup('dev-4'), isNull);
    await svc.dispose();
  });
}

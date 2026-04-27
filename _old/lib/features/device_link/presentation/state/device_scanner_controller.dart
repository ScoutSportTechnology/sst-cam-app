import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'device_scanner_state.dart';

class DeviceScannerController {
  DeviceScannerController();

  final ValueNotifier<DeviceScannerState> state =
      ValueNotifier<DeviceScannerState>(DeviceScannerState.initial());

  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<bool>? _scanningSub;
  StreamSubscription<List<ScanResult>>? _resultsSub;
  final Map<String, StreamSubscription<BluetoothConnectionState>>
  _connectionSubs = {};

  Future<void> init() async {
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      _set(state.value.copyWith(adapterState: s));
    });

    _scanningSub = FlutterBluePlus.isScanning.listen((s) {
      _set(state.value.copyWith(isScanning: s));
    });

    _resultsSub = FlutterBluePlus.onScanResults.listen((batch) {
      final next = Map<String, ScanResult>.from(state.value.devices);
      for (final r in batch) {
        if (r.advertisementData.connectable) {
          next[r.device.remoteId.str] = r;
        }
      }
      _set(state.value.copyWith(devices: next));
    });

    await _checkPermissions();
    await _seedConnected();
  }

  Future<void> dispose() async {
    await _adapterSub?.cancel();
    await _scanningSub?.cancel();
    await _resultsSub?.cancel();
    for (final sub in _connectionSubs.values) {
      await sub.cancel();
    }
    _connectionSubs.clear();
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final scan = await Permission.bluetoothScan.request();
      final connect = await Permission.bluetoothConnect.request();
      if (!scan.isGranted || !connect.isGranted) {
        await Permission.locationWhenInUse.request();
      }
    }
    await _checkPermissions();
  }

  Future<void> toggleScan() async {
    final st = state.value;
    if (st.isScanning) {
      await _stopScan();
      return;
    }
    if (!st.canScan) {
      final perm = st.permission;
      if (perm == PermissionGateStatus.denied ||
          perm == PermissionGateStatus.permanentlyDenied) {
        _set(st.copyWith(toast: 'Bluetooth permission is required.'));
      } else if (st.adapterState != BluetoothAdapterState.on) {
        _set(st.copyWith(toast: 'Turn on Bluetooth to scan.'));
      }
      return;
    }
    await _startScan();
  }

  Future<void> connectToggle(String remoteId) async {
    final st = state.value;
    if (st.busy.contains(remoteId)) return;

    final nextBusy = Set<String>.from(st.busy)..add(remoteId);
    _set(st.copyWith(busy: nextBusy));

    try {
      final device =
          state.value.devices[remoteId]?.device ??
          await _findKnownDevice(remoteId);
      if (device == null) {
        _set(
          state.value.copyWith(
            busy: Set<String>.from(state.value.busy)..remove(remoteId),
            toast: 'Device not found.',
          ),
        );
        return;
      }

      final current = await device.connectionState.first;

      if (current == BluetoothConnectionState.connected) {
        await device.disconnect();
        final nextConnected = Set<String>.from(state.value.connected)
          ..remove(remoteId);
        _set(state.value.copyWith(connected: nextConnected));
      } else {
        await _stopScan();

        _connectionSubs[remoteId]?.cancel();
        final sub = device.connectionState.listen((s) {
          if (s == BluetoothConnectionState.disconnected) {
            final now = state.value;
            final nc = Set<String>.from(now.connected)..remove(remoteId);
            _set(now.copyWith(connected: nc));
          }
        });
        _connectionSubs[remoteId] = sub;
        device.cancelWhenDisconnected(sub, delayed: true, next: true);

        await device.connect(autoConnect: false);

        final nextConnected = Set<String>.from(state.value.connected)
          ..add(remoteId);
        _set(state.value.copyWith(connected: nextConnected));
      }
    } catch (e) {
      _set(state.value.copyWith(toast: 'Connection error: $e'));
    } finally {
      final now = state.value;
      final nb = Set<String>.from(now.busy)..remove(remoteId);
      _set(now.copyWith(busy: nb));
    }
  }

  void updateQuery(String text) {
    _set(state.value.copyWith(query: text));
  }

  Future<void> _startScan() async {
    final cleared = state.value.copyWith(devices: {});
    _set(cleared);
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (e) {
      _set(state.value.copyWith(toast: 'Start scan failed: $e'));
    }
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  Future<void> _checkPermissions() async {
    PermissionGateStatus status;
    if (Platform.isAndroid) {
      final s = await Permission.bluetoothScan.status;
      final c = await Permission.bluetoothConnect.status;
      final l = await Permission.locationWhenInUse.status;

      final granted = (s.isGranted && c.isGranted) || l.isGranted;
      final permDenied =
          s.isPermanentlyDenied ||
          c.isPermanentlyDenied ||
          l.isPermanentlyDenied;

      if (granted) {
        status = PermissionGateStatus.granted;
      } else if (permDenied) {
        status = PermissionGateStatus.permanentlyDenied;
      } else {
        status = PermissionGateStatus.denied;
      }
    } else {
      status = PermissionGateStatus.granted;
    }
    _set(state.value.copyWith(permission: status));
  }

  Future<void> _seedConnected() async {
    try {
      final List<BluetoothDevice> list = FlutterBluePlus.connectedDevices;
      final ids = list.map((d) => d.remoteId.str).toSet();
      _set(state.value.copyWith(connected: ids));
      for (final d in list) {
        final id = d.remoteId.str;
        _connectionSubs[id]?.cancel();
        final sub = d.connectionState.listen((s) {
          if (s == BluetoothConnectionState.disconnected) {
            final now = state.value;
            final nc = Set<String>.from(now.connected)..remove(id);
            _set(now.copyWith(connected: nc));
          }
        });
        _connectionSubs[id] = sub;
        d.cancelWhenDisconnected(sub, delayed: true, next: true);
      }
    } catch (_) {}
  }

  Future<BluetoothDevice?> _findKnownDevice(String remoteId) async {
    try {
      final list = FlutterBluePlus.connectedDevices;
      for (final d in list) {
        if (d.remoteId.str == remoteId) return d;
      }
    } catch (_) {}
    return null;
  }

  void _set(DeviceScannerState next) {
    state.value = next;
  }
}

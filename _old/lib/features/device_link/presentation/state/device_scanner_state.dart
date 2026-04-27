import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum PermissionGateStatus { unknown, granted, denied, permanentlyDenied }

class DeviceScannerState {
  const DeviceScannerState({
    required this.adapterState,
    required this.permission,
    required this.isScanning,
    required this.devices,
    required this.connected,
    required this.busy,
    required this.saved,
    required this.query,
    this.toast,
  });

  final BluetoothAdapterState adapterState;
  final PermissionGateStatus permission;
  final bool isScanning;
  final Map<String, ScanResult> devices;
  final Set<String> connected;
  final Set<String> busy;
  final Set<String> saved;
  final String query;
  final String? toast;

  bool get canScan =>
      permission == PermissionGateStatus.granted &&
      adapterState == BluetoothAdapterState.on;

  List<ScanResult> get deviceList {
    final list = devices.values.toList();
    list.sort((a, b) => b.rssi.compareTo(a.rssi));
    return list;
  }

  DeviceScannerState copyWith({
    BluetoothAdapterState? adapterState,
    PermissionGateStatus? permission,
    bool? isScanning,
    Map<String, ScanResult>? devices,
    Set<String>? connected,
    Set<String>? busy,
    Set<String>? saved,
    String? query,
    Object? toast = _noChange,
  }) {
    final String? nextToast = identical(toast, _noChange)
        ? this.toast
        : toast as String?;
    return DeviceScannerState(
      adapterState: adapterState ?? this.adapterState,
      permission: permission ?? this.permission,
      isScanning: isScanning ?? this.isScanning,
      devices: devices ?? this.devices,
      connected: connected ?? this.connected,
      busy: busy ?? this.busy,
      saved: saved ?? this.saved,
      query: query ?? this.query,
      toast: nextToast,
    );
  }

  factory DeviceScannerState.initial() => const DeviceScannerState(
    adapterState: BluetoothAdapterState.unknown,
    permission: PermissionGateStatus.unknown,
    isScanning: false,
    devices: {},
    connected: {},
    busy: {},
    saved: {},
    query: '',
    toast: null,
  );
}

const Object _noChange = Object();

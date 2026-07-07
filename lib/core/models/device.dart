import 'dart:typed_data';

class SstDevice {
  const SstDevice({
    required this.id,
    required this.name,
    required this.firmwareVersion,
    required this.model,
    required this.protocolVersion,
    this.batteryPercent,
    this.rssi,
  });

  final String id;
  final String name;
  final String firmwareVersion;
  final String model;
  final int protocolVersion;

  /// Battery level 0–100, or null when not yet reported.
  final int? batteryPercent;

  /// RSSI in dBm (negative), or null when not available.
  final int? rssi;

  @override
  bool operator ==(Object other) => other is SstDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum CameraConnectionState {
  disconnected,
  connecting,

  /// BLE link is up and the protocol gate passed, but the connect handshake
  /// (time push → session snapshot → rehydrate → reconcile) has not finished.
  /// Session-affecting UI must gate on [connected] only — never treat
  /// [reconciling] as usable (a Record tap here would race the snapshot).
  reconciling,
  connected,
  disconnecting,
}

class ThumbnailResult {
  const ThumbnailResult({required this.jpegBytes, required this.capturedAt});
  final Uint8List jpegBytes;
  final DateTime capturedAt;
}

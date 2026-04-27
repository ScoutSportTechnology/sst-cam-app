import 'dart:typed_data';

class ScoutDevice {
  const ScoutDevice({
    required this.id,
    required this.name,
    required this.firmwareVersion,
    required this.model,
    required this.protocolVersion,
  });

  final String id;
  final String name;
  final String firmwareVersion;
  final String model;
  final int protocolVersion;

  @override
  bool operator ==(Object other) =>
      other is ScoutDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum CameraConnectionState { disconnected, connecting, connected, disconnecting }

class ThumbnailResult {
  const ThumbnailResult({required this.jpegBytes, required this.capturedAt});
  final Uint8List jpegBytes;
  final DateTime capturedAt;
}

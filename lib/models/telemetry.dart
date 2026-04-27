class DeviceTelemetry {
  const DeviceTelemetry({
    required this.storageFreeBytes,
    required this.storageTotalBytes,
    required this.wifiState,
    this.wifiSsid,
    this.wifiSignalDbm,
    required this.internetReachable,
    required this.tempCelsius,
    required this.ramUsedPct,
    required this.cpuUsedPct,
    required this.uptimeSeconds,
    required this.isRecording,
    required this.isStreaming,
  });

  final int storageFreeBytes;
  final int storageTotalBytes;
  final WifiState wifiState;
  final String? wifiSsid;
  final int? wifiSignalDbm;
  final bool internetReachable;
  final double tempCelsius;
  final double ramUsedPct;
  final double cpuUsedPct;
  final int uptimeSeconds;
  final bool isRecording;
  final bool isStreaming;

  double get storageUsedPct =>
      storageTotalBytes == 0
          ? 0
          : 1 - (storageFreeBytes / storageTotalBytes);
}

enum WifiState { unknown, disabled, disconnected, connected }

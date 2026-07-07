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
    this.batteryLevelPct,
    this.isRawCapturing = false,
  });

  final int storageFreeBytes;
  final int storageTotalBytes;
  final WifiState wifiState;
  final String? wifiSsid;
  final int? wifiSignalDbm;
  final bool internetReachable;
  final double tempCelsius;

  /// RAM / CPU utilisation as a **0–100 percent** (matching the firmware:
  /// `ram_used_pct = used * 100`, `CpuBusyPercent → [0,100]`). Not a 0–1
  /// fraction — display as `pct.round()%`, never `× 100`.
  final double ramUsedPct;
  final double cpuUsedPct;
  final int uptimeSeconds;
  final bool isRecording;
  final bool isStreaming;

  /// Battery charge 0–100, or null when the device does not report a battery.
  final int? batteryLevelPct;

  /// Whether raw dual-camera capture is running. Absent on the wire ⇒ false.
  final bool isRawCapturing;

  double get storageUsedPct =>
      storageTotalBytes == 0 ? 0 : 1 - (storageFreeBytes / storageTotalBytes);
}

enum WifiState { unknown, disabled, disconnected, connected }

/// Frame-truth per-camera health (state-health cycle). [ok] requires frames
/// actually flowing — a pipeline in PLAYING that delivers no samples is NOT
/// ok. [recovering] = stalled, watchdog restart pending/in progress (UIs show
/// a soft indicator, NOT "inoperable"). [down] = restart attempts completed
/// and failed — the device is inoperable for capture (start-class commands
/// are refused with DEVICE_INOPERABLE). [unknown] = unreported (older
/// firmware) — consumers render "—", never fabricate OK.
enum CameraHealth { unknown, ok, recovering, down }

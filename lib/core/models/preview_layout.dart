// Live preview composition (#6 A6b). SINGLE = the chosen camera with overlay
// baked in (the broadcast view; default). SIDE_BY_SIDE = cam0 | cam1
// composited by the firmware into one clean RTSP stream (a "see both cameras"
// monitoring view). The RTSP URL/port are unchanged across a switch — only the
// composited frame geometry changes, which the preview descriptor reports.
enum PreviewLayout { single, sideBySide }

/// Reply to a set-preview-layout request: the now-active layout plus the frame
/// geometry the firmware composites, so the app can size its preview box even
/// before the RTSP descriptor heartbeat catches up.
class PreviewLayoutResult {
  const PreviewLayoutResult({
    required this.layout,
    required this.width,
    required this.height,
  });

  final PreviewLayout layout;
  final int width;
  final int height;

  /// Frame aspect (width / height), or null when geometry is unreported.
  double? get aspect => height > 0 ? width / height : null;
}

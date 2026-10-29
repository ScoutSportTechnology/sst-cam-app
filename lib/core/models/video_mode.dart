// A capture/encode mode: resolution + frame rate. The plain-Dart twin of the
// wire `VideoQuality` (proto). Used for the firmware-advertised supported modes
// (DeviceInfoResponse.supportedModes) and the operator's independent record /
// stream quality selections that ride on RecordingControl / StreamingControl.

class VideoMode {
  const VideoMode({
    required this.width,
    required this.height,
    required this.fps,
  });

  final int width;
  final int height;
  final int fps;

  /// Human label, e.g. "1080p · 60 fps". Resolution is named by height so the
  /// common ladder reads naturally (720p / 1080p / 4K).
  String get label => '$_resolutionName · $fps fps';

  String get _resolutionName => switch (height) {
    >= 2160 => '4K',
    1440 => '1440p',
    1080 => '1080p',
    720 => '720p',
    480 => '480p',
    _ => '${height}p',
  };

  @override
  bool operator ==(Object other) =>
      other is VideoMode &&
      other.width == width &&
      other.height == height &&
      other.fps == fps;

  @override
  int get hashCode => Object.hash(width, height, fps);

  @override
  String toString() => 'VideoMode($width x $height @ $fps)';
}

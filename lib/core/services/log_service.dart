import 'package:flutter/foundation.dart';

/// In-memory ring buffer of recent log lines so on-device debugging does not
/// strictly require adb/logcat. Once [attach] wraps [debugPrint] at startup,
/// every `debugPrint` call is captured here (capped at [_maxLines]); a viewer
/// can render and export them. adb stays the primary path — this is a secondary,
/// in-app surface for when adb isn't available (e.g. someone else's device).
class LogService {
  LogService._();
  static final LogService instance = LogService._();

  static const int _maxLines = 1000;
  final List<String> _lines = <String>[];
  bool _attached = false;

  /// Increments on every add/clear so a [ValueListenableBuilder] can rebuild.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void add(String line) {
    // HH:mm:ss.mmm — enough to correlate with firmware/logcat timestamps.
    final stamp = DateTime.now().toIso8601String().substring(11, 23);
    _lines.add('$stamp  $line');
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    revision.value++;
  }

  List<String> get lines => List.unmodifiable(_lines);

  /// All captured lines as a single newline-joined string, for copy/export.
  String export() => _lines.join('\n');

  void clear() {
    _lines.clear();
    revision.value++;
  }

  /// Wrap [debugPrint] so every call is also captured here. Idempotent — safe to
  /// call from multiple entry points.
  void attach() {
    if (_attached) return;
    _attached = true;
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) add(message);
      original(message, wrapWidth: wrapWidth);
    };
  }
}

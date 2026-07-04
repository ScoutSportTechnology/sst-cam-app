import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// The industry-standard severity ladder — TRACE < DEBUG < INFO < WARN < ERROR
/// < FATAL — layered over `package:logging`. Its built-in [Level]s use Java's
/// java.util.logging names (FINEST/FINER/FINE/CONFIG/SEVERE/SHOUT), which read
/// oddly; these keep the same numeric values (so level filtering + `Level.ALL`
/// still work) but the conventional names, which is what surfaces in the log
/// viewer via `record.level.name`.
///
/// Use the [StdLog] extension helpers rather than the `package:logging` methods:
/// `log.debug(...)` not `log.fine(...)`, `log.warn(...)` not `log.warning(...)`,
/// `log.error(...)` not `log.severe(...)`. INFO keeps its standard name, so
/// `log.info(...)` is unchanged.
abstract final class LogLevels {
  static const trace = Level('TRACE', 400); // was FINER
  static const debug = Level('DEBUG', 500); // was FINE
  static const info = Level('INFO', 800); // unchanged
  static const warn = Level('WARN', 900); // was WARNING
  static const error = Level('ERROR', 1000); // was SEVERE
  static const fatal = Level('FATAL', 1200); // was SHOUT
}

/// Standard-name logging helpers on top of [Logger]. `info()` already exists on
/// [Logger] and emits the standard "INFO" name, so it is intentionally omitted.
extension StdLog on Logger {
  void trace(Object? message, [Object? error, StackTrace? stackTrace]) =>
      log(LogLevels.trace, message, error, stackTrace);
  void debug(Object? message, [Object? error, StackTrace? stackTrace]) =>
      log(LogLevels.debug, message, error, stackTrace);
  void warn(Object? message, [Object? error, StackTrace? stackTrace]) =>
      log(LogLevels.warn, message, error, stackTrace);
  void error(Object? message, [Object? error, StackTrace? stackTrace]) =>
      log(LogLevels.error, message, error, stackTrace);
  void fatal(Object? message, [Object? error, StackTrace? stackTrace]) =>
      log(LogLevels.fatal, message, error, stackTrace);
}

/// One captured log line, kept structured (not a flat string) so the viewer can
/// render a standardized line AND color the level. The canonical text form is
/// [formatted]:
///
///   `DD-MM-YYYY HH:mm:ss LEVEL [source (isolate)]: message`
///
/// where `source` is the logger name (feature code) or the parsed prefix of a
/// legacy `debugPrint`, and `isolate` stands in for a thread id (Dart is
/// single-isolate; the main UI isolate is `main`).
class LogEntry {
  LogEntry({
    required this.time,
    required this.level,
    required this.source,
    required this.message,
  }) : isolate = Isolate.current.debugName ?? 'main';

  final DateTime time;
  final String level;
  final String source;
  final String message;
  final String isolate;

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  /// `DD-MM-YYYY HH:mm:ss` — the standard date+clock stamp.
  String get timestamp {
    final date = '${_pad2(time.day)}-${_pad2(time.month)}-${time.year}';
    final clock =
        '${_pad2(time.hour)}:${_pad2(time.minute)}:${_pad2(time.second)}';
    return '$date $clock';
  }

  /// Timestamp + level + source prefix, without the message — lets the viewer
  /// lay the (colored) level inside the standard structure.
  String get prefix => '$timestamp $level [$source ($isolate)]';

  String get formatted => '$prefix: $message';
}

/// In-memory ring buffer of recent log entries so on-device debugging does not
/// strictly require adb/logcat. Two intake paths, both normalized to [LogEntry]:
///   - [wireLogging] routes `package:logging` records here — the preferred API
///     for feature code (`Logger('WifiService').info('...')`).
///   - [attach] wraps [debugPrint] so legacy raw prints are still captured; a
///     leading `WORD:` / `[tag]` prefix becomes the entry's source.
/// adb stays the primary path — this is the in-app surface for when adb isn't
/// available (e.g. someone else's device).
class LogService {
  LogService._();
  static final LogService instance = LogService._();

  static const int _maxLines = 1000;
  final List<LogEntry> _entries = <LogEntry>[];
  bool _attached = false;
  bool _loggingWired = false;

  /// Increments on every add/clear so a [ValueListenableBuilder] can rebuild.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void _push(LogEntry entry) {
    _entries.add(entry);
    if (_entries.length > _maxLines) {
      _entries.removeRange(0, _entries.length - _maxLines);
    }
    revision.value++;
  }

  /// Low-level structured sink. Prefer `Logger('X')` in feature code (routed
  /// here by [wireLogging]); use this only when a raw level/source is needed.
  void addEntry({
    required String level,
    required String source,
    required String message,
    DateTime? time,
  }) {
    _push(
      LogEntry(
        time: time ?? DateTime.now(),
        level: level,
        source: source,
        message: message,
      ),
    );
  }

  /// Capture a raw string (a legacy `debugPrint`). A leading `WORD:` or `[tag]`
  /// is lifted into the source so existing prefixed prints ('WIFI: …',
  /// '[wifi-handoff] …') land in the standardized structure without a rewrite.
  void captureRaw(String line) {
    final (source, message) = _splitPrefix(line);
    _push(
      LogEntry(
        time: DateTime.now(),
        level: 'INFO',
        source: source,
        message: message,
      ),
    );
  }

  static (String, String) _splitPrefix(String line) {
    final trimmed = line.trimLeft();
    final bracket = RegExp(
      r'^\[([^\]]+)\]\s*(.*)$',
      dotAll: true,
    ).firstMatch(trimmed);
    if (bracket != null) {
      return (bracket.group(1)!, bracket.group(2)!);
    }
    final colon = RegExp(
      r'^([A-Za-z][\w-]{0,20}):\s+(.*)$',
      dotAll: true,
    ).firstMatch(trimmed);
    if (colon != null) {
      return (colon.group(1)!, colon.group(2)!);
    }
    return ('app', trimmed);
  }

  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// All captured entries as standardized newline-joined text, for copy/export.
  String export() => _entries.map((e) => e.formatted).join('\n');

  void clear() {
    _entries.clear();
    revision.value++;
  }

  /// Wrap [debugPrint] so every call is also captured here. Idempotent.
  void attach() {
    if (_attached) return;
    _attached = true;
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) captureRaw(message);
      original(message, wrapWidth: wrapWidth);
    };
  }

  /// Route `package:logging` records into the buffer. Idempotent — call once at
  /// startup (alongside [attach]).
  void wireLogging() {
    if (_loggingWired) return;
    _loggingWired = true;
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((r) {
      addEntry(
        level: r.level.name,
        source: r.loggerName.isEmpty ? 'app' : r.loggerName,
        message: r.error == null ? r.message : '${r.message} — ${r.error}',
        time: r.time,
      );
    });
  }
}

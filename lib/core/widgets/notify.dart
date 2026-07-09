// User-facing notices that ALSO hit the log.
//
// Every snackbar shown through these helpers is mirrored into the app log at a
// matching severity BEFORE it is rendered, so a message the user saw for three
// seconds (a failed connect, a "camera inoperable" refusal, a stream that
// wouldn't start) is still recoverable from the in-app log viewer / adb after
// it has faded. The log line is emitted even when the context is already
// unmounted and the snackbar itself is skipped — the whole point is that the
// record survives regardless of what the UI managed to show.
//
// Pass `source` so the log line is attributed to the workflow that raised it
// (e.g. 'ConnectBanner', 'SessionActions') rather than a generic 'UI'; pass
// `error`/`stackTrace` on failures so the underlying exception (the GATT code,
// the platform message) rides along in the log even though the snackbar text
// stays human-friendly.

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

// StdLog (.warn/.error) extension on Logger lives here.
import '../services/log_service.dart';

/// Show an ERROR-level notice: logged at error, then shown as a snackbar.
/// Use for failures the user should notice AND that must be diagnosable later.
void showErrorSnack(
  BuildContext context,
  String message, {
  String source = 'UI',
  Object? error,
  StackTrace? stackTrace,
}) {
  Logger(source).error(message, error, stackTrace);
  _show(context, message);
}

/// Show a WARN-level notice: logged at warn, then shown as a snackbar. Use for
/// recoverable/expected conditions worth surfacing (disconnected mid-action,
/// nothing to do) that are not hard failures.
void showWarnSnack(
  BuildContext context,
  String message, {
  String source = 'UI',
  Object? error,
  StackTrace? stackTrace,
}) {
  Logger(source).warn(message, error, stackTrace);
  _show(context, message);
}

/// Show an INFO-level notice: logged at info, then shown as a snackbar. Use for
/// confirmations and neutral status ("Saved", "Copied").
void showInfoSnack(
  BuildContext context,
  String message, {
  String source = 'UI',
}) {
  Logger(source).info(message);
  _show(context, message);
}

void _show(BuildContext context, String message) {
  // The log line above already landed; only the visual is context-gated.
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

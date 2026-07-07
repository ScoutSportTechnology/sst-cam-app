// Auto-stop setting (R5, state-health cycle U5) — the app-configurable
// unsupervised-session timeout. The firmware ends a session (recording EOS'd,
// streams stopped, summary recorded) after this many minutes with no app
// connection; the value rides every PushSessionConfig (`auto_stop_minutes`,
// field 16).
//
// Cross-feature per conventions (Settings surface edits it, match setup
// pushes it), so it lives in core/state/. Persisted via shared_preferences
// like last_camera.dart.
//
// Mid-session change: the firmware maps auto_stop_minutes on every
// PushSessionConfig, so when the setting changes while connected with a live
// session, [AutoStopMinutesNotifier.set] re-pushes the last session config
// with the new value immediately — a changed timeout must not be silently
// deferred to the next session. The re-push is best-effort: a wire failure
// keeps the persisted setting (the next session config carries it anyway).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'camera_selection.dart' show activeCameraIdProvider;
import '../../features/video/video_state.dart' show liveSessionActiveProvider;
import '../ble/ble_providers.dart';
import '../models/command.dart';
import '../models/device.dart';
import '../services/log_service.dart';

final _log = Logger('AutoStop');

const String _kAutoStopMinutesKey = 'auto_stop_minutes';

/// Bounds for [AutoStopMinutesNotifier.set] (and the settings picker): no
/// zero/negative (that would end every session instantly) and a sanity max.
const int kAutoStopMinMinutes = 5;
const int kAutoStopMaxMinutes = 240;

/// The last successfully-pushed session config this app run. Written by the
/// setup screen after `pushSessionConfig` succeeds; consumed by the
/// mid-session auto-stop re-push (which needs the full config — the firmware
/// has no partial-update command). Null until a session config was pushed.
final lastPushedSessionConfigProvider = StateProvider<PushSessionConfig?>(
  (_) => null,
);

/// Persisted unsupervised-session timeout in minutes. Defaults to
/// [kDefaultAutoStopMinutes]; clamped to
/// [kAutoStopMinMinutes]..[kAutoStopMaxMinutes] on every write (and on read,
/// so an out-of-range persisted value can never reach the wire).
class AutoStopMinutesNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_kAutoStopMinutesKey);
    if (stored == null) return kDefaultAutoStopMinutes;
    return stored.clamp(kAutoStopMinMinutes, kAutoStopMaxMinutes);
  }

  /// Persist [minutes] (clamped to bounds) and, when connected with a live
  /// session, immediately re-push the session config carrying the new value.
  Future<void> set(int minutes) async {
    final clamped = minutes.clamp(kAutoStopMinMinutes, kAutoStopMaxMinutes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAutoStopMinutesKey, clamped);
    state = AsyncData(clamped);
    await _repushIfSessionLive(clamped);
  }

  /// One extra PushSessionConfig — same config, new timeout — only when it
  /// can take effect now: a config was pushed this run, a camera is
  /// connected, and a session is live. Best-effort (see header).
  Future<void> _repushIfSessionLive(int minutes) async {
    final config = ref.read(lastPushedSessionConfigProvider);
    if (config == null) return;
    final deviceId = ref.read(activeCameraIdProvider);
    if (deviceId == null) return;
    final connected =
        ref.read(connectionStateProvider(deviceId)).valueOrNull ==
        CameraConnectionState.connected;
    if (!connected) return;
    if (!ref.read(liveSessionActiveProvider)) return;

    final updated = config.withAutoStopMinutes(minutes);
    try {
      await ref.read(bleServiceProvider).pushSessionConfig(deviceId, updated);
      ref.read(lastPushedSessionConfigProvider.notifier).state = updated;
      _log.info('auto-stop re-pushed mid-session: $minutes min');
    } catch (e) {
      // Setting is persisted either way; the firmware keeps the old timeout
      // until the next session config.
      _log.warn('mid-session auto-stop re-push failed: $e');
    }
  }
}

/// The configured unsupervised-session timeout (minutes). Consumers: the
/// Settings row (edit) and match setup (rides PushSessionConfig).
final autoStopMinutesProvider =
    AsyncNotifierProvider<AutoStopMinutesNotifier, int>(
      AutoStopMinutesNotifier.new,
    );

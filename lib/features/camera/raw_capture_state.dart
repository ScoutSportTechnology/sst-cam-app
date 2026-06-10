// Raw dual-camera capture control — optimistic state machine that mints the
// capture group id, drives RawCaptureControlCommand over BLE, and auto-downloads
// + persists both per-camera files on stop.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/ble/ble_providers.dart';
import '../../core/db/app_database.dart';
import '../../core/models/command.dart';
import '../../core/models/recording.dart';
import '../../core/state/db_providers.dart';
import '../../core/wifi/wifi_providers.dart';
import 'camera_state.dart';

enum RawCapturePhase { idle, starting, capturing, stopping, downloading, error }

class RawCaptureState {
  const RawCaptureState({
    this.phase = RawCapturePhase.idle,
    this.captureGroupId,
    this.message,
  });

  final RawCapturePhase phase;
  final String? captureGroupId;
  final String? message;

  /// A capture is in flight — block starting another until it settles.
  bool get isBusy =>
      phase == RawCapturePhase.starting ||
      phase == RawCapturePhase.capturing ||
      phase == RawCapturePhase.stopping ||
      phase == RawCapturePhase.downloading;

  bool get isCapturing => phase == RawCapturePhase.capturing;

  RawCaptureState copyWith({
    RawCapturePhase? phase,
    String? captureGroupId,
    String? message,
  }) =>
      RawCaptureState(
        phase: phase ?? this.phase,
        captureGroupId: captureGroupId ?? this.captureGroupId,
        message: message,
      );
}

class RawCaptureController extends Notifier<RawCaptureState> {
  static const _uuid = Uuid();

  @override
  RawCaptureState build() => const RawCaptureState();

  /// Start raw capture: mint the group id, send START, go optimistic.
  Future<void> start() async {
    final deviceId = ref.read(activeCameraIdProvider);
    if (deviceId == null || state.isBusy) return;

    final groupId = _uuid.v4();
    state = RawCaptureState(
      phase: RawCapturePhase.starting,
      captureGroupId: groupId,
    );

    final resp = await ref.read(bleServiceProvider).sendCommand<void>(
          deviceId,
          RawCaptureControlCommand(
            action: RecordingControlAction.start,
            captureGroupId: groupId,
          ),
        );

    state = resp.isOk
        ? RawCaptureState(
            phase: RawCapturePhase.capturing,
            captureGroupId: groupId,
          )
        : const RawCaptureState(
            phase: RawCapturePhase.error,
            message: 'Failed to start raw capture',
          );
  }

  /// Stop raw capture, then auto-download + persist both per-camera files.
  Future<void> stop() async {
    final deviceId = ref.read(activeCameraIdProvider);
    final groupId = state.captureGroupId;
    if (deviceId == null || groupId == null || !state.isCapturing) return;

    final ble = ref.read(bleServiceProvider);
    state = RawCaptureState(
      phase: RawCapturePhase.stopping,
      captureGroupId: groupId,
    );
    await ble.sendCommand<void>(
      deviceId,
      RawCaptureControlCommand(action: RecordingControlAction.stop),
    );

    state = RawCaptureState(
      phase: RawCapturePhase.downloading,
      captureGroupId: groupId,
    );

    final listResp = await ble.sendCommand<List<RecordingMetadata>>(
      deviceId,
      ListRecordingsCommand(),
    );
    final pair = (listResp.payload ?? <RecordingMetadata>[])
        .where((r) => r.isRaw && r.captureGroupId == groupId)
        .toList();

    final wifi = ref.read(wifiServiceProvider);
    final dao = ref.read(rawRecordingsDaoProvider);
    for (final rec in pair) {
      final handle = await wifi.downloadRecording(deviceId, rec.id);
      await dao.upsert(
        RawRecordingsTableCompanion.insert(
          id: rec.id,
          captureGroupId: groupId,
          cameraIndex: rec.cameraIndex ?? 0,
          startedAt: rec.startedAt.toIso8601String(),
          localPath: Value(handle.savePath),
          sizeBytes: Value(rec.sizeBytes),
        ),
      );
    }

    final complete = pair.length == 2;
    if (complete) {
      await dao.setGroupComplete(groupId, complete: true);
      state = const RawCaptureState();
    } else {
      // A missing second file is surfaced, not silently saved as whole.
      state = const RawCaptureState(
        phase: RawCapturePhase.error,
        message: 'Raw capture incomplete — a file may be missing',
      );
    }
  }

  /// Called when the camera disconnects mid-capture: reset to idle with a
  /// non-blocking interrupted banner.
  void onInterrupted() {
    if (state.phase == RawCapturePhase.capturing ||
        state.phase == RawCapturePhase.starting) {
      state = const RawCaptureState(
        phase: RawCapturePhase.error,
        message: 'Raw capture interrupted — files may be incomplete',
      );
    }
  }

  /// Clear an error banner back to idle.
  void acknowledge() {
    if (state.phase == RawCapturePhase.error) {
      state = const RawCaptureState();
    }
  }
}

final rawCaptureProvider =
    NotifierProvider<RawCaptureController, RawCaptureState>(
  RawCaptureController.new,
);

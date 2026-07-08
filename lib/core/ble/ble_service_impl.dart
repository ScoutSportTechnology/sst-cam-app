import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/proto/bluetooth.pb.dart' as proto;
import '../async/seeded_broadcast.dart';
import '../models/command.dart';
import '../models/device.dart';
import '../models/match.dart';
import '../models/network_config.dart';
import '../models/export_job.dart';
import '../models/overlay_layout.dart';
import '../models/preview_layout.dart';
import '../models/recording.dart';
import '../models/telemetry.dart';
import '../services/log_service.dart';
import 'ble_protocol.dart';
import 'ble_seams.dart';
import 'ble_service.dart';

// UUIDs defined in proto/README.md.
//
// When wiring proto encoding, regenerate Dart bindings from
// `proto/bluetooth.proto` (the schema was consolidated from six smaller
// files; see proto/README.md history note).
final _serviceUuid = Guid('A1B2C3D400010000800000805F9B34FB');
final _cmdWriteUuid = Guid('A1B2C3D400110000800000805F9B34FB');
final _cmdResponseUuid = Guid('A1B2C3D400120000800000805F9B34FB');

// Device name prefix — secondary filter after UUID filter
const _kNamePrefix = 'sst-cam-';

// Overall budget for one command round-trip (ack-gated frame writes + response).
const _kCommandTimeout = Duration(seconds: 10);

// Time remaining until [deadline], clamped at zero so Future.timeout never gets a
// negative Duration.
Duration _remainingUntil(DateTime deadline) {
  final remaining = deadline.difference(DateTime.now());
  return remaining.isNegative ? Duration.zero : remaining;
}

final _log = Logger('BleService');

class BleServiceImpl implements BleService {
  BleServiceImpl({
    this.connectTimeout = const Duration(seconds: 20),
    this.disconnectSettle = const Duration(milliseconds: 2500),
  });

  /// Budget for the platform-level connect. Deliberately BELOW the connect
  /// controller's 30 s handshake wall: Dart's `Future.timeout` abandons but
  /// cannot cancel, whereas FBP's own connect timeout actively cancels the
  /// platform attempt AND releases FBP's global op mutex (which `connect`
  /// holds for its whole wait). With FBP's 35 s default, a wall-abandoned
  /// connect kept the mutex wedged past the wall, so every retry queued
  /// behind it and timed out identically until the app was restarted.
  final Duration connectTimeout;

  /// Minimum gap between an observed link teardown and the next platform
  /// connect to the same device. Field bug (2026-07-07, real Jetson + phone):
  /// the phone-side disconnect callback fires ~1 s BEFORE the peripheral
  /// processes the LL teardown and re-asserts its advertisement (journal:
  /// central-link-down + re-advertise landed 1.1–1.2 s after the app's
  /// disconnect); a manual reconnect fired into that window got no response
  /// and died with android error 147 (GATT_CONNECTION_TIMEOUT). Sized to
  /// outlast that whole teardown + re-advertise sequence with margin.
  final Duration disconnectSettle;

  // Seeded so a late subscriber (e.g. re-entering the discovery page) replays the
  // last known device list immediately instead of seeing nothing until the next
  // scan result lands.
  final _discovery = SeededBroadcast<List<SstDevice>>(const []);

  // Accumulated discovered devices, keyed by id. Persists across the FlutterBluePlus
  // scan-restart (startScan internally emits an empty `[]` first); we merge into
  // this map and never relay that empty, so the device list never blanks mid-scan
  // (the bug where a found camera flashed then vanished). Cleared silently at the
  // start of a new scan so stale devices drop without blanking the UI.
  final Map<String, SstDevice> _discovered = {};

  // Persistent per-device channels. A slot is created lazily on first
  // stream access OR on connect and is REUSED across connect/disconnect cycles —
  // never removed on disconnect — so the connection/telemetry/match streams keep
  // a stable identity and replay current state to late subscribers. Slots are
  // only torn down in [dispose].
  final Map<String, _ConnectedDevice> _devices = {};
  bool _isScanning = false;

  // Live subscriptions for the active scan. The results listener MUST outlive
  // the `FlutterBluePlus.startScan()` future: that future completes the instant
  // the platform scan STARTS (its `timeout` only schedules a later auto-stop),
  // so the old code — which cancelled the listener in a `finally` right after
  // the await — tore it down before any advert was delivered. The platform scan
  // kept running and buffering, but nothing relayed results into `_discovery`,
  // so the page sat empty until you re-entered it (which re-listened and picked
  // up the buffered results). These subs instead live until the scan actually
  // stops, observed via `FlutterBluePlus.isScanning`.
  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<bool>? _isScanningSub;

  @override
  Stream<bool> get bluetoothOn =>
      FlutterBluePlus.adapterState.map((s) => s == BluetoothAdapterState.on);

  @override
  Future<void> requestBluetoothOn() async {
    // Android can prompt the user to enable Bluetooth in-app; other platforms
    // have no equivalent, and a decline/timeout just leaves the adapter off
    // (the UI keeps showing the "Bluetooth is off" banner).
    try {
      await FlutterBluePlus.turnOn();
    } catch (_) {
      // Unsupported platform / user declined — nothing to do.
    }
  }

  @override
  bool get isScanning => _isScanning;

  @override
  Stream<List<SstDevice>> get discoveredDevices => _discovery.stream;

  _ConnectedDevice _deviceSlot(String deviceId) =>
      _devices.putIfAbsent(deviceId, () => _ConnectedDevice(deviceId));

  // ---------------------------------------------------------------------------
  // Discovery — filter by advertised service UUID (primary) + name prefix
  // ---------------------------------------------------------------------------

  @override
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_isScanning) return;
    // Claim the scan slot BEFORE the first await. The permission request below
    // can suspend for seconds behind the OS dialog; without claiming the slot
    // up-front a second startScan (e.g. a double-tapped Scan button) would slip
    // past the guard, re-wire the subscriptions, and orphan the first call's
    // live results listener (alive, feeding _discovery, unreachable to cancel).
    // The catch releases the slot on any setup failure.
    _isScanning = true;

    try {
      // Android 12+ requires the BLUETOOTH_SCAN/CONNECT runtime permissions (and
      // FINE_LOCATION on API <= 31) to be granted before a scan returns any
      // results — declaring them in the manifest is not enough. Without this the
      // OS never prompts and FlutterBluePlus.startScan silently yields nothing.
      // permission_handler no-ops on platforms that don't gate these (iOS asks
      // via Info.plist usage strings on first BLE use).
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      if (statuses[Permission.bluetoothScan]?.isGranted == false ||
          statuses[Permission.bluetoothConnect]?.isGranted == false) {
        throw StateError(
          'Bluetooth permission denied — grant Nearby devices / Bluetooth to scan.',
        );
      }

      // Drop stale devices for this fresh scan WITHOUT emitting — late
      // subscribers keep seeing the last list (replayed by the seeded stream)
      // until the first real result repopulates, so the UI never flashes empty.
      _discovered.clear();

      // Relay scan results for the WHOLE lifetime of the scan. Stored in a field
      // (not a local cancelled in `finally`) because `startScan()` returns before
      // results arrive — see the field doc.
      await _scanResultsSub?.cancel();
      _scanResultsSub = FlutterBluePlus.onScanResults.listen((results) {
        var changed = false;
        for (final r in results) {
          final name = r.advertisementData.advName.toLowerCase();
          if (!name.startsWith(_kNamePrefix)) continue;
          _discovered[r.device.remoteId.str] = SstDevice(
            id: r.device.remoteId.str,
            name: r.advertisementData.advName,
            firmwareVersion: '',
            model: '',
            protocolVersion: 0,
          );
          changed = true;
        }
        // Only emit when we actually have matching results — never relay the
        // empty list FlutterBluePlus pushes at scan start (that blanked the UI).
        if (changed) {
          _discovery.add(List.unmodifiable(_discovered.values.toList()));
        }
      });

      // Retire the results listener when the platform scan actually stops
      // (timeout fires or stopScan is called) — NOT when `startScan()` returns.
      // Guard on `sawScanning` so a stale `false` replayed at subscribe time
      // can't clear the slot we claimed above before the scan has even begun.
      final scanLifecycle = ScanLifecycleTracker();
      await _isScanningSub?.cancel();
      _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
        if (scanLifecycle.onScanningChanged(scanning)) {
          _isScanning = false;
          unawaited(_teardownScanSubscriptions());
        }
      });

      // Primary filter: only devices advertising the SST-Cam service UUID (set in
      // the firmware advertising payload). The name-prefix check above is a
      // secondary safeguard. This future completes when the scan STARTS; the
      // subscriptions above carry it the rest of the way.
      await FlutterBluePlus.startScan(
        withServices: [_serviceUuid],
        timeout: timeout,
      );
    } catch (_) {
      // Setup failed (permission denied, adapter off, platform throw): release
      // the claimed slot and tear down any partial subscriptions so the next
      // startScan starts clean and nothing relays results with no active scan.
      _isScanning = false;
      await _teardownScanSubscriptions();
      rethrow;
    }
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _isScanning = false;
    await _teardownScanSubscriptions();
  }

  // Cancel and null both scan subscriptions. Single teardown path shared by
  // stopScan, the scan-end listener, a failed startScan, and dispose so the two
  // subs never diverge across the competing call sites.
  Future<void> _teardownScanSubscriptions() async {
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
    await _isScanningSub?.cancel();
    _isScanningSub = null;
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  @override
  Future<void> connect(String deviceId) async {
    _log.info('connecting to camera $deviceId');
    final device = BluetoothDevice(remoteId: DeviceIdentifier(deviceId));
    // Reuse the persistent slot so any stream subscribed BEFORE connect (the
    // discovery row watches connectionStateStream at build time) receives the
    // connecting/connected transitions on the same controller.
    final conn = _deviceSlot(deviceId);
    // Attempt epoch: a newer connect()/disconnect() supersedes this attempt.
    // A handshake-wall timeout abandons this future WITHOUT cancelling it, so
    // its remaining steps keep running — every slot mutation and the failure
    // teardown below are epoch-guarded so a late-failing abandoned attempt
    // can never tear down the state a newer attempt has just built (that
    // cross-attempt teardown made "retry" fail forever on device until the
    // app was killed).
    final attempt = ++conn._attemptEpoch;
    conn._device = device;

    conn._connController.add(CameraConnectionState.connecting);

    // Throws when a newer attempt (or a disconnect) took over the slot while
    // this one was awaiting — routed to the catch below, which then leaves
    // both the slot and the platform link untouched for the new owner.
    void ensureCurrent() {
      if (conn._attemptEpoch != attempt) {
        throw BleConnectionException(
          'Connect attempt superseded for $deviceId',
        );
      }
    }

    try {
      // Settle the previous link's GATT teardown before reconnecting — see
      // [disconnectSettle]. Without this, a connect fired right after a
      // manual disconnect races the peripheral's teardown + re-advertise and
      // times out with android error 147.
      final lastTeardown = conn._lastTeardownAt;
      if (lastTeardown != null) {
        final wait = disconnectSettle - DateTime.now().difference(lastTeardown);
        if (wait > Duration.zero) {
          _log.info(
            'settling GATT teardown of $deviceId for ${wait.inMilliseconds} ms '
            'before reconnecting',
          );
          await Future<void>.delayed(wait);
          ensureCurrent();
        }
      }

      // Bounded below the controller's handshake wall — see [connectTimeout].
      await device.connect(autoConnect: false, timeout: connectTimeout);
      ensureCurrent();
      // requestMtu returns the ACTUAL negotiated MTU, which can be below 512 on
      // real hardware. Derive the chunk budget from it — a fixed 400-byte chunk
      // overflows a single GATT write on a sub-512 MTU (the #1 bring-up risk).
      // requestMtu is Android-only; platforms that negotiate the MTU implicitly
      // (iOS, host-side tests against a fake platform) throw androidOnly — fall
      // back to the platform-tracked value instead of failing the connect.
      int negotiatedMtu;
      try {
        negotiatedMtu = await device.requestMtu(512);
      } on FlutterBluePlusException catch (e) {
        if (e.code != FbpErrorCode.androidOnly.index) rethrow;
        negotiatedMtu = device.mtuNow;
      }
      ensureCurrent();
      conn.chunkDataBudget = BleProtocol.chunkBudgetForMtu(negotiatedMtu);

      final services = await device.discoverServices();
      ensureCurrent();
      final svc = services.where((s) => s.uuid == _serviceUuid).firstOrNull;

      if (svc == null) {
        throw BleConnectionException('SST-Cam service not found on $deviceId');
      }

      conn._cmdWrite = svc.characteristics
          .where((c) => c.uuid == _cmdWriteUuid)
          .firstOrNull;
      conn._cmdResponse = svc.characteristics
          .where((c) => c.uuid == _cmdResponseUuid)
          .firstOrNull;

      if (conn._cmdWrite == null || conn._cmdResponse == null) {
        throw BleConnectionException(
          'Required characteristics not found on $deviceId',
        );
      }

      await conn._cmdResponse!.setNotifyValue(true);
      ensureCurrent();
      conn._startResponseListener();

      // Link is up and the command channel works, but the §9b handshake
      // (protocol gate → time push → snapshot → rehydrate → reconcile) has
      // not run yet — that is the connect controller's job. Expose
      // `reconciling` so session-affecting UI (which gates on `connected`
      // only) stays locked until completeHandshake().
      conn._connController.add(CameraConnectionState.reconciling);
      _log.info('camera $deviceId link up — awaiting handshake');

      // Listen for unexpected disconnection. Keep the slot (replays
      // disconnected to existing/late subscribers) — only tear down the
      // transient connection resources. Epoch-guarded: once a newer attempt
      // owns the slot, a leaked/lagging subscription from this one no-ops.
      conn._connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected &&
            conn._attemptEpoch == attempt) {
          conn._lastTeardownAt = DateTime.now();
          conn._connController.add(CameraConnectionState.disconnected);
          conn.teardownConnection();
        }
      });
    } catch (e) {
      _log.warn('connect to camera $deviceId failed', e);
      if (conn._attemptEpoch == attempt) {
        // Drop whatever the platform holds for THIS attempt — a live link
        // when a post-link step failed, or an in-progress attempt. Without
        // this the platform kept a connection the app no longer had a handle
        // to (teardown nulls _device, so the controller's cleanup disconnect
        // silently no-oped) and the next connect ran against that ghost.
        // queue:false jumps FBP's op queue so a stuck connect is CANCELLED
        // rather than waited behind. Skipped entirely when superseded: the
        // remoteId now belongs to the newer attempt's live link.
        try {
          await device.disconnect(queue: false);
        } catch (_) {
          // Best-effort — surface the original failure below.
        }
        conn._lastTeardownAt = DateTime.now();
        conn._connController.add(CameraConnectionState.disconnected);
        conn.teardownConnection();
      }
      if (e is BleConnectionException || e is BleProtocolVersionException) {
        rethrow;
      }
      throw BleConnectionException('Connect failed: $e');
    }
  }

  @override
  void completeHandshake(String deviceId) {
    final conn = _devices[deviceId];
    // Only a device sitting in `reconciling` with a live command channel can
    // complete — a raced disconnect (cmdWrite already torn down) must not
    // resurrect `connected` or start pollers against a dead link.
    if (conn == null ||
        conn._cmdWrite == null ||
        conn._connController.value != CameraConnectionState.reconciling) {
      return;
    }

    conn._connController.add(CameraConnectionState.connected);
    _log.info('connected to camera $deviceId (handshake complete)');

    // Pollers start ONLY here — after reconcile — so a match-state poll can
    // never land mid-handshake and mutate live state before the snapshot
    // restore reads it. Polling from here (not as a stream-subscribe side
    // effect) ties the pollers' lifecycle to the connection, and a UI that
    // subscribes before connect still gets ticks after connect.
    conn._startTelemetryPolling(
      (cmd) => sendCommand<DeviceTelemetry>(deviceId, cmd),
    );
    conn._startMatchStatePolling(
      (cmd) => sendCommand<MatchState>(deviceId, cmd),
    );
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final conn = _devices[deviceId];
    if (conn == null) return;
    _log.info('disconnecting camera $deviceId');
    // Supersede any in-flight connect attempt: its late failure path must not
    // re-tear-down (or platform-disconnect) after this explicit teardown.
    conn._attemptEpoch++;
    conn._connController.add(CameraConnectionState.disconnecting);
    // Build the handle from the id — conn._device may already be null (a
    // failed handshake's teardown clears it) while the platform still holds
    // a link or an in-progress attempt; FBP devices are value handles keyed
    // by remote id, so this always addresses the right connection. The old
    // `conn._device?.disconnect()` silently no-oped in exactly that state,
    // leaving a ghost platform link behind a "disconnected" app.
    final device =
        conn._device ?? BluetoothDevice(remoteId: DeviceIdentifier(deviceId));
    try {
      // queue:false jumps FBP's op queue: a user disconnect must CANCEL an
      // in-progress connect attempt (FBP holds its global op mutex for the
      // whole connect wait — queueing behind it wedged every reconnect retry
      // until app restart) and shouldn't wait behind in-flight polls either.
      await device.disconnect(queue: false);
    } finally {
      // FBP's disconnect resolves once the PHONE observes disconnected; the
      // peripheral's teardown + re-advertise completes later. Stamp now so
      // the next connect() waits out the remainder (see [disconnectSettle]).
      conn._lastTeardownAt = DateTime.now();
      conn._connController.add(CameraConnectionState.disconnected);
      // Keep the slot so the connection stream replays disconnected and a
      // later reconnect reuses the same controllers.
      conn.teardownConnection();
    }
  }

  @override
  Stream<CameraConnectionState> connectionStateStream(String deviceId) {
    // Seeded with disconnected, so a subscriber attaching before connect (or
    // after disconnect) immediately sees the current state and then every
    // transition on this stable controller.
    return _deviceSlot(deviceId)._connController.stream;
  }

  // ---------------------------------------------------------------------------
  // Telemetry — app polls at ~1 Hz; stream exposed to UI
  // ---------------------------------------------------------------------------

  @override
  Stream<DeviceTelemetry> telemetryStream(String deviceId) {
    // Stable seeded stream; polling is started by connect(), not here, so
    // subscription order relative to connect no longer changes behavior.
    return _deviceSlot(deviceId)._telemetryController.stream;
  }

  // ---------------------------------------------------------------------------
  // Thumbnail — single poll
  // ---------------------------------------------------------------------------

  @override
  Future<ThumbnailResult> requestThumbnail(
    String deviceId, {
    int width = 160,
    int height = 90,
    int quality = 60,
  }) async {
    final resp = await sendCommand<ThumbnailResult>(
      deviceId,
      RequestThumbnailCommand(width: width, height: height, quality: quality),
    );
    if (!resp.isOk || resp.payload == null) {
      throw BleTimeoutException(
        'Thumbnail request failed: ${resp.errorMessage}',
      );
    }
    return resp.payload!;
  }

  // ---------------------------------------------------------------------------
  // Match state — app polls; stream exposed to UI
  // ---------------------------------------------------------------------------

  @override
  Stream<MatchState> matchStateStream(String deviceId) {
    // Stable seeded stream; polling is started by connect(), not here.
    return _deviceSlot(deviceId)._matchStateController.stream;
  }

  // ---------------------------------------------------------------------------
  // Commands — encode via BleProtocol → write ChunkedPayload to cmdWrite;
  // await ChunkedPayload response on cmdResponse → decode via BleProtocol.
  // ---------------------------------------------------------------------------

  @override
  Future<BleCommandResponse<T>> sendCommand<T>(
    String deviceId,
    BleCommand command,
  ) async {
    final conn = _devices[deviceId];
    if (conn == null || conn._cmdWrite == null) {
      return BleCommandResponse.error('Device $deviceId not connected');
    }

    final corrId = BleProtocol.newCorrelationId();
    try {
      final frames = BleProtocol.encodeCommandFrames(
        command,
        corrId,
        maxDataBytes: conn.chunkDataBudget,
      );
      final responseBytes = await conn._sendFramesAndAwait(
        corrId,
        frames,
        'Command ${command.runtimeType} for $deviceId',
      );
      return BleProtocol.decodeResponse<T>(responseBytes, corrId);
    } on BleTimeoutException {
      return BleCommandResponse<T>.timeout();
    } catch (e) {
      return BleCommandResponse.error('sendCommand failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Session push (U9)
  // ---------------------------------------------------------------------------

  @override
  Future<void> pushSessionConfig(
    String deviceId,
    PushSessionConfig config,
  ) async {
    final conn = _devices[deviceId];
    if (conn == null || conn._cmdWrite == null) {
      throw BleConnectionException('Device $deviceId not connected');
    }

    // Fix 14: PushSessionConfig is not a BleCommand and never routes through
    // sendCommand/_toProtoCommand. It encodes via the dedicated
    // encodeSessionConfigFrames helper and shares the request lifecycle via
    // _sendFramesAndAwait.
    final corrId = BleProtocol.newCorrelationId();
    final frames = BleProtocol.encodeSessionConfigFrames(
      config,
      corrId,
      maxDataBytes: conn.chunkDataBudget,
    );
    final responseBytes = await conn._sendFramesAndAwait(
      corrId,
      frames,
      'pushSessionConfig for $deviceId',
    );
    final resp = BleProtocol.decodeSessionConfigResponse(responseBytes, corrId);
    if (!resp.isOk) {
      throw BleConnectionException(
        'pushSessionConfig failed: ${resp.errorMessage}',
      );
    }
  }

  @override
  Future<void> pushOverlayLayout(String deviceId, OverlayLayout layout) async {
    final resp = await sendCommand<void>(
      deviceId,
      PushOverlayLayoutCommand(layout: layout),
    );
    if (!resp.isOk) {
      throw BleConnectionException(
        'pushOverlayLayout failed: ${resp.errorMessage}',
      );
    }
  }

  @override
  Future<PreviewLayoutResult> setPreviewLayout(
    String deviceId,
    PreviewLayout layout,
  ) async {
    final resp = await sendCommand<PreviewLayoutResult>(
      deviceId,
      SetPreviewLayoutCommand(layout: layout),
    );
    if (!resp.isOk) {
      throw BleConnectionException(
        'setPreviewLayout failed: ${resp.errorMessage}',
      );
    }
    final result = resp.payload;
    if (result == null) {
      throw const BleConnectionException(
        'setPreviewLayout: firmware returned no PreviewLayoutResponse',
      );
    }
    return result;
  }

  @override
  Future<void> setCameraCalibration(
    String deviceId, {
    required double rGain,
    required double gGain,
    required double bGain,
    bool enabled = true,
    double saturation = 1.0,
    double contrast = 1.0,
    double brightness = 0.0,
  }) async {
    // Decodes to a CameraCalibrationResult echo; we ignore it (the sliders are the
    // source of truth for a manual set).
    final resp = await sendCommand<CameraCalibrationResult>(
      deviceId,
      SetCameraCalibrationCommand(
        rGain: rGain,
        gGain: gGain,
        bGain: bGain,
        enabled: enabled,
        saturation: saturation,
        contrast: contrast,
        brightness: brightness,
      ),
    );
    if (!resp.isOk) {
      throw BleConnectionException(
        'setCameraCalibration failed: ${resp.errorMessage}',
      );
    }
  }

  @override
  Future<CameraCalibrationResult?> autoWhiteBalance(String deviceId) async {
    final resp = await sendCommand<CameraCalibrationResult>(
      deviceId,
      AutoWhiteBalanceCommand(),
    );
    if (!resp.isOk) {
      throw BleConnectionException(
        'autoWhiteBalance failed: ${resp.errorMessage}',
      );
    }
    return resp.payload;
  }

  @override
  Future<CameraFocusResult?> setCameraFocus(
    String deviceId, {
    required CameraFocusMode mode,
    int? position,
    int? cameraIndex,
  }) async {
    final resp = await sendCommand<CameraFocusResult>(
      deviceId,
      CameraFocusCommand(
        mode: mode,
        position: position,
        cameraIndex: cameraIndex,
      ),
    );
    if (!resp.isOk) {
      throw BleConnectionException(
        'setCameraFocus failed: ${resp.errorMessage}',
      );
    }
    return resp.payload;
  }

  @override
  Future<void> setActiveCamera(String deviceId, int cameraIndex) async {
    final resp = await sendCommand<void>(
      deviceId,
      SetActiveCameraCommand(cameraIndex: cameraIndex),
    );
    if (!resp.isOk) {
      throw BleConnectionException(
        'setActiveCamera failed: ${resp.errorMessage}',
      );
    }
  }

  @override
  Future<NetworkConfigResult> setNetworkConfig(
    String deviceId,
    NetworkConfig config,
  ) => _networkConfig(
    deviceId,
    SetNetworkConfigCommand(config: config),
    'setNetworkConfig',
  );

  @override
  Future<NetworkConfigResult> getNetworkConfig(String deviceId) =>
      _networkConfig(deviceId, GetNetworkConfigCommand(), 'getNetworkConfig');

  @override
  Future<DeviceInfoResponse?> getDeviceInfo(String deviceId) async {
    final r = await sendCommand<DeviceInfoResponse>(
      deviceId,
      GetDeviceInfoCommand(),
    );
    return (r.isOk) ? r.payload : null;
  }

  // Shared round-trip for Set/GetNetworkConfig — both reply with the same
  // NetworkConfigResult (echoed config + live status).
  Future<NetworkConfigResult> _networkConfig(
    String deviceId,
    BleCommand command,
    String label,
  ) async {
    final resp = await sendCommand<NetworkConfigResult>(deviceId, command);
    if (!resp.isOk) {
      if (resp.isUnsupported) {
        // Old firmware predating the NetworkConfig command surface — surface a
        // distinct, actionable exception rather than a generic failure.
        throw BleNetworkConfigUnsupportedException(resp.errorMessage);
      }
      throw BleConnectionException('$label failed: ${resp.errorMessage}');
    }
    final result = resp.payload;
    if (result == null) {
      throw BleConnectionException(
        '$label: firmware returned no NetworkConfigResponse',
      );
    }
    return result;
  }

  @override
  Future<ExportJob> requestOverlayExport(
    String deviceId,
    String recordingId,
  ) async {
    final resp = await sendCommand<ExportJob>(
      deviceId,
      ExportOverlayedCommand(recordingId: recordingId),
    );
    if (!resp.isOk) {
      // Carry the stable LIVE_SESSION_ACTIVE token (derived from the typed
      // response status, NOT the firmware's free-form message) so the UI can
      // recognise the live-session case regardless of wording.
      if (resp.isLiveSessionActive) {
        throw const BleConnectionException(
          'overlay export request failed: LIVE_SESSION_ACTIVE',
        );
      }
      throw BleConnectionException(
        'overlay export request failed: ${resp.errorMessage}',
      );
    }
    final job = resp.payload;
    if (job == null) {
      throw const BleConnectionException(
        'overlay export: firmware returned no ExportJobResponse',
      );
    }
    return job;
  }

  @override
  Future<ExportJob> pollOverlayExport(String deviceId, String jobId) async {
    final resp = await sendCommand<ExportJob>(
      deviceId,
      PollExportCommand(jobId: jobId),
    );
    if (!resp.isOk) {
      throw BleConnectionException(
        'overlay export poll failed: ${resp.errorMessage}',
      );
    }
    final job = resp.payload;
    if (job == null) {
      throw const BleConnectionException(
        'overlay export poll: firmware returned no ExportJobResponse',
      );
    }
    return job;
  }

  // ---------------------------------------------------------------------------
  // Recordings
  // ---------------------------------------------------------------------------

  @override
  Future<List<RecordingMetadata>> listRecordings(String deviceId) async {
    final resp = await sendCommand<List<RecordingMetadata>>(
      deviceId,
      ListRecordingsCommand(),
    );
    if (!resp.isOk || resp.payload == null) {
      throw BleTimeoutException('listRecordings failed: ${resp.errorMessage}');
    }
    return resp.payload!;
  }

  @override
  Future<DownloadToken> requestDownload(
    String deviceId,
    String recordingId,
  ) async {
    final resp = await sendCommand<DownloadToken>(
      deviceId,
      DownloadRequestCommand(recordingId: recordingId),
    );
    if (!resp.isOk || resp.payload == null) {
      throw BleTimeoutException('requestDownload failed: ${resp.errorMessage}');
    }
    return resp.payload!;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  Future<void> dispose() async {
    await _teardownScanSubscriptions();
    for (final conn in _devices.values) {
      await conn._device?.disconnect();
      conn.dispose();
    }
    _devices.clear();
    await _discovery.close();
  }
}

// ---------------------------------------------------------------------------
// Per-connection state
// ---------------------------------------------------------------------------

class _ConnectedDevice {
  _ConnectedDevice(this.deviceId);

  /// Stable id for this persistent slot. The transient [_device] (and the
  /// characteristics/timers below) are (re)assigned on each connect and cleared
  /// on disconnect; the seeded controllers below live for the slot's lifetime.
  final String deviceId;

  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  /// Monotonic connect-attempt epoch. Bumped by every connect() and
  /// disconnect() so an ABANDONED attempt (the handshake wall times out but
  /// cannot cancel the underlying future) detects it was superseded and keeps
  /// its hands off the slot + platform link the new owner is using.
  int _attemptEpoch = 0;

  /// When this device's last link teardown was observed (manual disconnect,
  /// failed-connect cleanup, or an unexpected drop). The next connect() gates
  /// on it — see [BleServiceImpl.disconnectSettle].
  DateTime? _lastTeardownAt;

  // Seeded controllers: replay current value to late subscribers and keep a
  // stable identity across connect/disconnect cycles. Connection state seeds
  // disconnected so a pre-connect subscriber sees a defined state immediately.
  final _connController = SeededBroadcast<CameraConnectionState>(
    CameraConnectionState.disconnected,
  );
  final _telemetryController = SeededBroadcast<DeviceTelemetry>();
  final _matchStateController = SeededBroadcast<MatchState>();
  final _pendingRequests = <String, Completer<List<int>>>{};

  /// Per-frame `data` budget derived from the negotiated ATT MTU at connect.
  /// Defaults to the proven cap; lowered when the device negotiates below 512.
  int chunkDataBudget = BleProtocol.maxChunkDataBytes;

  BluetoothCharacteristic? _cmdWrite;
  BluetoothCharacteristic? _cmdResponse;
  StreamSubscription<List<int>>? _responseSub;
  Timer? _telemetryTimer;
  Timer? _matchStateTimer;

  // Inbound response reassembly — index-addressed (NOT arrival-order), one
  // ChunkReassembler per correlation_id. Completes once every index [0, total)
  // is present.
  final _reassemblers = <String, ChunkReassembler>{};

  // Outbound chunk flow-control — completers awaiting an inbound ChunkAck for a
  // given correlation_id + chunk_index (see [_writeFrames]).
  final _pendingAcks = <String, Map<int, Completer<void>>>{};

  /// Writes [frames] (one or more ChunkedPayload frames sharing [corrId]) to the
  /// command-write characteristic. The single-frame fast path writes once and
  /// returns. For multi-frame commands the write loop is ack-gated: after each
  /// frame it awaits the inbound [proto.ChunkAck] for that `chunk_index` before
  /// sending the next, so a missing/late ack stalls (and the caller's overall
  /// timeout fires) rather than racing ahead.
  /// Registers a pending request for [corrId], writes [frames] (ack-gated for
  /// multi-frame), and awaits the response bytes — all under one shared timeout
  /// budget. Shared verbatim by sendCommand and pushSessionConfig so the
  /// flow-control lifecycle lives in exactly one place. [timeoutLabel] names the
  /// operation in the timeout message.
  Future<List<int>> _sendFramesAndAwait(
    String corrId,
    List<Uint8List> frames,
    String timeoutLabel,
  ) async {
    final completer = Completer<List<int>>();
    _pendingRequests[corrId] = completer;
    try {
      // One shared deadline spans the ack-gated writes AND the response wait, so
      // a multi-chunk command cannot stack per-chunk timeouts past the budget.
      final deadline = DateTime.now().add(_kCommandTimeout);
      await _writeFrames(corrId, frames, deadline);
      return await completer.future.timeout(
        _remainingUntil(deadline),
        onTimeout: () {
          _pendingRequests.remove(corrId);
          throw BleTimeoutException('$timeoutLabel timed out');
        },
      );
    } finally {
      _pendingRequests.remove(corrId);
      _cleanupCorrelation(corrId);
    }
  }

  Future<void> _writeFrames(
    String corrId,
    List<Uint8List> frames,
    DateTime deadline,
  ) async {
    final write = _cmdWrite;
    if (write == null) {
      throw const BleConnectionException('command-write characteristic absent');
    }
    // The firmware command characteristic declares ONLY "write-without-response"
    // (see firmware gatt-application.cpp). Writing with-response issues an ATT
    // Write Request the GATT stack rejects, which failed the very first
    // GetDeviceInfo handshake on hardware. Application-level confirmation comes
    // back via the response/notify characteristic (ChunkAck), not the ATT layer.
    if (frames.length == 1) {
      await write.write(frames.first, withoutResponse: true);
      return;
    }
    for (var i = 0; i < frames.length; i++) {
      final ackCompleter = Completer<void>();
      (_pendingAcks[corrId] ??= {})[i] = ackCompleter;
      await write.write(frames[i], withoutResponse: true);
      try {
        // Share the caller's overall deadline; a missing/late ack surfaces as a
        // BleTimeoutException (so sendCommand maps it to a clean timeout result)
        // rather than a raw TimeoutException or an unbounded stall.
        await ackCompleter.future.timeout(
          _remainingUntil(deadline),
          onTimeout: () => throw BleTimeoutException(
            'ChunkAck timeout (chunk $i) for $corrId',
          ),
        );
      } finally {
        _pendingAcks[corrId]?.remove(i);
        if (_pendingAcks[corrId]?.isEmpty ?? false) {
          _pendingAcks.remove(corrId);
        }
      }
    }
  }

  /// Clears any reassembly / ack-flow state for [corrId]. Called when a request
  /// completes or times out so buffers do not leak.
  void _cleanupCorrelation(String corrId) {
    _reassemblers.remove(corrId);
    _pendingAcks.remove(corrId);
  }

  void _startResponseListener() {
    // Never stack listeners: an overwritten subscription would keep feeding
    // frames (subscription-not-cancelled ghost-state class).
    _responseSub?.cancel();
    _responseSub = _cmdResponse?.onValueReceived.listen((rawBytes) {
      try {
        final chunk = proto.ChunkedPayload.fromBuffer(rawBytes);
        final corrId = chunk.correlationId;
        final total = chunk.totalChunks;

        // Disambiguate an inbound ChunkAck (outbound flow-control) from an
        // inbound ChunkedPayload response (total_chunks: 0=ack, 1=single, >=2
        // multi). See [classifyInboundFrame].
        switch (classifyInboundFrame(total)) {
          case InboundFrameKind.ack:
            _pendingAcks[corrId]?.remove(chunk.chunkIndex)?.complete();
            return;
          case InboundFrameKind.singlePayload:
            // Single-chunk fast path: ack (flow control is symmetric per the
            // contract) then deliver immediately.
            _sendAck(corrId, chunk.chunkIndex);
            _pendingRequests.remove(corrId)?.complete(rawBytes);
            return;
          case InboundFrameKind.multiPayload:
            break; // fall through to reassembly below
        }

        // Multi-chunk: ack this chunk, then place its data at chunk_index
        // (index-addressed — ignores arrival order; duplicates overwrite).
        _sendAck(corrId, chunk.chunkIndex);

        final reassembler = _reassemblers.putIfAbsent(
          corrId,
          ChunkReassembler.new,
        );
        final assembled = reassembler.add(chunk);
        if (assembled != null) {
          // Re-wrap reassembled data in a single ChunkedPayload so
          // decodeResponse() can strip the envelope uniformly.
          final full = proto.ChunkedPayload(
            correlationId: corrId,
            chunkIndex: 0,
            totalChunks: 1,
            data: assembled,
          ).writeToBuffer();
          _reassemblers.remove(corrId);
          _pendingRequests.remove(corrId)?.complete(full);
        }
      } catch (_) {
        // Malformed chunk — silently drop; the pending completer will
        // eventually time out and surface as BleResponseStatus.timeout.
      }
    });
  }

  /// Writes a ChunkAck for ([corrId], [chunkIndex]) back to the camera.
  /// Best-effort — failures are swallowed; the camera's own retransmit/timeout
  /// handling covers a dropped ack.
  void _sendAck(String corrId, int chunkIndex) {
    final write = _cmdWrite;
    if (write == null) return;
    unawaited(
      write
          .write(
            BleProtocol.encodeChunkAck(corrId, chunkIndex),
            withoutResponse: true,
          )
          .catchError((_) {}),
    );
  }

  void _startTelemetryPolling(
    Future<BleCommandResponse<DeviceTelemetry>> Function(BleCommand) send,
  ) {
    _telemetryTimer ??= Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final resp = await send(GetTelemetryCommand());
        if (resp.isOk && resp.payload != null) {
          _telemetryController.add(resp.payload!);
        }
      } catch (_) {}
    });
  }

  void _startMatchStatePolling(
    Future<BleCommandResponse<MatchState>> Function(BleCommand) send,
  ) {
    _matchStateTimer ??= Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final resp = await send(GetMatchStateCommand());
        if (resp.isOk && resp.payload != null) {
          _matchStateController.add(resp.payload!);
        }
      } catch (_) {}
    });
  }

  /// Tears down the transient connection (timers, response subscription,
  /// in-flight requests, characteristics) WITHOUT closing the seeded controllers
  /// or removing the slot. Called on disconnect so the connection stream keeps
  /// replaying the (disconnected) state and a later reconnect reuses the same
  /// controllers. Safe to call repeatedly.
  void teardownConnection() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    _matchStateTimer?.cancel();
    _matchStateTimer = null;
    _responseSub?.cancel();
    _responseSub = null;
    _connSub?.cancel();
    _connSub = null;
    // Fail any in-flight requests/acks so awaiting callers get a clean error
    // immediately on disconnect instead of hanging until their timeout fires.
    for (final c in _pendingRequests.values) {
      if (!c.isCompleted) {
        c.completeError(const BleConnectionException('Connection closed'));
      }
    }
    _pendingRequests.clear();
    for (final acks in _pendingAcks.values) {
      for (final c in acks.values) {
        if (!c.isCompleted) {
          c.completeError(const BleConnectionException('Connection closed'));
        }
      }
    }
    _pendingAcks.clear();
    _reassemblers.clear();
    _cmdWrite = null;
    _cmdResponse = null;
    _device = null;
  }

  /// Full teardown including the seeded controllers — only on service dispose.
  void dispose() {
    teardownConnection();
    _connController.close();
    _telemetryController.close();
    _matchStateController.close();
  }
}

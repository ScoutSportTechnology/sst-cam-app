import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/device.dart';
import '../camera/camera_state.dart' show activeCameraIdProvider;
import '../../core/ble/ble_providers.dart';
import '../../core/ble/ble_service.dart';
import '../../core/state/connect_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/indicators.dart';
import '../../core/widgets/wf_button.dart';
import '../../core/widgets/wf_card.dart';

/// Scan & connect flow. Reachable from Settings → "Connect a different camera".
class DiscoveryPage extends ConsumerStatefulWidget {
  const DiscoveryPage({super.key});

  @override
  ConsumerState<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends ConsumerState<DiscoveryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScan();
    });
  }

  /// Kick off a scan and surface any failure to the user. Both call sites are
  /// fire-and-forget, so without these catches the throw lands in an unawaited
  /// Future and the screen silently sits on "Idle":
  /// - StateError → BLUETOOTH_SCAN/CONNECT permission denied.
  /// - PlatformException("Bluetooth must be turned on") → adapter off. That one
  ///   is handled by the persistent "Bluetooth is off" banner (with an Enable
  ///   button), so we suppress the redundant snackbar for it.
  Future<void> _startScan() async {
    try {
      await ref.read(bleServiceProvider).startScan();
    } on StateError catch (e) {
      _showScanError(e.message);
    } catch (e) {
      final btOff = ref.read(bluetoothOnProvider).valueOrNull == false;
      if (!btOff) _showScanError('Scan failed. $e');
    }
    if (mounted) setState(() {});
  }

  void _showScanError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Persistent prompt shown while the Bluetooth adapter is off — scanning can't
  /// start without it. "Enable" asks the OS to turn it on (Android system
  /// prompt); the scan auto-resumes via the `bluetoothOnProvider` listener.
  Widget _bluetoothOffBanner() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: WfCard(
      child: Row(
        children: [
          const Icon(Icons.bluetooth_disabled, color: T.warn, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bluetooth is off',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: T.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Turn on Bluetooth to find your camera.',
                  style: TextStyle(fontSize: 12, color: T.ink2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          WfButton(
            label: 'Enable',
            size: WfButtonSize.sm,
            variant: WfButtonVariant.primary,
            onPressed: () => ref.read(bleServiceProvider).requestBluetoothOn(),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(discoveredDevicesProvider).valueOrNull ?? [];
    final scanning = ref.watch(bleServiceProvider).isScanning;
    // Default true so a not-yet-resolved adapter state doesn't flash the banner.
    final btOn = ref.watch(bluetoothOnProvider).valueOrNull ?? true;
    // Auto-resume scanning the moment the user turns Bluetooth back on.
    ref.listen(bluetoothOnProvider, (prev, next) {
      if (next.valueOrNull == true && (prev?.valueOrNull ?? true) == false) {
        _startScan();
      }
    });

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(title: const Text('Connect a camera')),
      body: ListView(
        children: [
          if (!btOn) _bluetoothOffBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            child: Row(
              children: [
                _ScanIndicator(active: scanning),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scanning ? 'Scanning for cameras' : 'Idle',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: T.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Filter: sst-cam-*',
                        style: TextStyle(
                          fontSize: 11,
                          color: T.ink2,
                          fontFamily: T.mono,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    if (scanning) {
                      ref.read(bleServiceProvider).stopScan();
                      setState(() {});
                    } else {
                      _startScan();
                    }
                  },
                  child: Text(scanning ? 'Stop' : 'Scan'),
                ),
              ],
            ),
          ),
          const WfSection('Found nearby'),
          if (devices.isEmpty && !scanning)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: WfNote('No cameras found yet')),
            ),
          ...devices.map((d) => _DeviceRow(device: d)),
          const WfSection('Help'),
          const Padding(
            padding: EdgeInsets.all(16),
            child: WfCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Can't see your camera?",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: T.ink,
                    ),
                  ),
                  SizedBox(height: 6),
                  WfNote('• Power on the Jetson and wait ~10s for advertising'),
                  WfNote('• Check Bluetooth permission for this app'),
                  WfNote('• Stay within ~10 m line-of-sight'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanIndicator extends StatefulWidget {
  const _ScanIndicator({required this.active});
  final bool active;

  @override
  State<_ScanIndicator> createState() => _ScanIndicatorState();
}

class _ScanIndicatorState extends State<_ScanIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctl,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.active ? T.accent : T.hair,
            width: 2,
          ),
        ),
        foregroundDecoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              widget.active ? T.accent : T.hair,
              Colors.transparent,
              Colors.transparent,
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceRow extends ConsumerWidget {
  const _DeviceRow({required this.device});
  final SstDevice device;

  /// Connect via the universal handshake (protocol gate → time push →
  /// snapshot → rehydrate → reconcile — see ConnectController), and surface a
  /// real, actionable error (with Retry) on failure. The controller owns the
  /// success side effects (active-camera id, last-connected persistence) and
  /// selection adoption from the firmware snapshot. Extracted so the error
  /// sheet's Retry button can re-run the exact same flow.
  Future<void> _attemptConnect(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(connectControllerProvider).connect(device.id);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) _showConnectErrorSheet(context, ref, e);
    }
  }

  /// Maps a connect exception to a human-readable, actionable reason instead of
  /// a generic "Connection failed". The impl throws descriptive exceptions; the
  /// old SnackBar discarded them entirely.
  String _humanConnectError(Object error) => switch (error) {
    BleProtocolVersionException(:final actual, :final expected) =>
      'Firmware protocol version $actual is incompatible with this app '
          '(expects $expected). Update the app or camera firmware.',
    BleHandshakeException(:final message) =>
      'Connected, but syncing camera state failed ($message). Try again.',
    BleConnectionException(:final message) => message,
    BleTimeoutException(:final message) => message,
    _ => error.toString(),
  };

  void _showConnectErrorSheet(
    BuildContext context,
    WidgetRef ref,
    Object error,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(16),
        child: WfCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 18, color: T.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Couldn't connect to ${device.name}",
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: T.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _humanConnectError(error),
                style: const TextStyle(fontSize: 12, color: T.ink2),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: WfButton(
                      label: 'Dismiss',
                      variant: WfButtonVariant.outline,
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: WfButton(
                      label: 'Retry',
                      variant: WfButtonVariant.primary,
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _attemptConnect(context, ref);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState =
        ref.watch(connectionStateProvider(device.id)).valueOrNull ??
        CameraConnectionState.disconnected;
    final connected = connState == CameraConnectionState.connected;
    // The handshake (reconciling) is still "connecting" as far as this row is
    // concerned — keep the spinner until the device is actually usable.
    final connecting =
        connState == CameraConnectionState.connecting ||
        connState == CameraConnectionState.reconciling;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const Border(
        bottom: BorderSide(color: T.rule),
      ).toBoxDecoration(),
      child: Row(
        children: [
          const SignalIndicator(bars: 4, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: T.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${device.model} · fw ${device.firmwareVersion}',
                  style: const TextStyle(fontSize: 11, color: T.ink2),
                ),
              ],
            ),
          ),
          if (connecting)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(T.accent),
              ),
            )
          else
            WfButton(
              label: connected ? 'Disconnect' : 'Connect',
              variant: connected
                  ? WfButtonVariant.outline
                  : WfButtonVariant.primary,
              size: WfButtonSize.sm,
              onPressed: () async {
                final svc = ref.read(bleServiceProvider);
                if (connected) {
                  await svc.disconnect(device.id);
                  ref.read(activeCameraIdProvider.notifier).state = null;
                } else {
                  await _attemptConnect(context, ref);
                }
              },
            ),
        ],
      ),
    );
  }
}

extension on Border {
  BoxDecoration toBoxDecoration() => BoxDecoration(border: this);
}

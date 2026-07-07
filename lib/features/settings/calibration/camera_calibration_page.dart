import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ble/ble_providers.dart';
import '../../../core/models/command.dart' show CameraFocusMode;
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/live_preview_view.dart';
import '../../../core/widgets/wf_button.dart';
import '../../../core/widgets/wf_card.dart';
import '../../../core/wifi/wifi_providers.dart' show livePreviewEnabledProvider;
import '../../camera/camera_state.dart'
    show activeCameraIdProvider, modalPreviewActiveProvider;

/// Diagnostic → Calibration → Camera: tune the postprocessor white-balance gains
/// against the live preview to neutralize the IMX477 magenta cast.
/// Slider drags are debounced and pushed to the firmware live (it applies them on
/// the next frame and logs the values so a dialed-in setting can be persisted as
/// the shipping default). Gains multiply the BGR channels; 1.0 = identity.
class CameraCalibrationPage extends ConsumerStatefulWidget {
  const CameraCalibrationPage({super.key});

  @override
  ConsumerState<CameraCalibrationPage> createState() =>
      _CameraCalibrationPageState();
}

class _CameraCalibrationPageState extends ConsumerState<CameraCalibrationPage> {
  // Seeded at the firmware's shipping defaults so the sliders reflect what the
  // camera is already applying (dialed in on-device against the RBPCV3 IMX477).
  double _r = 0.86;
  double _g = 0.94;
  double _b = 0.84;
  double _saturation = 1.10;
  double _contrast = 1.20;
  double _brightness = -0.05;
  bool _enabled = true;
  Timer? _debounce;

  // Focus (U8/U9). (Output-camera / manual tracking lives next to the live
  // preview on the camera + match screens, not here.)
  //
  // Intent vs observed (per the settings-toggle learning): [_afRequested] is
  // what the user last asked for; [_afEffective] is the EFFECTIVE mode echoed
  // by the firmware's CameraFocusResponse. The toggle displays the echo once
  // one exists — never the request. Seeded at the firmware default (manual,
  // no echo yet).
  CameraFocusMode _afRequested = CameraFocusMode.manual; // intent
  CameraFocusMode? _afEffective; // observed (null until first echo)
  bool _afAvailable = true; // observed; false = fixed lens, no VCM motor
  double _focus = 320;
  Timer? _focusDebounce;

  /// Captured in initState so dispose() can release the modal-preview claim
  /// without touching `ref` (riverpod forbids ref use once the element is
  /// unmounting — reading it there throws and skips the rest of dispose,
  /// leaving the claim stuck and the hero/match previews paused).
  StateController<bool>? _modalClaim;

  /// What the toggle shows: the observed effective mode when the firmware has
  /// echoed one, else the pending intent.
  bool get _afDisplayedAuto =>
      (_afEffective ?? _afRequested) == CameraFocusMode.auto;

  @override
  void initState() {
    super.initState();
    // Just enable the live preview in whatever layout is already active — the
    // magenta cast is module-uniform, so a single-camera preview is a sufficient
    // reference. Forcing a layout switch here renegotiates the RTSP pipeline
    // mid-startup and the player loops on "reconnecting".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Claim the sole preview client: this screen is pushed over the tab shell,
      // whose hero/match previews stay mounted and would otherwise keep a second
      // RTSP client open (starving this one on the single-stream server).
      final claim = ref.read(modalPreviewActiveProvider.notifier);
      claim.state = true;
      _modalClaim = claim;
      final id = ref.read(activeCameraIdProvider);
      if (id == null) return;
      ref.read(livePreviewEnabledProvider(id).notifier).state = true;
    });
  }

  @override
  void dispose() {
    // Release the claim so the hero/match previews resume (via the captured
    // controller — `ref` is unusable during unmount).
    _modalClaim?.state = false;
    _debounce?.cancel();
    _focusDebounce?.cancel();
    super.dispose();
  }

  /// AF mode toggle (U9). Blocked when no camera is connected (the whole page
  /// body is already gated on connection); otherwise awaits the firmware echo
  /// — no fire-and-forget — and renders the EFFECTIVE mode it reports, which
  /// may differ from the request.
  Future<void> _setAfMode(bool auto) async {
    final id = ref.read(activeCameraIdProvider);
    if (id == null) return; // standard disconnected affordance covers the page
    final requested = auto ? CameraFocusMode.auto : CameraFocusMode.manual;
    _focusDebounce?.cancel();
    setState(() => _afRequested = requested);
    try {
      final echo = await ref
          .read(bleServiceProvider)
          .setCameraFocus(
            id,
            mode: requested,
            position: requested == CameraFocusMode.manual
                ? _focus.round()
                : null,
          );
      if (!mounted || echo == null) return;
      setState(() {
        _afEffective = echo.mode; // observed — wins over the request
        _afAvailable = echo.autofocusAvailable;
      });
    } catch (_) {
      if (!mounted) return;
      // Roll intent back to the last observed state so the toggle doesn't
      // claim a mode the camera never acknowledged.
      setState(() => _afRequested = _afEffective ?? CameraFocusMode.manual);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Focus mode change failed')));
    }
  }

  /// Manual-position drags — debounced like the color sliders; the echo still
  /// refreshes the observed mode/availability.
  void _pushFocus() {
    final id = ref.read(activeCameraIdProvider);
    if (id == null) return;
    _focusDebounce?.cancel();
    _focusDebounce = Timer(const Duration(milliseconds: 120), () async {
      try {
        final echo = await ref
            .read(bleServiceProvider)
            .setCameraFocus(
              id,
              mode: CameraFocusMode.manual,
              position: _focus.round(),
            );
        if (!mounted || echo == null) return;
        setState(() {
          _afEffective = echo.mode;
          _afAvailable = echo.autofocusAvailable;
        });
      } catch (_) {
        // Drag path stays quiet — the next drag retries; the mode toggle is
        // the surface that reports errors.
      }
    });
  }

  void _push() {
    final id = ref.read(activeCameraIdProvider);
    if (id == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      ref
          .read(bleServiceProvider)
          .setCameraCalibration(
            id,
            rGain: _r,
            gGain: _g,
            bGain: _b,
            enabled: _enabled,
            saturation: _saturation,
            contrast: _contrast,
            brightness: _brightness,
          )
          .ignore();
    });
  }

  void _reset() {
    setState(() {
      _r = 1.0;
      _g = 1.0;
      _b = 1.0;
      _saturation = 1.0;
      _contrast = 1.0;
      _brightness = 0.0;
    });
    _push();
  }

  Future<void> _autoWhiteBalance() async {
    final id = ref.read(activeCameraIdProvider);
    if (id == null) return;
    try {
      final result = await ref.read(bleServiceProvider).autoWhiteBalance(id);
      if (result != null && mounted) {
        setState(() {
          _r = result.rGain.clamp(0.3, 1.7);
          _g = result.gGain.clamp(0.3, 1.7);
          _b = result.bGain.clamp(0.3, 1.7);
          _enabled = result.enabled;
          // Auto-WB preserves these; reflect what the camera reports back.
          _saturation = result.saturation.clamp(0.0, 2.0);
          _contrast = result.contrast.clamp(0.5, 2.0);
          _brightness = result.brightness.clamp(-0.5, 0.5);
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Auto white-balance failed')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = ref.watch(activeCameraIdProvider);
    final connected = id != null;

    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        title: const Text('Camera calibration'),
        backgroundColor: T.bg,
      ),
      body: !connected
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Connect to a camera to calibrate its color.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                // Full-width live preview — same presentation as the camera hero
                // card (no aspect override), so it's large enough to judge colour.
                // No autoStart: the orchestrator already owns the WiFi-Direct
                // group (the preview was on before we got here). autoStart calls
                // connectGroup() directly, which fights the orchestrator and
                // cycles the group → stuck on "RECONNECTING…". We just attach to
                // the existing stream.
                LivePreviewView(
                  deviceId: id,
                  label: 'Live preview',
                  showButtons: false,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      WfCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'White balance',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Switch(
                                  value: _enabled,
                                  onChanged: (v) {
                                    setState(() => _enabled = v);
                                    _push();
                                  },
                                ),
                              ],
                            ),
                            const WfNote(
                              'Point the camera at a white or grey surface and tap '
                              'Auto to set white balance + saturation/contrast/'
                              'brightness, then fine-tune below. 1.00 = no change.',
                            ),
                            const SizedBox(height: 10),
                            WfButton(
                              label: 'Auto color',
                              variant: WfButtonVariant.primary,
                              full: true,
                              leading: const Icon(
                                Icons.auto_fix_high_rounded,
                                size: 15,
                                color: T.accentInk,
                              ),
                              onPressed: _enabled ? _autoWhiteBalance : null,
                            ),
                            const SizedBox(height: 8),
                            _GainSlider(
                              label: 'Red',
                              color: T.channelRed,
                              value: _r,
                              enabled: _enabled,
                              onChanged: (v) {
                                setState(() => _r = v);
                                _push();
                              },
                            ),
                            _GainSlider(
                              label: 'Green',
                              color: T.channelGreen,
                              value: _g,
                              enabled: _enabled,
                              onChanged: (v) {
                                setState(() => _g = v);
                                _push();
                              },
                            ),
                            _GainSlider(
                              label: 'Blue',
                              color: T.channelBlue,
                              value: _b,
                              enabled: _enabled,
                              onChanged: (v) {
                                setState(() => _b = v);
                                _push();
                              },
                            ),
                            const Divider(height: 18, color: T.rule),
                            _GainSlider(
                              label: 'Saturation',
                              color: T.ink,
                              value: _saturation,
                              min: 0.0,
                              max: 2.0,
                              enabled: _enabled,
                              onChanged: (v) {
                                setState(() => _saturation = v);
                                _push();
                              },
                            ),
                            _GainSlider(
                              label: 'Contrast',
                              color: T.ink,
                              value: _contrast,
                              min: 0.5,
                              max: 2.0,
                              enabled: _enabled,
                              onChanged: (v) {
                                setState(() => _contrast = v);
                                _push();
                              },
                            ),
                            _GainSlider(
                              label: 'Brightness',
                              color: T.ink,
                              value: _brightness,
                              min: -0.5,
                              max: 0.5,
                              enabled: _enabled,
                              onChanged: (v) {
                                setState(() => _brightness = v);
                                _push();
                              },
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerRight,
                              child: WfButton(
                                label: 'Reset to 1.00',
                                variant: WfButtonVariant.text,
                                size: WfButtonSize.sm,
                                onPressed: _enabled ? _reset : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Focus (U8/U9) — motorized VCM lens. The toggle shows
                      // the firmware-echoed EFFECTIVE mode; a fixed lens
                      // (autofocus_available=false) disables it.
                      WfCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Autofocus',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Switch(
                                  value: _afDisplayedAuto,
                                  onChanged: _afAvailable
                                      ? (v) => _setAfMode(v)
                                      : null,
                                ),
                              ],
                            ),
                            WfNote(
                              !_afAvailable
                                  ? 'Fixed lens — this camera has no '
                                        'motorized focus.'
                                  : _afDisplayedAuto
                                  ? 'Continuous autofocus is on. Autofocus '
                                        'pauses while recording.'
                                  : 'Manual focus — drag to set both lenses '
                                        '(0 = near, 1000 = far).',
                            ),
                            const SizedBox(height: 4),
                            _GainSlider(
                              label: 'Focus',
                              color: T.accent,
                              value: _focus,
                              min: 0,
                              max: 1000,
                              enabled: _afAvailable && !_afDisplayedAuto,
                              onChanged: (v) {
                                setState(() => _focus = v);
                                _pushFocus();
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const WfNote(
                        'The camera logs the applied gains — read them from the '
                        'console to bake a tuned setting as the saved default.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _GainSlider extends StatelessWidget {
  const _GainSlider({
    required this.label,
    required this.color,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.min = 0.3,
    this.max = 1.7,
  });

  final String label;
  final Color color;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) * 100).round(),
            activeColor: color,
            label: value.toStringAsFixed(2),
            onChanged: enabled ? onChanged : null,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: const TextStyle(fontFamily: T.mono, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

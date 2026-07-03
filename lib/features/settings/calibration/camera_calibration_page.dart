import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ble/ble_providers.dart';
import '../../../core/models/preview_layout.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/live_preview_view.dart';
import '../../../core/widgets/wf_card.dart';
import '../../../core/wifi/wifi_providers.dart' show livePreviewEnabledProvider;
import '../../camera/camera_state.dart' show activeCameraIdProvider;

/// Diagnostic → Calibration → Camera: tune the postprocessor white-balance gains
/// against the live both-camera preview to neutralize the IMX477 magenta cast.
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
  // Seeded at the firmware's shipping default (mild magenta correction) so the
  // sliders reflect what the camera is already applying.
  double _r = 0.82;
  double _g = 1.0;
  double _b = 0.84;
  bool _enabled = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Force the both-camera layout so tuning is verified on both sensors at once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = ref.read(activeCameraIdProvider);
      if (id == null) return;
      ref.read(livePreviewEnabledProvider(id).notifier).state = true;
      ref
          .read(bleServiceProvider)
          .setPreviewLayout(id, PreviewLayout.sideBySide)
          .ignore();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
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
          )
          .ignore();
    });
  }

  void _reset() {
    setState(() {
      _r = 1.0;
      _g = 1.0;
      _b = 1.0;
    });
    _push();
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
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Both-camera live preview — the reference for tuning.
                LivePreviewView(
                  deviceId: id,
                  label: 'Both cameras',
                  aspect: 32 / 9,
                  autoStart: true,
                  showButtons: false,
                ),
                const SizedBox(height: 12),
                WfCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'White balance',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
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
                      Text(
                        'Drag until the preview looks neutral (no pink / green '
                        'tint). 1.00 = no change.',
                        style: TextStyle(color: T.ink2, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      _GainSlider(
                        label: 'Red',
                        color: const Color(0xFFE0564E),
                        value: _r,
                        enabled: _enabled,
                        onChanged: (v) {
                          setState(() => _r = v);
                          _push();
                        },
                      ),
                      _GainSlider(
                        label: 'Green',
                        color: const Color(0xFF4FAF5A),
                        value: _g,
                        enabled: _enabled,
                        onChanged: (v) {
                          setState(() => _g = v);
                          _push();
                        },
                      ),
                      _GainSlider(
                        label: 'Blue',
                        color: const Color(0xFF4E7BE0),
                        value: _b,
                        enabled: _enabled,
                        onChanged: (v) {
                          setState(() => _b = v);
                          _push();
                        },
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _enabled ? _reset : null,
                          child: const Text('Reset to 1.00'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'The camera logs the applied gains — read them from the console '
                  'to bake a tuned setting as the saved default.',
                  style: TextStyle(color: T.ink2, fontSize: 11),
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
  });

  final String label;
  final Color color;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0.3,
            max: 1.7,
            divisions: 140,
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
            style: const TextStyle(fontFeatures: [], fontSize: 12),
          ),
        ),
      ],
    );
  }
}

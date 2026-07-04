// resetSelectionOnConnect mirrors the firmware's session reset: the firmware
// clears its session-scoped selections (active output camera → 0, preview layout
// → single) on every BLE disconnect, so a reconnect starts fresh. The app's
// selection providers outlive a reconnect, so the connect flow calls this to
// reset them — otherwise the UI keeps showing the previous session's camera
// while the firmware serves camera 0.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/models/preview_layout.dart';
import 'package:sst_cam_app/core/state/selection_sync.dart';
import 'package:sst_cam_app/core/wifi/wifi_providers.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart';

const _id = 'cam-1';

/// Pump a bare Consumer and hand back its WidgetRef so the helper (which takes a
/// WidgetRef) can be exercised against a real ProviderScope.
Future<WidgetRef> _ref(WidgetTester tester) async {
  late WidgetRef captured;
  await tester.pumpWidget(
    ProviderScope(
      child: Consumer(
        builder: (_, ref, _) {
          captured = ref;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  testWidgets('resets a Right / side-by-side selection to 0 / single', (
    tester,
  ) async {
    final ref = await _ref(tester);

    ref.read(activeOutputCameraProvider.notifier).state = 1;
    ref.read(previewLayoutProvider(_id).notifier).state =
        PreviewLayout.sideBySide;

    resetSelectionOnConnect(ref, _id);

    expect(ref.read(activeOutputCameraProvider), 0);
    expect(ref.read(previewLayoutProvider(_id)), PreviewLayout.single);
  });

  testWidgets('idempotent when already at defaults', (tester) async {
    final ref = await _ref(tester);

    resetSelectionOnConnect(ref, _id);

    expect(ref.read(activeOutputCameraProvider), 0);
    expect(ref.read(previewLayoutProvider(_id)), PreviewLayout.single);
  });
}

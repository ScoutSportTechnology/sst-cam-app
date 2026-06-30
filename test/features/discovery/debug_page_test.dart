// U3 — redesigned database browser. Verifies it renders seeded data with the
// design-system vocabulary and shows an empty-state note (no crash) for an
// empty table. Behaviour (4-tab inspect + reset) is unchanged from the rewrite.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/widgets/wf_button.dart';
import 'package:sst_cam_app/features/discovery/debug_page.dart';

import '../../test_helpers.dart';

void main() {
  final db = useInMemoryDb();

  testWidgets('renders seeded rows with redesigned chrome', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: dbOverrides(db),
        child: const MaterialApp(home: DebugPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Database'), findsOneWidget);
    // Reset uses the design-system danger button, not a raw red FilledButton.
    expect(find.widgetWithText(WfButton, 'Reset database'), findsOneWidget);
    // Default Users tab — 2 seeded users → row-count header.
    expect(find.text('2 rows'), findsOneWidget);
  });

  testWidgets('empty table shows a note, not a crash', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: dbOverrides(db),
        child: const MaterialApp(home: DebugPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Clips are empty in the canonical seed.
    await tester.tap(find.text('Clips'));
    await tester.pumpAndSettle();
    expect(find.text('No clips'), findsOneWidget);
  });
}

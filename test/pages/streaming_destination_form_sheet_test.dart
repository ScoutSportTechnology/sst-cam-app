// U9 — `streaming_destination_form_sheet` tests.
//
// Covers AE6 / AE7 / AE8 plus the sensitive-field treatment (obscureText +
// visibility toggle, enableSuggestions / autocorrect off), default-name
// behavior, validation, edit-mode prefill, and trim semantics.
//
// Pumping pattern: harness boots a `Builder` whose only role is to expose
// a `BuildContext` from which `showStreamingDestinationFormSheet` is
// triggered (via tapping the "open sheet" button). The test captures the
// returned future to assert the eventual draft (or null on cancel).
//
// Keys: TextField widgets carry explicit `Key('streaming-X-field')` so we
// can find them deterministically and read `obscureText` /
// `enableSuggestions` / `autocorrect` off the widget.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/models/streaming.dart';
import 'package:sst_cam_app/pages/streaming_destination_form_sheet.dart';

const _kNameKey = Key('streaming-name-field');
const _kUrlKey = Key('streaming-url-field');
const _kStreamKeyKey = Key('streaming-key-field');
const _kUsernameKey = Key('streaming-username-field');
const _kPasswordKey = Key('streaming-password-field');

/// Captures the future returned by `showStreamingDestinationFormSheet` so
/// tests can assert the eventual draft (or null on cancel) after they've
/// driven the form to a terminal state.
class _SheetHarness {
  Future<StreamingDestinationDraft?>? future;
}

/// Pumps a harness with an "Open sheet" button. Tapping the button calls
/// `showStreamingDestinationFormSheet` with the provided `existing` and
/// stores the returned Future on the harness.
Future<_SheetHarness> _openSheet(
  WidgetTester tester, {
  StreamingDestination? existing,
}) async {
  final harness = _SheetHarness();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () {
                harness.future = showStreamingDestinationFormSheet(
                  ctx,
                  existing: existing,
                );
              },
              child: const Text('open sheet'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open sheet'));
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  testWidgets('AE6: known provider (YouTube) hides the protocol picker '
      'and renders only Name / URL / Stream key fields', (tester) async {
    await _openSheet(tester);

    // YouTube is the default provider. Provider picker shows all 5 chips,
    // but the protocol picker is NOT in the tree.
    expect(find.text('YouTube'), findsAtLeastNWidgets(1));
    expect(find.text('PROTOCOL'), findsNothing);
    // Protocol-label chips that would appear in the picker are absent.
    expect(find.text('RTMPS'), findsNothing);
    expect(find.text('RTSP'), findsNothing);

    // Visible fields: Name, URL, Stream key. Username and Password are
    // NOT in the tree.
    expect(find.byKey(_kNameKey), findsOneWidget);
    expect(find.byKey(_kUrlKey), findsOneWidget);
    expect(find.byKey(_kStreamKeyKey), findsOneWidget);
    expect(find.byKey(_kUsernameKey), findsNothing);
    expect(find.byKey(_kPasswordKey), findsNothing);
  });

  testWidgets('AE7: Custom + RTSP renders Username/Password but not Stream '
      'key; switching to RTMP rebuilds the form (Stream key reappears, '
      'Username/Password disappear)', (tester) async {
    await _openSheet(tester);

    // Switch provider to Custom.
    await tester.tap(find.text('Custom').first);
    await tester.pumpAndSettle();

    // Protocol picker is now visible.
    expect(find.text('PROTOCOL'), findsOneWidget);

    // Switch protocol to RTSP.
    await tester.tap(find.text('RTSP').first);
    await tester.pumpAndSettle();

    expect(find.byKey(_kNameKey), findsOneWidget);
    expect(find.byKey(_kUrlKey), findsOneWidget);
    expect(find.byKey(_kUsernameKey), findsOneWidget);
    expect(find.byKey(_kPasswordKey), findsOneWidget);
    expect(find.byKey(_kStreamKeyKey), findsNothing);

    // Switch to RTMP — Stream key reappears, Username/Password disappear.
    await tester.tap(find.text('RTMP').first);
    await tester.pumpAndSettle();

    expect(find.byKey(_kStreamKeyKey), findsOneWidget);
    expect(find.byKey(_kUsernameKey), findsNothing);
    expect(find.byKey(_kPasswordKey), findsNothing);
  });

  testWidgets('AE8: URL scheme validation — RTMP with https:// URL shows '
      'inline error and does not return a draft', (tester) async {
    final harness = await _openSheet(tester);

    // Default is YouTube + RTMP. Type a non-rtmp URL and try to save.
    await tester.enterText(find.byKey(_kUrlKey), 'https://example.com/x');
    await tester.enterText(find.byKey(_kStreamKeyKey), 'somekey');
    await tester.tap(find.text('Add destination').last);
    await tester.pumpAndSettle();

    // Inline error is rendered.
    expect(find.textContaining('must start with rtmp://'), findsOneWidget);
    // Sheet still on screen — submit didn't pop.
    expect(find.byKey(_kUrlKey), findsOneWidget);

    // Cancel to settle the future and check it's null.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await harness.future, isNull);
  });

  testWidgets('Stream key field uses obscureText: true initially; '
      'visibility toggle flips it', (tester) async {
    await _openSheet(tester);

    // Default YouTube + RTMP — Stream key visible.
    expect(
      tester.widget<TextField>(find.byKey(_kStreamKeyKey)).obscureText,
      isTrue,
    );

    // Tap visibility toggle (the IconButton next to the Stream key field).
    await tester.tap(find.byIcon(Icons.visibility_outlined).first);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byKey(_kStreamKeyKey)).obscureText,
      isFalse,
    );
  });

  testWidgets('RTSP password field uses obscureText: true initially; '
      'visibility toggle flips it', (tester) async {
    await _openSheet(tester);

    // Switch to Custom + RTSP.
    await tester.tap(find.text('Custom').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('RTSP').first);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byKey(_kPasswordKey)).obscureText,
      isTrue,
    );

    // Tap the password's visibility toggle. The Username field has no
    // toggle; only the Password row does, so a single visibility icon is
    // present in the tree.
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byKey(_kPasswordKey)).obscureText,
      isFalse,
    );
  });

  testWidgets('Stream key, Username, and Password all have '
      'enableSuggestions == false and autocorrect == false', (tester) async {
    // First check the Stream key with default YouTube + RTMP.
    await _openSheet(tester);

    final keyField = tester.widget<TextField>(find.byKey(_kStreamKeyKey));
    expect(keyField.enableSuggestions, isFalse);
    expect(keyField.autocorrect, isFalse);

    // Now switch to Custom + RTSP and check Username + Password.
    await tester.tap(find.text('Custom').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('RTSP').first);
    await tester.pumpAndSettle();

    final userField = tester.widget<TextField>(find.byKey(_kUsernameKey));
    expect(userField.enableSuggestions, isFalse);
    expect(userField.autocorrect, isFalse);

    final passField = tester.widget<TextField>(find.byKey(_kPasswordKey));
    expect(passField.enableSuggestions, isFalse);
    expect(passField.autocorrect, isFalse);
  });

  testWidgets('Default name from provider — switching YouTube → TikTok '
      'updates the Name field when the user has not typed a custom name', (
    tester,
  ) async {
    await _openSheet(tester);

    // Default name is "YouTube".
    expect(
      tester.widget<TextField>(find.byKey(_kNameKey)).controller!.text,
      'YouTube',
    );

    // Tap TikTok provider chip.
    await tester.tap(find.text('TikTok').first);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byKey(_kNameKey)).controller!.text,
      'TikTok',
    );
  });

  testWidgets('Empty Name with provider = Custom is rejected with '
      '"Destination name is required" inline error', (tester) async {
    await _openSheet(tester);

    // Switch to Custom — default name was YouTube, but the form swaps it
    // to '' for Custom because Custom's default name is empty.
    await tester.tap(find.text('Custom').first);
    await tester.pumpAndSettle();

    // Name is now empty.
    expect(
      tester.widget<TextField>(find.byKey(_kNameKey)).controller!.text,
      '',
    );

    // Type a valid URL + Stream key, then tap Save.
    await tester.enterText(
      find.byKey(_kUrlKey),
      'rtmp://server.example.com/path',
    );
    await tester.enterText(find.byKey(_kStreamKeyKey), 'abc');
    await tester.tap(find.text('Add destination').last);
    await tester.pumpAndSettle();

    expect(find.text('Destination name is required'), findsOneWidget);
  });

  testWidgets('Trailing whitespace trimmed in returned draft', (tester) async {
    final harness = await _openSheet(tester);

    // Default YouTube + RTMP.
    await tester.enterText(
      find.byKey(_kUrlKey),
      '  rtmp://server.example.com/path  ',
    );
    await tester.enterText(find.byKey(_kStreamKeyKey), '  somekey  ');
    await tester.tap(find.text('Add destination').last);
    await tester.pumpAndSettle();

    final draft = await harness.future;
    expect(draft, isNotNull);
    expect(draft!.name, 'YouTube');
    expect(draft.provider, StreamingProvider.youtube);
    expect(draft.protocol, StreamingProtocol.rtmp);
    final cfg = draft.config as RtmpConfig;
    expect(cfg.url, 'rtmp://server.example.com/path');
    expect(cfg.streamKey, 'somekey');
  });

  testWidgets('Edit mode — RtmpConfig prefill: Name, URL, Stream key all '
      'show the existing values', (tester) async {
    const existing = StreamingDestination(
      id: 'dest-1',
      name: 'My YT',
      provider: StreamingProvider.youtube,
      protocol: StreamingProtocol.rtmp,
      config: RtmpConfig(
        url: 'rtmp://a.rtmp.youtube.com/live2',
        streamKey: 'YT-secret',
      ),
    );
    await _openSheet(tester, existing: existing);

    expect(
      tester.widget<TextField>(find.byKey(_kNameKey)).controller!.text,
      'My YT',
    );
    expect(
      tester.widget<TextField>(find.byKey(_kUrlKey)).controller!.text,
      'rtmp://a.rtmp.youtube.com/live2',
    );
    expect(
      tester.widget<TextField>(find.byKey(_kStreamKeyKey)).controller!.text,
      'YT-secret',
    );
    // Sheet is in edit mode — title is "Edit destination".
    expect(find.text('Edit destination'), findsOneWidget);
    // Save button is "Save" not "Add destination".
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('Edit mode — RTSP prefill with username only: both fields '
      'render; only Username has a non-empty value', (tester) async {
    const existing = StreamingDestination(
      id: 'dest-2',
      name: 'Backyard cam',
      provider: StreamingProvider.custom,
      protocol: StreamingProtocol.rtsp,
      config: RtspConfig(url: 'rtsp://192.168.1.50/stream', username: 'admin'),
    );
    await _openSheet(tester, existing: existing);

    // Both username and password fields render.
    expect(find.byKey(_kUsernameKey), findsOneWidget);
    expect(find.byKey(_kPasswordKey), findsOneWidget);

    expect(
      tester.widget<TextField>(find.byKey(_kUsernameKey)).controller!.text,
      'admin',
    );
    expect(
      tester.widget<TextField>(find.byKey(_kPasswordKey)).controller!.text,
      '',
    );
    expect(
      tester.widget<TextField>(find.byKey(_kUrlKey)).controller!.text,
      'rtsp://192.168.1.50/stream',
    );
  });
}

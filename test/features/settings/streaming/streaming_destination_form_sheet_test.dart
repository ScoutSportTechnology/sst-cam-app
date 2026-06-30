// streaming_destination_form_sheet tests — custom-RTMP-only form (U5/R18).
//
// The per-platform provider picker (YouTube/TikTok/Facebook/Instagram) was
// removed; the form is now custom-only with a PROTOCOL picker (RTMP/RTMPS/RTSP).
// Covers field rendering per protocol, URL-scheme validation, sensitive-field
// treatment, name-required, trim semantics, and edit-mode prefill.
//
// Keys: TextField widgets carry explicit Key('streaming-X-field').

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/models/streaming.dart';
import 'package:sst_cam_app/features/settings/streaming/streaming_destination_form_sheet.dart';

const _kNameKey = Key('streaming-name-field');
const _kUrlKey = Key('streaming-url-field');
const _kStreamKeyKey = Key('streaming-key-field');
const _kUsernameKey = Key('streaming-username-field');
const _kPasswordKey = Key('streaming-password-field');

class _SheetHarness {
  Future<StreamingDestinationDraft?>? future;
}

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
  testWidgets('custom-only: no provider picker; PROTOCOL picker + RTMP fields '
      'visible by default', (tester) async {
    await _openSheet(tester);

    // Per-platform providers are gone.
    expect(find.text('PROVIDER'), findsNothing);
    expect(find.text('YouTube'), findsNothing);
    expect(find.text('TikTok'), findsNothing);
    expect(find.text('Instagram'), findsNothing);

    // Protocol picker is present (custom is the only mode now).
    expect(find.text('PROTOCOL'), findsOneWidget);
    expect(find.text('RTMP'), findsAtLeastNWidgets(1));
    expect(find.text('RTMPS'), findsAtLeastNWidgets(1));
    expect(find.text('RTSP'), findsAtLeastNWidgets(1));

    // Default protocol RTMP → Name / URL / Stream key; no Username/Password.
    expect(find.byKey(_kNameKey), findsOneWidget);
    expect(find.byKey(_kUrlKey), findsOneWidget);
    expect(find.byKey(_kStreamKeyKey), findsOneWidget);
    expect(find.byKey(_kUsernameKey), findsNothing);
    expect(find.byKey(_kPasswordKey), findsNothing);
  });

  testWidgets('RTSP renders Username/Password not Stream key; back to RTMP '
      'reverses', (tester) async {
    await _openSheet(tester);

    await tester.tap(find.text('RTSP').first);
    await tester.pumpAndSettle();
    expect(find.byKey(_kUsernameKey), findsOneWidget);
    expect(find.byKey(_kPasswordKey), findsOneWidget);
    expect(find.byKey(_kStreamKeyKey), findsNothing);

    await tester.tap(find.text('RTMP').first);
    await tester.pumpAndSettle();
    expect(find.byKey(_kStreamKeyKey), findsOneWidget);
    expect(find.byKey(_kUsernameKey), findsNothing);
    expect(find.byKey(_kPasswordKey), findsNothing);
  });

  testWidgets('URL scheme validation — https:// URL shows inline error, no '
      'draft', (tester) async {
    final harness = await _openSheet(tester);

    await tester.enterText(find.byKey(_kNameKey), 'My stream');
    await tester.enterText(find.byKey(_kUrlKey), 'https://example.com/x');
    await tester.enterText(find.byKey(_kStreamKeyKey), 'somekey');
    await tester.tap(find.text('Add destination').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('must start with rtmp://'), findsOneWidget);
    expect(find.byKey(_kUrlKey), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await harness.future, isNull);
  });

  testWidgets('Stream key obscured initially; visibility toggle flips it', (
    tester,
  ) async {
    await _openSheet(tester);
    expect(
      tester.widget<TextField>(find.byKey(_kStreamKeyKey)).obscureText,
      isTrue,
    );
    await tester.tap(find.byIcon(Icons.visibility_outlined).first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(_kStreamKeyKey)).obscureText,
      isFalse,
    );
  });

  testWidgets('RTSP password obscured initially; visibility toggle flips it', (
    tester,
  ) async {
    await _openSheet(tester);
    await tester.tap(find.text('RTSP').first);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byKey(_kPasswordKey)).obscureText,
      isTrue,
    );
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byKey(_kPasswordKey)).obscureText,
      isFalse,
    );
  });

  testWidgets('sensitive fields disable suggestions + autocorrect', (
    tester,
  ) async {
    await _openSheet(tester);
    final keyField = tester.widget<TextField>(find.byKey(_kStreamKeyKey));
    expect(keyField.enableSuggestions, isFalse);
    expect(keyField.autocorrect, isFalse);

    await tester.tap(find.text('RTSP').first);
    await tester.pumpAndSettle();
    final passField = tester.widget<TextField>(find.byKey(_kPasswordKey));
    expect(passField.enableSuggestions, isFalse);
    expect(passField.autocorrect, isFalse);
  });

  testWidgets('Empty Name rejected with inline error', (tester) async {
    await _openSheet(tester);
    // Custom default name is empty.
    expect(
      tester.widget<TextField>(find.byKey(_kNameKey)).controller!.text,
      '',
    );
    await tester.enterText(
      find.byKey(_kUrlKey),
      'rtmp://server.example.com/path',
    );
    await tester.enterText(find.byKey(_kStreamKeyKey), 'abc');
    await tester.tap(find.text('Add destination').last);
    await tester.pumpAndSettle();
    expect(find.text('Destination name is required'), findsOneWidget);
  });

  testWidgets('valid submit trims and returns a custom RTMP draft', (
    tester,
  ) async {
    final harness = await _openSheet(tester);

    await tester.enterText(find.byKey(_kNameKey), '  Field cam  ');
    await tester.enterText(
      find.byKey(_kUrlKey),
      '  rtmp://server.example.com/path  ',
    );
    await tester.enterText(find.byKey(_kStreamKeyKey), '  somekey  ');
    await tester.tap(find.text('Add destination').last);
    await tester.pumpAndSettle();

    final draft = await harness.future;
    expect(draft, isNotNull);
    expect(draft!.name, 'Field cam');
    expect(draft.provider, StreamingProvider.custom);
    expect(draft.protocol, StreamingProtocol.rtmp);
    final cfg = draft.config as RtmpConfig;
    expect(cfg.url, 'rtmp://server.example.com/path');
    expect(cfg.streamKey, 'somekey');
  });

  testWidgets('Edit mode — RtmpConfig prefill', (tester) async {
    const existing = StreamingDestination(
      id: 'dest-1',
      name: 'My RTMP',
      provider: StreamingProvider.custom,
      protocol: StreamingProtocol.rtmp,
      config: RtmpConfig(
        url: 'rtmp://a.example.com/live2',
        streamKey: 'secret',
      ),
    );
    await _openSheet(tester, existing: existing);

    expect(
      tester.widget<TextField>(find.byKey(_kNameKey)).controller!.text,
      'My RTMP',
    );
    expect(
      tester.widget<TextField>(find.byKey(_kUrlKey)).controller!.text,
      'rtmp://a.example.com/live2',
    );
    expect(
      tester.widget<TextField>(find.byKey(_kStreamKeyKey)).controller!.text,
      'secret',
    );
    expect(find.text('Edit destination'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('Edit mode — RTSP prefill renders both creds fields', (
    tester,
  ) async {
    const existing = StreamingDestination(
      id: 'dest-2',
      name: 'Backyard cam',
      provider: StreamingProvider.custom,
      protocol: StreamingProtocol.rtsp,
      config: RtspConfig(url: 'rtsp://192.168.1.50/stream', username: 'admin'),
    );
    await _openSheet(tester, existing: existing);

    expect(find.byKey(_kUsernameKey), findsOneWidget);
    expect(find.byKey(_kPasswordKey), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(_kUsernameKey)).controller!.text,
      'admin',
    );
    expect(
      tester.widget<TextField>(find.byKey(_kUrlKey)).controller!.text,
      'rtsp://192.168.1.50/stream',
    );
  });
}

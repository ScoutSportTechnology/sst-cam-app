// U8 — Tests for `showUserFormSheet`.
//
// The sheet renders a single trimmed text field for the user name and
// returns a `UserDraft` (or null on cancel). On edit, the sheet prefills
// the existing name and preserves `existing.id` on the returned draft so
// the controller routes to update.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/models/user.dart';
import 'package:scout_camera/pages/user_form_sheet.dart';

void main() {
  group('showUserFormSheet — happy paths', () {
    testWidgets('non-empty trimmed name returns a UserDraft with that name '
        'and empty id', (tester) async {
      UserDraft? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    captured = await showUserFormSheet(context);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Form is open with the create-mode title.
      expect(find.text('Add user'), findsAtLeastNWidgets(1));

      // Type a name (with leading/trailing whitespace to assert trim).
      await tester.enterText(find.byType(TextField), '  Coach C  ');
      // Tap the primary submit button. The Save button label in create
      // mode is "Add user"; there's also a section title "Add user", so
      // we grab the WfButton-rendered text with last-found matcher.
      final addUserFinders = find.text('Add user');
      // The button is rendered second (after the title). Tap last.
      await tester.tap(addUserFinders.last);
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.name, 'Coach C');
      expect(captured!.id, '');
    });

    testWidgets('edit mode prefills existing name and returns draft '
        'preserving existing.id', (tester) async {
      const existing = UserRecord(id: 'user-9', name: 'Coach Z');
      UserDraft? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    captured = await showUserFormSheet(
                      context,
                      existing: existing,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Edit-mode title.
      expect(find.text('Edit user'), findsOneWidget);

      // Field is prefilled with the existing name.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Coach Z');

      // Change the name and submit.
      await tester.enterText(find.byType(TextField), 'Coach Z2');
      await tester.tap(find.text('Save user'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.name, 'Coach Z2');
      expect(captured!.id, 'user-9');
    });
  });

  group('showUserFormSheet — validation', () {
    testWidgets('empty name shows validation error and does NOT pop '
        'the sheet', (tester) async {
      bool resolved = false;
      UserDraft? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    captured = await showUserFormSheet(context);
                    resolved = true;
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Submit without entering anything.
      await tester.tap(find.text('Add user').last);
      await tester.pumpAndSettle();

      // Error message is shown.
      expect(find.text('User name is required'), findsOneWidget);
      // Sheet is still open — its title remains.
      expect(find.text('Add user'), findsAtLeastNWidgets(1));
      // The future has not resolved.
      expect(resolved, isFalse);
      expect(captured, isNull);
    });

    testWidgets('whitespace-only name is treated as empty', (tester) async {
      bool resolved = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await showUserFormSheet(context);
                    resolved = true;
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '   \t  ');
      await tester.tap(find.text('Add user').last);
      await tester.pumpAndSettle();

      expect(find.text('User name is required'), findsOneWidget);
      expect(resolved, isFalse);
    });
  });
}

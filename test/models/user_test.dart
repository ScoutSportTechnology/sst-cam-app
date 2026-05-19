import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/models/user.dart';

void main() {
  group('UserRecord', () {
    test('constructs with id and name', () {
      const user = UserRecord(id: 'user-1', name: 'Coach Diego');

      expect(user.id, 'user-1');
      expect(user.name, 'Coach Diego');
    });

    test('copyWith mutates only the named field', () {
      const original = UserRecord(id: 'user-1', name: 'Coach Diego');
      final updated = original.copyWith(name: 'Coach Maria');

      expect(updated.id, 'user-1');
      expect(updated.name, 'Coach Maria');
      // Original is unchanged.
      expect(original.name, 'Coach Diego');
    });

    test('copyWith with no arguments returns an equal record', () {
      const original = UserRecord(id: 'user-1', name: 'Coach Diego');
      final copy = original.copyWith();

      expect(copy, equals(original));
    });

    test('equality holds for two records with the same id and name', () {
      const a = UserRecord(id: 'user-1', name: 'Coach Diego');
      const b = UserRecord(id: 'user-1', name: 'Coach Diego');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('records with different ids are unequal', () {
      const a = UserRecord(id: 'user-1', name: 'Coach Diego');
      const b = UserRecord(id: 'user-2', name: 'Coach Diego');

      expect(a, isNot(equals(b)));
    });

    test('records with different names are unequal', () {
      const a = UserRecord(id: 'user-1', name: 'Coach Diego');
      const b = UserRecord(id: 'user-1', name: 'Coach Maria');

      expect(a, isNot(equals(b)));
    });
  });

  group('UserDraft', () {
    test('default id is empty string', () {
      const draft = UserDraft(name: 'Coach Diego');

      expect(draft.id, '');
      expect(draft.name, 'Coach Diego');
    });

    test('id can be supplied for update flows', () {
      const draft = UserDraft(id: 'user-1', name: 'Coach Diego');

      expect(draft.id, 'user-1');
      expect(draft.name, 'Coach Diego');
    });
  });
}

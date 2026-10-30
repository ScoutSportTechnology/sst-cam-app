// U8 — friendly, action-oriented, secret-redacting copy for the enumerated
// connectivity/streaming/network outcomes.

import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/errors/friendly_status.dart';

void main() {
  group('FriendlyStatus.forOutcome', () {
    test('every enumerated outcome maps to a non-empty, action-oriented, '
        'human string (never the raw enum name)', () {
      for (final outcome in ConnectivityOutcome.values) {
        final status = FriendlyStatus.forOutcome(outcome);
        expect(status.outcome, outcome);
        expect(status.message.trim(), isNotEmpty);
        // The message must read as prose, never leak the enum symbol.
        expect(status.message, isNot(contains(outcome.name)));
        // Sanity: it's a real sentence, not a token.
        expect(status.message.length, greaterThan(15));
        expect(status.message, contains(' '));
      }
    });

    test('known failures carry a next-step action hint', () {
      const withHints = [
        ConnectivityOutcome.isolated,
        ConnectivityOutcome.wrongPassword,
        ConnectivityOutcome.couldntJoin,
        ConnectivityOutcome.noUplink,
        ConnectivityOutcome.egressUnreachable,
        ConnectivityOutcome.configReadFailure,
        ConnectivityOutcome.configWriteFailure,
      ];
      for (final o in withHints) {
        final status = FriendlyStatus.forOutcome(o);
        expect(status.actionHint, isNotNull, reason: '$o should hint a step');
        expect(status.actionHint!.trim(), isNotEmpty);
      }
    });

    test(
      'isolation copy reassures BLE control + recording still work (U7)',
      () {
        final s = FriendlyStatus.forOutcome(ConnectivityOutcome.isolated);
        expect(s.message.toLowerCase(), contains('bluetooth'));
        expect(s.message.toLowerCase(), contains('recording'));
      },
    );

    test('unknown outcome yields a generic friendly fallback, never a stack '
        'or enum', () {
      final s = FriendlyStatus.forOutcome(ConnectivityOutcome.unknown);
      expect(s.message.trim(), isNotEmpty);
      expect(s.message, isNot(contains('unknown')));
      expect(s.message.toLowerCase(), contains('bluetooth'));
    });
  });

  group('classifyError', () {
    test('routes well-known error phrasings to their outcome', () {
      expect(
        classifyError(Exception('bad passphrase')),
        ConnectivityOutcome.wrongPassword,
      );
      expect(
        classifyError('the AP is client-isolated'),
        ConnectivityOutcome.isolated,
      );
      expect(
        classifyError('egress unreachable'),
        ConnectivityOutcome.egressUnreachable,
      );
      expect(
        classifyError('failed to join network'),
        ConnectivityOutcome.couldntJoin,
      );
    });

    test('unrecognized error falls back (default unknown; overridable)', () {
      expect(classifyError('kaboom 0x9f'), ConnectivityOutcome.unknown);
      expect(
        classifyError('kaboom 0x9f', fallback: ConnectivityOutcome.couldntJoin),
        ConnectivityOutcome.couldntJoin,
      );
    });
  });

  group('redaction (CRITICAL — never render an SSID or passphrase)', () {
    const ssid = 'HomeNet-5G-Guest';
    const passphrase = 'hunter2SuperSecret';

    test('redactSecrets removes ssid/password values in key=value form', () {
      final raw = 'join failed ssid=$ssid password=$passphrase code=7';
      final red = redactSecrets(raw);
      expect(red, isNot(contains(ssid)));
      expect(red, isNot(contains(passphrase)));
      // Non-secret context is preserved for debugging.
      expect(red, contains('code=7'));
      expect(red, contains('[redacted]'));
    });

    test('redactSecrets removes quoted + colon-delimited secret values', () {
      final raw = 'nmcli error: psk: "$passphrase", SSID "$ssid" not reachable';
      final red = redactSecrets(raw);
      expect(red, isNot(contains(ssid)));
      expect(red, isNot(contains(passphrase)));
    });

    test('a passphrase/SSID-bearing error maps to a redacted debug detail '
        '(no secret substring), and the friendly message never carries it', () {
      final err = Exception(
        'SetNetworkConfig failed ssid=$ssid passphrase=$passphrase',
      );
      final status = FriendlyStatus.fromError(
        err,
        fallback: ConnectivityOutcome.couldntJoin,
      );
      // The user-facing copy is a fixed string — it never interpolates raw.
      expect(status.message, isNot(contains(ssid)));
      expect(status.message, isNot(contains(passphrase)));
      // The debug affordance detail is present but redacted.
      expect(status.debugDetail, isNotNull);
      expect(status.debugDetail, isNot(contains(ssid)));
      expect(status.debugDetail, isNot(contains(passphrase)));
      expect(status.debugDetail, contains('[redacted]'));
    });

    test('forOutcome with rawDetail redacts the debug detail', () {
      final s = FriendlyStatus.forOutcome(
        ConnectivityOutcome.configWriteFailure,
        rawDetail: 'wifi_password=$passphrase ssid=$ssid',
      );
      expect(s.debugDetail, isNotNull);
      expect(s.debugDetail, isNot(contains(passphrase)));
      expect(s.debugDetail, isNot(contains(ssid)));
    });
  });
}

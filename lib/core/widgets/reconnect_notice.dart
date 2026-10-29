// Reconnect give-up notice — the DISTINCT surface for the one permanent
// auto-reconnect failure (U6): the camera answered the loop's handshake with
// a protocol_version this app build does not speak. Retrying cannot fix
// wire-contract skew, so the loop stopped; the fix is a software update on
// one side. Rendered where connection state already shows (main page hero
// area), same visual grammar as the device-health banner.
//
// The bluetooth-off give-up intentionally has NO surface here — the
// discovery page already owns the "Bluetooth is off" prompt.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/reconnect_controller.dart';
import '../theme/tokens.dart';

class ReconnectFailureNotice extends ConsumerWidget {
  const ReconnectFailureNotice({super.key, this.margin});

  /// Outer margin — defaults to the standard 14 px page inset.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(reconnectControllerProvider);
    final mismatch =
        s.phase == ReconnectPhase.gaveUp &&
        s.giveUpReason == ReconnectGiveUpReason.protocolMismatch;
    if (!mismatch) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.dangerSoft,
        border: Border.all(color: T.danger, width: 1),
      ),
      child: const Row(
        children: [
          Icon(Icons.sync_problem, size: 20, color: T.danger),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reconnect stopped — software mismatch',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: T.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'The camera runs an incompatible protocol version. Update '
                  'the app or the camera firmware, then reconnect.',
                  style: TextStyle(fontSize: 11, color: T.ink2, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

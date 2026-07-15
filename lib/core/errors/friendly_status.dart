/// Human-readable, action-oriented copy for the enumerated set of
/// connectivity / streaming / network OUTCOMES the app can surface (U7 + U8).
///
/// This is deliberately a small, closed enumeration of the F1 provisioning +
/// streaming outcomes — NOT a cross-app error-code framework. Anything not in
/// the set maps to a generic friendly fallback; a raw enum name or stack trace
/// must never reach the user.
///
/// REDACTION INVARIANT: neither the user-facing copy nor the redacted debug
/// affordance may ever render an SSID or passphrase. The user-facing [message]
/// / [actionHint] are fixed strings that never interpolate raw error text, and
/// any raw detail exposed for debugging is passed through [redactSecrets] first.
library;

/// The closed set of connectivity / streaming / network outcomes the app maps
/// to friendly copy. [unknown] is the catch-all that yields a generic fallback.
enum ConnectivityOutcome {
  /// The WiFi password the operator entered was rejected by the network.
  wrongPassword,

  /// The camera couldn't join the network (association failed, not auth).
  couldntJoin,

  /// The phone's Wi-Fi is a 2.4 GHz network. The camera's single radio carries
  /// the Bluetooth control link on 2.4 GHz, so it can only join a 5 GHz Wi-Fi
  /// (2.4 GHz association is torn down by radio coexistence). Validated up front.
  needs5GHz,

  /// The network is client-isolated — devices can't reach each other, so the
  /// LAN preview probe failed even though the camera joined.
  isolated,

  /// The shared WiFi dropped mid-session; the camera fell back to a direct
  /// connection.
  droppedMidSession,

  /// The operator tapped Connect on the network the camera is ALREADY on — a
  /// no-op, surfaced as a calm "you're already connected", never the alarming
  /// "a network change is already in progress" (which is the true busy case).
  alreadyConnected,

  /// A change-networks (switch to a new Wi-Fi) FAILED. One radio can't hold two
  /// STA sessions, so the switch tore the old network down before the new join;
  /// on failure the camera fell back to the direct (P2P) connection rather than
  /// silently breaking. This is the destructive-failure path.
  switchFailedRevertedToP2p,

  /// Streaming was requested with no internet uplink present.
  noUplink,

  /// An uplink is present but the RTMP egress itself is unreachable (the
  /// firmware's distinct "egress unreachable" reason) — the internet is not
  /// necessarily fine.
  egressUnreachable,

  /// Reading the camera's network config over BLE failed.
  configReadFailure,

  /// Writing/applying the camera's network config over BLE failed.
  configWriteFailure,

  /// Anything not enumerated above — yields the generic friendly fallback.
  unknown,
}

/// A user-facing status derived from a [ConnectivityOutcome]: the friendly
/// [message], an optional [actionHint], and a REDACTED [debugDetail] for a
/// debug/diagnostics affordance (never shown by default, never containing a
/// secret).
class FriendlyStatus {
  const FriendlyStatus({
    required this.outcome,
    required this.message,
    this.actionHint,
    this.debugDetail,
  });

  final ConnectivityOutcome outcome;

  /// Fixed, secret-free, human-readable copy. Safe to render anywhere.
  final String message;

  /// A short next step, when there is one (e.g. "Double-check the password").
  final String? actionHint;

  /// Raw error detail with SSIDs/passphrases stripped, for a debug affordance.
  /// Null when there was no raw detail. NEVER contains a secret.
  final String? debugDetail;

  /// [message] plus [actionHint] as one line, for a single-line surface.
  String get combined => actionHint == null || actionHint!.isEmpty
      ? message
      : '$message $actionHint';

  /// Maps [outcome] to fixed friendly copy, attaching a redacted [rawDetail]
  /// (if any) as [debugDetail]. The copy never interpolates [rawDetail].
  factory FriendlyStatus.forOutcome(
    ConnectivityOutcome outcome, {
    String? rawDetail,
  }) {
    final (message, hint) = _copyFor(outcome);
    return FriendlyStatus(
      outcome: outcome,
      message: message,
      actionHint: hint,
      debugDetail: (rawDetail == null || rawDetail.isEmpty)
          ? null
          : redactSecrets(rawDetail),
    );
  }

  /// Classifies an arbitrary caught [error] into a [ConnectivityOutcome] and
  /// returns the friendly status, carrying the (redacted) raw string as
  /// [debugDetail]. Use this on catch paths where the outcome isn't already
  /// known (e.g. the provisioning `_save`/`_load` catches).
  factory FriendlyStatus.fromError(
    Object error, {
    ConnectivityOutcome fallback = ConnectivityOutcome.unknown,
  }) {
    final raw = error.toString();
    return FriendlyStatus.forOutcome(
      classifyError(error, fallback: fallback),
      rawDetail: raw,
    );
  }

  static (String, String?) _copyFor(ConnectivityOutcome outcome) {
    switch (outcome) {
      case ConnectivityOutcome.isolated:
        return (
          "This Wi-Fi network keeps devices from talking to each other, so live "
              "preview and streaming won't work here. Your camera is still "
              "connected over Bluetooth — recording works fine.",
          "To use preview and streaming, connect to a different network.",
        );
      case ConnectivityOutcome.wrongPassword:
        return (
          "That Wi-Fi password didn't work. Your camera is still connected over "
              "Bluetooth.",
          "Double-check the password and try again.",
        );
      case ConnectivityOutcome.couldntJoin:
        return (
          "The camera couldn't join that network. It's still connected over "
              "Bluetooth — recording works.",
          "Try again or pick another network.",
        );
      case ConnectivityOutcome.needs5GHz:
        return (
          "This looks like a 2.4 GHz Wi-Fi network. The camera can only join a "
              "5 GHz Wi-Fi — while it's connected over Bluetooth its radio can't "
              "hold a 2.4 GHz Wi-Fi at the same time.",
          "Switch your phone's hotspot (or Wi-Fi) to 5 GHz, then try again.",
        );
      case ConnectivityOutcome.droppedMidSession:
        return (
          "The camera lost that Wi-Fi network and switched back to a direct "
              "connection. Recording and preview still work; streaming is paused "
              "until Wi-Fi is back.",
          null,
        );
      case ConnectivityOutcome.alreadyConnected:
        return (
          "The camera is already connected to this Wi-Fi — live preview and "
              "streaming are on.",
          null,
        );
      case ConnectivityOutcome.switchFailedRevertedToP2p:
        return (
          "Couldn't switch to the new Wi-Fi, so the camera went back to a direct "
              "connection. Recording and the direct live preview still work.",
          "Check the new network, then try connecting again.",
        );
      case ConnectivityOutcome.noUplink:
        return (
          "Streaming needs an internet connection. The camera doesn't have one "
              "right now, so streaming is off. Recording and live preview still "
              "work.",
          "Connect the camera to your Wi-Fi or plug in Ethernet.",
        );
      case ConnectivityOutcome.egressUnreachable:
        return (
          "The camera is online but couldn't reach the streaming server, so "
              "streaming didn't start. Recording still works.",
          "Check the streaming destination, or try again in a moment.",
        );
      case ConnectivityOutcome.configReadFailure:
        return (
          "Couldn't read the camera's network settings just now.",
          "Make sure the camera is connected, then try again.",
        );
      case ConnectivityOutcome.configWriteFailure:
        return (
          "Couldn't save the camera's network settings.",
          "Make sure the camera is connected, then try again.",
        );
      case ConnectivityOutcome.unknown:
        return (
          "Something went wrong with the camera's network. Your camera is still "
              "connected over Bluetooth — recording works.",
          "Try again in a moment.",
        );
    }
  }
}

/// Best-effort classification of a caught error into a [ConnectivityOutcome] by
/// scanning its message for well-known tokens. Returns [fallback] when nothing
/// matches. Never renders the message — only inspects it.
ConnectivityOutcome classifyError(
  Object error, {
  ConnectivityOutcome fallback = ConnectivityOutcome.unknown,
}) {
  final s = error.toString().toLowerCase();
  bool has(String needle) => s.contains(needle);

  if (has('wrong password') ||
      has('bad password') ||
      has('bad passphrase') ||
      has('incorrect password') ||
      has('auth failed') ||
      has('authentication failed') ||
      has('unauthor')) {
    return ConnectivityOutcome.wrongPassword;
  }
  if (has('isolat')) return ConnectivityOutcome.isolated;
  if (has('egress')) return ConnectivityOutcome.egressUnreachable;
  if (has('no uplink') ||
      has('no internet') ||
      has('internet unreachable') ||
      has('no route')) {
    return ConnectivityOutcome.noUplink;
  }
  if (has('dropped') || has('lost wifi') || has('lost wi-fi')) {
    return ConnectivityOutcome.droppedMidSession;
  }
  if (has('could not join') ||
      has("couldn't join") ||
      has('failed to join') ||
      has('join failed') ||
      has('association')) {
    return ConnectivityOutcome.couldntJoin;
  }
  return fallback;
}

/// Strips likely SSID / passphrase / credential values from a raw string so it
/// can be shown in a debug/diagnostics affordance without leaking a secret.
///
/// Handles the common shapes `key=value`, `key: value`, `key "value"` and
/// `key 'value'` for a fixed set of secret-bearing keys. Deliberately
/// conservative: it never widens the surface by echoing the raw value elsewhere;
/// the friendly [FriendlyStatus.message] never contains raw text at all.
String redactSecrets(String raw) {
  const secretKeys = [
    'ssid',
    'password',
    'passphrase',
    'psk',
    'pwd',
    'pass',
    'credential',
    'preview_credential',
    'previewcredential',
    'wifi_password',
    'wifipassword',
    'stream_key',
    'streamkey',
    'authtoken',
    'auth_token',
  ];
  var out = raw;
  for (final key in secretKeys) {
    // key = value  /  key: value  (value = a run of non-space, non-delimiter)
    out = out.replaceAllMapped(
      RegExp(
        '($key)(\\s*[=:]\\s*)("?\'?)([^\\s,;)"\']+)',
        caseSensitive: false,
      ),
      (m) => '${m[1]}${m[2]}${m[3]}[redacted]',
    );
    // key "value"  /  key 'value'  (quoted, space-separated)
    out = out.replaceAllMapped(
      RegExp('($key)(\\s+)(["\'])([^"\']*)(["\'])', caseSensitive: false),
      (m) => '${m[1]}${m[2]}${m[3]}[redacted]${m[5]}',
    );
  }
  return out;
}

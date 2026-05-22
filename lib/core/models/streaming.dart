// Per-user live-streaming destinations. Each destination targets one
// streaming endpoint (YouTube Live, a custom RTMP/RTSP server, etc.) and
// is stored in the local Drift DB, scoped to the user that owns it.
//
// Shape:
//
//   StreamingDestination
//     id, name
//     provider  in { youtube, tiktok, facebook, instagram, custom }
//     protocol  in { rtmp, rtmps, rtsp }
//     config    sealed: RtmpConfig | RtspConfig
//
// Invariants (enforced at form-submit time in U9; the model itself is just
// data so test doubles and proto round-trips don't need to know the rules):
//
//   * provider in { youtube, tiktok, facebook, instagram } => protocol == rtmp
//   * provider == custom                                   => protocol picked
//                                                              by the user
//   * protocol in { rtmp, rtmps }                          => RtmpConfig
//   * protocol == rtsp                                     => RtspConfig
//
// `RtmpConfig` covers both `rtmp` and `rtmps` — the protocol enum carries
// the distinction so the wire format stays a single config case.

import 'package:flutter/foundation.dart';

enum StreamingProvider { youtube, tiktok, facebook, instagram, custom }

extension StreamingProviderLabel on StreamingProvider {
  String get displayLabel {
    switch (this) {
      case StreamingProvider.youtube:
        return 'YouTube';
      case StreamingProvider.tiktok:
        return 'TikTok';
      case StreamingProvider.facebook:
        return 'Facebook';
      case StreamingProvider.instagram:
        return 'Instagram';
      case StreamingProvider.custom:
        return 'Custom';
    }
  }
}

enum StreamingProtocol { rtmp, rtmps, rtsp }

extension StreamingProtocolLabel on StreamingProtocol {
  String get displayLabel {
    switch (this) {
      case StreamingProtocol.rtmp:
        return 'RTMP';
      case StreamingProtocol.rtmps:
        return 'RTMPS';
      case StreamingProtocol.rtsp:
        return 'RTSP';
    }
  }

  /// URL scheme prefix that matching destination URLs must start with.
  String get urlScheme {
    switch (this) {
      case StreamingProtocol.rtmp:
        return 'rtmp://';
      case StreamingProtocol.rtmps:
        return 'rtmps://';
      case StreamingProtocol.rtsp:
        return 'rtsp://';
    }
  }
}

/// Sealed protocol-specific configuration. Pattern-match exhaustively at
/// serialization / form-render time.
sealed class StreamingConfig {
  const StreamingConfig();
}

/// Covers BOTH `rtmp` and `rtmps`; the [StreamingProtocol] on the
/// destination carries the distinction.
@immutable
class RtmpConfig extends StreamingConfig {
  const RtmpConfig({required this.url, required this.streamKey});

  final String url;
  final String streamKey;

  RtmpConfig copyWith({String? url, String? streamKey}) {
    return RtmpConfig(
      url: url ?? this.url,
      streamKey: streamKey ?? this.streamKey,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RtmpConfig && other.url == url && other.streamKey == streamKey;

  @override
  int get hashCode => Object.hash(url, streamKey);
}

@immutable
class RtspConfig extends StreamingConfig {
  const RtspConfig({required this.url, this.username, this.password});

  final String url;
  final String? username;
  final String? password;

  RtspConfig copyWith({String? url, String? username, String? password}) {
    return RtspConfig(
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RtspConfig &&
          other.url == url &&
          other.username == username &&
          other.password == password;

  @override
  int get hashCode => Object.hash(url, username, password);
}

@immutable
class StreamingDestination {
  const StreamingDestination({
    required this.id,
    required this.name,
    required this.provider,
    required this.protocol,
    required this.config,
  });

  final String id;
  final String name;
  final StreamingProvider provider;
  final StreamingProtocol protocol;
  final StreamingConfig config;

  StreamingDestination copyWith({
    String? name,
    StreamingProvider? provider,
    StreamingProtocol? protocol,
    StreamingConfig? config,
  }) {
    return StreamingDestination(
      id: id,
      name: name ?? this.name,
      provider: provider ?? this.provider,
      protocol: protocol ?? this.protocol,
      config: config ?? this.config,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamingDestination &&
          other.id == id &&
          other.name == name &&
          other.provider == provider &&
          other.protocol == protocol &&
          other.config == config;

  @override
  int get hashCode => Object.hash(id, name, provider, protocol, config);
}

/// Mutable inputs for create/update. `id` is empty on create — firmware
/// assigns it.
@immutable
class StreamingDestinationDraft {
  const StreamingDestinationDraft({
    required this.name,
    required this.provider,
    required this.protocol,
    required this.config,
    this.id = '',
  });

  final String id;
  final String name;
  final StreamingProvider provider;
  final StreamingProtocol protocol;
  final StreamingConfig config;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/models/streaming.dart';

/// Helper used by the exhaustive-switch edge case below. Returns a stable
/// tag for each [StreamingConfig] subtype so the test can assert that
/// pattern matching covers both cases.
String tagOfConfig(StreamingConfig config) {
  return switch (config) {
    RtmpConfig() => 'rtmp',
    RtspConfig() => 'rtsp',
  };
}

void main() {
  group('StreamingProvider.displayLabel', () {
    test('youtube → "YouTube"', () {
      expect(StreamingProvider.youtube.displayLabel, 'YouTube');
    });

    test('tiktok → "TikTok"', () {
      expect(StreamingProvider.tiktok.displayLabel, 'TikTok');
    });

    test('facebook → "Facebook"', () {
      expect(StreamingProvider.facebook.displayLabel, 'Facebook');
    });

    test('instagram → "Instagram"', () {
      expect(StreamingProvider.instagram.displayLabel, 'Instagram');
    });

    test('custom → "Custom"', () {
      expect(StreamingProvider.custom.displayLabel, 'Custom');
    });
  });

  group('StreamingProtocol.displayLabel', () {
    test('rtmp → "RTMP"', () {
      expect(StreamingProtocol.rtmp.displayLabel, 'RTMP');
    });

    test('rtmps → "RTMPS"', () {
      expect(StreamingProtocol.rtmps.displayLabel, 'RTMPS');
    });

    test('rtsp → "RTSP"', () {
      expect(StreamingProtocol.rtsp.displayLabel, 'RTSP');
    });
  });

  group('StreamingProtocol.urlScheme', () {
    test('rtmp → "rtmp://"', () {
      expect(StreamingProtocol.rtmp.urlScheme, 'rtmp://');
    });

    test('rtmps → "rtmps://"', () {
      expect(StreamingProtocol.rtmps.urlScheme, 'rtmps://');
    });

    test('rtsp → "rtsp://"', () {
      expect(StreamingProtocol.rtsp.urlScheme, 'rtsp://');
    });
  });

  group('StreamingDestination with RtmpConfig', () {
    const rtmpConfig = RtmpConfig(
      url: 'rtmp://a.rtmp.youtube.com/live2',
      streamKey: 'abcd-efgh-ijkl-mnop',
    );

    test('constructs for YouTube with RTMP', () {
      const dest = StreamingDestination(
        id: 'dest-1',
        name: 'My YouTube',
        provider: StreamingProvider.youtube,
        protocol: StreamingProtocol.rtmp,
        config: rtmpConfig,
      );

      expect(dest.provider, StreamingProvider.youtube);
      expect(dest.protocol, StreamingProtocol.rtmp);
      expect(dest.config, isA<RtmpConfig>());
      expect((dest.config as RtmpConfig).url, rtmpConfig.url);
      expect((dest.config as RtmpConfig).streamKey, rtmpConfig.streamKey);
    });

    test('constructs for TikTok with RTMP', () {
      const dest = StreamingDestination(
        id: 'dest-2',
        name: 'TikTok Live',
        provider: StreamingProvider.tiktok,
        protocol: StreamingProtocol.rtmp,
        config: rtmpConfig,
      );

      expect(dest.provider, StreamingProvider.tiktok);
      expect(dest.protocol, StreamingProtocol.rtmp);
    });

    test('constructs for Facebook with RTMP', () {
      const dest = StreamingDestination(
        id: 'dest-3',
        name: 'FB Live',
        provider: StreamingProvider.facebook,
        protocol: StreamingProtocol.rtmp,
        config: rtmpConfig,
      );

      expect(dest.provider, StreamingProvider.facebook);
      expect(dest.protocol, StreamingProtocol.rtmp);
    });

    test('constructs for Instagram with RTMP', () {
      const dest = StreamingDestination(
        id: 'dest-4',
        name: 'IG Live',
        provider: StreamingProvider.instagram,
        protocol: StreamingProtocol.rtmp,
        config: rtmpConfig,
      );

      expect(dest.provider, StreamingProvider.instagram);
      expect(dest.protocol, StreamingProtocol.rtmp);
    });

    test('constructs for Custom with RTMPS', () {
      const dest = StreamingDestination(
        id: 'dest-5',
        name: 'My Server',
        provider: StreamingProvider.custom,
        protocol: StreamingProtocol.rtmps,
        config: RtmpConfig(
          url: 'rtmps://example.com/live',
          streamKey: 'secret',
        ),
      );

      expect(dest.provider, StreamingProvider.custom);
      expect(dest.protocol, StreamingProtocol.rtmps);
      expect(dest.config, isA<RtmpConfig>());
    });
  });

  group('StreamingDestination with RtspConfig', () {
    test('constructs without username/password', () {
      const dest = StreamingDestination(
        id: 'dest-6',
        name: 'IP Camera',
        provider: StreamingProvider.custom,
        protocol: StreamingProtocol.rtsp,
        config: RtspConfig(url: 'rtsp://192.168.1.10/stream'),
      );

      expect(dest.config, isA<RtspConfig>());
      final cfg = dest.config as RtspConfig;
      expect(cfg.url, 'rtsp://192.168.1.10/stream');
      expect(cfg.username, isNull);
      expect(cfg.password, isNull);
    });

    test('constructs with username and password', () {
      const dest = StreamingDestination(
        id: 'dest-7',
        name: 'IP Camera',
        provider: StreamingProvider.custom,
        protocol: StreamingProtocol.rtsp,
        config: RtspConfig(
          url: 'rtsp://192.168.1.10/stream',
          username: 'admin',
          password: 'hunter2',
        ),
      );

      final cfg = dest.config as RtspConfig;
      expect(cfg.username, 'admin');
      expect(cfg.password, 'hunter2');
    });
  });

  group('Equality', () {
    test('two destinations with the same fields are equal (deep)', () {
      const a = StreamingDestination(
        id: 'dest-1',
        name: 'My YouTube',
        provider: StreamingProvider.youtube,
        protocol: StreamingProtocol.rtmp,
        config: RtmpConfig(url: 'rtmp://a/b', streamKey: 'k'),
      );
      const b = StreamingDestination(
        id: 'dest-1',
        name: 'My YouTube',
        provider: StreamingProvider.youtube,
        protocol: StreamingProtocol.rtmp,
        config: RtmpConfig(url: 'rtmp://a/b', streamKey: 'k'),
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('RtmpConfig equality holds on identical fields', () {
      const a = RtmpConfig(url: 'rtmp://a/b', streamKey: 'k');
      const b = RtmpConfig(url: 'rtmp://a/b', streamKey: 'k');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('RtspConfig equality holds on identical fields (with creds)', () {
      const a = RtspConfig(url: 'rtsp://x', username: 'u', password: 'p');
      const b = RtspConfig(url: 'rtsp://x', username: 'u', password: 'p');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different stream keys break RtmpConfig equality', () {
      const a = RtmpConfig(url: 'rtmp://a/b', streamKey: 'k1');
      const b = RtmpConfig(url: 'rtmp://a/b', streamKey: 'k2');

      expect(a, isNot(equals(b)));
    });

    test('a destination wrapping different configs is unequal', () {
      const a = StreamingDestination(
        id: 'dest-1',
        name: 'My YouTube',
        provider: StreamingProvider.youtube,
        protocol: StreamingProtocol.rtmp,
        config: RtmpConfig(url: 'rtmp://a/b', streamKey: 'k1'),
      );
      const b = StreamingDestination(
        id: 'dest-1',
        name: 'My YouTube',
        provider: StreamingProvider.youtube,
        protocol: StreamingProtocol.rtmp,
        config: RtmpConfig(url: 'rtmp://a/b', streamKey: 'k2'),
      );

      expect(a, isNot(equals(b)));
    });
  });

  group('copyWith', () {
    const original = StreamingDestination(
      id: 'dest-1',
      name: 'My YouTube',
      provider: StreamingProvider.youtube,
      protocol: StreamingProtocol.rtmp,
      config: RtmpConfig(url: 'rtmp://a/b', streamKey: 'k'),
    );

    test('changes only name', () {
      final copy = original.copyWith(name: 'Renamed');

      expect(copy.id, original.id);
      expect(copy.name, 'Renamed');
      expect(copy.provider, original.provider);
      expect(copy.protocol, original.protocol);
      expect(copy.config, original.config);
    });

    test('changes only provider', () {
      final copy = original.copyWith(provider: StreamingProvider.tiktok);

      expect(copy.provider, StreamingProvider.tiktok);
      expect(copy.name, original.name);
      expect(copy.protocol, original.protocol);
      expect(copy.config, original.config);
    });

    test('with no arguments produces an equal instance', () {
      final copy = original.copyWith();

      expect(copy, equals(original));
    });
  });

  group('Sealed switch on StreamingConfig', () {
    test('returns "rtmp" for RtmpConfig', () {
      const config = RtmpConfig(url: 'rtmp://a/b', streamKey: 'k');

      expect(tagOfConfig(config), 'rtmp');
    });

    test('returns "rtsp" for RtspConfig', () {
      const config = RtspConfig(url: 'rtsp://x');

      expect(tagOfConfig(config), 'rtsp');
    });
  });

  group('StreamingDestinationDraft', () {
    test('default id is empty string', () {
      const draft = StreamingDestinationDraft(
        name: 'New',
        provider: StreamingProvider.youtube,
        protocol: StreamingProtocol.rtmp,
        config: RtmpConfig(url: 'rtmp://a/b', streamKey: 'k'),
      );

      expect(draft.id, '');
    });

    test('id can be supplied for update flows', () {
      const draft = StreamingDestinationDraft(
        id: 'dest-1',
        name: 'Updated',
        provider: StreamingProvider.youtube,
        protocol: StreamingProtocol.rtmp,
        config: RtmpConfig(url: 'rtmp://a/b', streamKey: 'k'),
      );

      expect(draft.id, 'dest-1');
      expect(draft.name, 'Updated');
    });
  });
}

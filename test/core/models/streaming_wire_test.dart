// resolveWireStream / joinRtmp — the shared wire-URL resolution used by match
// setup + mid-match streaming. Covers RTMP key-join and the RTSP credential
// percent-encoding (so special chars in a password don't corrupt the URL).
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/models/streaming.dart';

void main() {
  group('joinRtmp', () {
    test('appends key with a single slash', () {
      expect(joinRtmp('rtmp://h/app', 'KEY'), 'rtmp://h/app/KEY');
    });
    test('does not double the slash', () {
      expect(joinRtmp('rtmp://h/app/', 'KEY'), 'rtmp://h/app/KEY');
    });
    test('empty key returns the base unchanged', () {
      expect(joinRtmp('rtmp://h/app', ''), 'rtmp://h/app');
    });
  });

  group('resolveWireStream', () {
    test('RTMP combines base + key; stores them split', () {
      final w = resolveWireStream(
        const RtmpConfig(url: 'rtmp://a.example.com/live', streamKey: 'abc'),
      );
      expect(w, isNotNull);
      expect(w!.wireUrl, 'rtmp://a.example.com/live/abc');
      expect(w.storeUrl, 'rtmp://a.example.com/live');
      expect(w.storeKey, 'abc');
    });

    test('RTSP with no creds passes the URL through, null key', () {
      final w = resolveWireStream(
        const RtspConfig(url: 'rtsp://192.168.1.5/stream'),
      );
      expect(w!.wireUrl, 'rtsp://192.168.1.5/stream');
      expect(w.storeKey, isNull);
    });

    test('RTSP percent-encodes creds — @ and : do not break the authority', () {
      final w = resolveWireStream(
        const RtspConfig(
          url: 'rtsp://192.168.1.5/stream',
          username: 'cam',
          password: 'p@ss:w/rd',
        ),
      );
      // The @ : / in the password are encoded inside userInfo, so the host
      // stays 192.168.1.5 (not shifted by the raw '@').
      final uri = Uri.parse(w!.wireUrl);
      expect(uri.host, '192.168.1.5');
      expect(uri.userInfo, 'cam:p%40ss%3Aw%2Frd');
      expect(Uri.decodeComponent(uri.userInfo.split(':')[1]), 'p@ss:w/rd');
    });
  });
}

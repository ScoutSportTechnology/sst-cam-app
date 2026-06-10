// Real streamed-to-disk download client (App-U4): exercises the dio streaming,
// Content-Length progress, Bearer header, error status, and cancellation —
// without a real server, via a fake HttpClientAdapter.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/core/ble/ble_service.dart';
import 'package:sst_cam_app/core/models/recording.dart';
import 'package:sst_cam_app/core/models/wifi.dart';
import 'package:sst_cam_app/core/wifi/wifi_service_impl.dart';

class _DummyBle implements BleService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Streams [bytes] back in small chunks (with a yield between them so a
/// cancellation can land mid-stream), capturing the request headers.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({required this.bytes, this.status = 200, this.chunkSize = 64});
  final List<int> bytes;
  final int status;
  final int chunkSize;
  Map<String, List<String>>? lastRequestHeaders;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequestHeaders = {
      for (final e in options.headers.entries) e.key: ['${e.value}'],
    };
    Stream<Uint8List> body() async* {
      for (var i = 0; i < bytes.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, bytes.length);
        await Future<void>.delayed(const Duration(milliseconds: 1));
        yield Uint8List.fromList(bytes.sublist(i, end));
      }
    }

    return ResponseBody(
      body(),
      status,
      headers: {
        Headers.contentLengthHeader: [bytes.length.toString()],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DownloadToken _token() => DownloadToken(
      recordingId: 'rec-1',
      httpUrl: 'http://camera/recordings/rec-1',
      authToken: 'secret-bearer',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );

Future<VideoDownloadProgress> _terminal(VideoDownloadHandle handle) {
  final completer = Completer<VideoDownloadProgress>();
  handle.progress.listen((p) {
    if (p.isTerminal && !completer.isCompleted) completer.complete(p);
  });
  return completer.future;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sst-dl'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('streams the body to disk and completes with full byte count', () async {
    final bytes = List<int>.generate(1000, (i) => i % 256);
    final adapter = _FakeAdapter(bytes: bytes);
    final svc =
        WifiServiceImpl(ble: _DummyBle(), dio: Dio()..httpClientAdapter = adapter);
    final savePath = '${tmp.path}/out.mp4';

    final handle = await svc.startDownload('dev', _token(), saveAs: savePath);
    final terminal = await _terminal(handle);

    expect(terminal.status, DownloadStatus.completed);
    expect(terminal.bytesReceived, 1000);
    expect(terminal.bytesTotal, 1000);
    expect(File(savePath).readAsBytesSync(), bytes);
    // Bearer header was sent (and is the only place the token appears).
    expect(adapter.lastRequestHeaders!['Authorization'], ['Bearer secret-bearer']);
    await svc.dispose();
  });

  test('an error status surfaces as a failed download', () async {
    final adapter = _FakeAdapter(bytes: const [], status: 401);
    final svc =
        WifiServiceImpl(ble: _DummyBle(), dio: Dio()..httpClientAdapter = adapter);

    final handle =
        await svc.startDownload('dev', _token(), saveAs: '${tmp.path}/x.mp4');
    final terminal = await _terminal(handle);

    expect(terminal.status, DownloadStatus.failed);
    expect(terminal.errorMessage, contains('401'));
    await svc.dispose();
  });

  test('cancel mid-stream ends in cancelled', () async {
    // Large body + tiny chunks so cancel lands before completion.
    final bytes = List<int>.generate(100000, (i) => i % 256);
    final adapter = _FakeAdapter(bytes: bytes, chunkSize: 16);
    final svc =
        WifiServiceImpl(ble: _DummyBle(), dio: Dio()..httpClientAdapter = adapter);

    final handle =
        await svc.startDownload('dev', _token(), saveAs: '${tmp.path}/c.mp4');
    final terminal = _terminal(handle);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await handle.cancel();

    expect((await terminal).status, DownloadStatus.cancelled);
    await svc.dispose();
  });
}

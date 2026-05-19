import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sst_cam_app/db/app_database.dart';
import 'package:sst_cam_app/services/clip_service.dart';
import 'package:sst_cam_app/services/video_path_service.dart';

void main() {
  late AppDatabase db;
  late ClipService clipService;

  setUp(() {
    db = AppDatabase.forTesting(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    clipService = ClipService(
      clipsDao: db.clipsDao,
      videoPathService: VideoPathService(),
    );
  });

  tearDown(() => db.close());

  group('ClipService.trim', () {
    test('throws ClipTrimException when source file does not exist', () async {
      expect(
        () => clipService.trim(
          matchId: 'match-123',
          sourcePath: '/nonexistent/path/file.mp4',
          startSeconds: 10,
          durationSeconds: 30,
        ),
        throwsA(
          isA<ClipTrimException>().having(
            (e) => e.message,
            'message',
            contains('Source file not found'),
          ),
        ),
      );
    });

    test('no DB row inserted when source file is missing', () async {
      try {
        await clipService.trim(
          matchId: 'match-456',
          sourcePath: '/nonexistent/path/file.mp4',
          startSeconds: 0,
          durationSeconds: 30,
        );
      } on ClipTrimException {
        // Expected — swallow.
      }

      final clips = await db.select(db.clipsTable).get();
      expect(clips, isEmpty);
    });

    // NOTE: The success path (FFmpeg executes, row inserted) cannot be covered
    // in unit tests because FFmpegKit calls a native MethodChannel that is not
    // available in the unit-test environment. Integration tests with a real
    // device or emulator are required for the success path.
  });
}

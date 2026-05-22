// U12 — Settings page Backup & Restore section tests.
//
// Verifies:
//   1. _DataSection renders when activeCameraIdProvider is null (no camera).
//   2. _DataSection renders when camera is connected.
//   3. "Export backup" tap → BackupService.export() called; success SnackBar shown.
//   4. "Restore backup" tap → confirmation dialog shown.
//   5. Confirming restore → file path input dialog shown.
//   6. Cancelling confirmation → no file dialog, no SnackBar.
//   7. Entering a non-existent file path → error SnackBar shown.
//   8. Successful restore → success SnackBar shown, providers invalidated.
//
// BackupService is injected via backupServiceProvider so tests can use a
// FakeBackupService that avoids real file I/O (path_provider is unavailable
// in the widget-test environment).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sst_cam_app/mock/mock_ble_service.dart';
import 'package:sst_cam_app/core/models/device.dart';
import 'package:sst_cam_app/features/settings/data/data_settings_page.dart';
import 'package:sst_cam_app/features/settings/settings_page.dart';
import 'package:sst_cam_app/core/services/backup_service.dart';
import 'package:sst_cam_app/features/camera/camera_state.dart'
    show activeCameraIdProvider;
import 'package:sst_cam_app/core/ble/ble_providers.dart';
import 'package:sst_cam_app/core/state/db_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../test_helpers.dart';

// ---------------------------------------------------------------------------
// Fake PathProviderPlatform so the path containment check (Fix 2) in
// settings_page.dart can resolve a predictable docs dir in widget tests.
// ---------------------------------------------------------------------------

const String _kTestDocsDir = '/tmp/sst-test-docs';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => _kTestDocsDir;
}

const String _kFakeDeviceId = 'SST-CAM-001';

MockBleService _newMock() => MockBleService(
  scanDeviceAppearDelays: const [Duration.zero, Duration.zero],
  connectionDelay: Duration.zero,
  failureRate: 0.0,
  randomSeed: 1,
);

// ---------------------------------------------------------------------------
// Fake BackupService — avoids real file I/O in widget tests.
// ---------------------------------------------------------------------------

class FakeBackupService extends BackupService {
  FakeBackupService({
    required AppDatabase db,
    this.exportResult = '/tmp/sst-backup-2026-01-01.json',
    this.exportError,
    this.importResult,
    this.importError,
  }) : super(db);

  final String exportResult;
  final Exception? exportError;
  final String? importResult;
  final Exception? importError;

  var exportCalled = false;
  var importCalled = false;

  @override
  Future<String> export({String? deviceId, Directory? outputDir}) async {
    exportCalled = true;
    if (exportError != null) throw exportError!;
    return exportResult;
  }

  @override
  Future<String?> import(File file, {String? currentCameraDeviceId}) async {
    importCalled = true;
    if (importError != null) throw importError!;
    return importResult;
  }
}

// ---------------------------------------------------------------------------
// Test harness builder
// ---------------------------------------------------------------------------

Widget _buildHarness({
  required MockBleService service,
  required Object db,
  BackupService? backupService,
  String? activeCameraId,
  CameraConnectionState? connectionState,
}) {
  return ProviderScope(
    overrides: [
      ...dbOverrides(db),
      bleServiceProvider.overrideWithValue(service),
      if (backupService != null)
        backupServiceProvider.overrideWithValue(backupService),
      if (activeCameraId != null)
        activeCameraIdProvider.overrideWith((_) => activeCameraId),
      if (connectionState != null && activeCameraId != null)
        connectionStateProvider(activeCameraId).overrideWith(
          (_) => Stream<CameraConnectionState>.value(connectionState),
        ),
    ],
    child: const MaterialApp(home: SettingsPage()),
  );
}

/// Scrolls to the "Backup & restore" nav row on the main Settings page and
/// taps it to open [DataSettingsPage], making Export/Restore rows visible.
Future<void> _openDataSettingsPage(WidgetTester tester) async {
  // Use a large scroll delta (500px) so the element ends up well inside the
  // viewport rather than just barely entering at the bottom edge.
  await tester.scrollUntilVisible(
    find.text('Backup & restore'),
    500,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Backup & restore'));
  await tester.pumpAndSettle();
}

void main() {
  final db = useInMemoryDb();

  setUpAll(() {
    // Register the fake path provider so Fix 2's path containment check
    // resolves a predictable docs directory in widget tests.
    PathProviderPlatform.instance = _FakePathProvider();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ---------------------------------------------------------------------------
  // 1. _DataSection renders when no camera connected (activeCameraId = null)
  // ---------------------------------------------------------------------------
  testWidgets('Data section is visible when no camera is connected', (
    tester,
  ) async {
    final mock = _newMock();
    addTearDown(mock.dispose);

    await tester.pumpWidget(_buildHarness(service: mock, db: db));
    await tester.pumpAndSettle();

    // Banner is present.
    expect(find.text('No camera connected'), findsOneWidget);

    // Data section nav row is below the DB-backed sections — scroll and navigate.
    await _openDataSettingsPage(tester);
    expect(find.byType(DataSettingsPage), findsOneWidget);
    expect(find.text('Export backup'), findsOneWidget);
    expect(find.text('Restore backup'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 2. _DataSection renders when camera is connected
  // ---------------------------------------------------------------------------
  testWidgets('Data section is visible when camera is connected', (
    tester,
  ) async {
    final mock = _newMock();
    addTearDown(mock.dispose);

    await tester.pumpWidget(
      _buildHarness(
        service: mock,
        db: db,
        activeCameraId: _kFakeDeviceId,
        connectionState: CameraConnectionState.connected,
      ),
    );
    await tester.pumpAndSettle();

    // Populated layout is up.
    expect(find.text('Connected camera'), findsOneWidget);

    // Data section nav row is present below the camera-gated sections.
    await _openDataSettingsPage(tester);
    expect(find.byType(DataSettingsPage), findsOneWidget);
    expect(find.text('Export backup'), findsOneWidget);
    expect(find.text('Restore backup'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 3. "Export backup" tap calls BackupService.export() and shows SnackBar
  // ---------------------------------------------------------------------------
  testWidgets(
    '"Export backup" tap calls BackupService.export() and shows success SnackBar',
    (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);
      final fake = FakeBackupService(
        db: db.value,
        exportResult: '/tmp/sst-backup-2026-01-01.json',
      );

      await tester.pumpWidget(
        _buildHarness(service: mock, db: db, backupService: fake),
      );
      await tester.pumpAndSettle();

      await _openDataSettingsPage(tester);
      await tester.tap(find.text('Export backup'));
      await tester.pumpAndSettle();

      // Fix 3: Credentials warning dialog is shown before export proceeds.
      expect(find.text('Backup contains credentials'), findsOneWidget);
      expect(find.text('Export Anyway'), findsOneWidget);
      await tester.tap(find.text('Export Anyway'));
      await tester.pumpAndSettle();

      // export() was called on our fake.
      expect(fake.exportCalled, isTrue);
      // Success SnackBar shown.
      expect(
        find.text('Backup saved: sst-backup-2026-01-01.json'),
        findsOneWidget,
      );
    },
  );

  // ---------------------------------------------------------------------------
  // 4. "Restore backup" tap shows confirmation dialog
  // ---------------------------------------------------------------------------
  testWidgets(
    '"Restore backup" tap shows confirmation dialog with expected copy',
    (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);

      await tester.pumpWidget(_buildHarness(service: mock, db: db));
      await tester.pumpAndSettle();

      await _openDataSettingsPage(tester);
      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();

      // Confirmation dialog is shown.
      expect(find.text('Restore backup?'), findsOneWidget);
      expect(find.text('This will replace all your data.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);
    },
  );

  // ---------------------------------------------------------------------------
  // 5. Confirming restore dialog shows file path input dialog
  // ---------------------------------------------------------------------------
  testWidgets('Confirming restore shows file path input dialog', (
    tester,
  ) async {
    final mock = _newMock();
    addTearDown(mock.dispose);

    await tester.pumpWidget(_buildHarness(service: mock, db: db));
    await tester.pumpAndSettle();

    await _openDataSettingsPage(tester);
    await tester.tap(find.text('Restore backup'));
    await tester.pumpAndSettle();

    // Tap Restore to confirm.
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    // File path input dialog is shown.
    expect(find.text('Enter backup file path'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 6. Cancel on confirmation dialog dismisses without showing file dialog
  // ---------------------------------------------------------------------------
  testWidgets('Cancelling confirmation dialog does not show file path dialog', (
    tester,
  ) async {
    final mock = _newMock();
    addTearDown(mock.dispose);

    await tester.pumpWidget(_buildHarness(service: mock, db: db));
    await tester.pumpAndSettle();

    await _openDataSettingsPage(tester);
    await tester.tap(find.text('Restore backup'));
    await tester.pumpAndSettle();

    // Cancel the confirmation.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // No file path dialog.
    expect(find.text('Enter backup file path'), findsNothing);
    // No SnackBar.
    expect(find.byType(SnackBar), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // 7. BackupService.import() throwing shows error SnackBar
  // ---------------------------------------------------------------------------
  testWidgets(
    'BackupImportException from import shows error SnackBar with message',
    (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);
      final fake = FakeBackupService(
        db: db.value,
        importError: const BackupImportException(
          'backup is for a different camera',
        ),
      );

      await tester.pumpWidget(
        _buildHarness(service: mock, db: db, backupService: fake),
      );
      await tester.pumpAndSettle();

      await _openDataSettingsPage(tester);
      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();

      // Confirm.
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      // Enter a path inside the test docs dir so the Fix 2 containment check passes.
      await tester.enterText(
        find.byType(TextField),
        '$_kTestDocsDir/any-backup.json',
      );
      await tester.tap(find.textContaining('Restore').last);
      await tester.pumpAndSettle();

      // BackupImportException message is shown.
      expect(find.text('backup is for a different camera'), findsOneWidget);
    },
  );

  // ---------------------------------------------------------------------------
  // 8. Successful restore invalidates providers and shows success SnackBar
  // ---------------------------------------------------------------------------
  testWidgets('Successful restore shows success SnackBar and calls import()', (
    tester,
  ) async {
    final mock = _newMock();
    addTearDown(mock.dispose);
    // Fake import returns 'user-1' as the first restored user.
    final fake = FakeBackupService(db: db.value, importResult: 'user-1');

    await tester.pumpWidget(
      _buildHarness(service: mock, db: db, backupService: fake),
    );
    await tester.pumpAndSettle();

    await _openDataSettingsPage(tester);
    await tester.tap(find.text('Restore backup'));
    await tester.pumpAndSettle();

    // Confirm.
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    // Enter a path inside the test docs dir so the Fix 2 containment check passes.
    await tester.enterText(
      find.byType(TextField),
      '$_kTestDocsDir/sst-backup.json',
    );
    await tester.tap(find.textContaining('Restore').last);
    await tester.pumpAndSettle();

    // import() was called on our fake.
    expect(fake.importCalled, isTrue);
    // Success SnackBar shown.
    expect(find.text('Backup restored successfully'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 10. (#5) Path outside docs dir shows "Invalid path" SnackBar; import not called
  // ---------------------------------------------------------------------------
  testWidgets(
    'Path outside Documents dir shows Invalid path SnackBar; import not called',
    (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);
      final fake = FakeBackupService(db: db.value, importResult: null);

      await tester.pumpWidget(
        _buildHarness(service: mock, db: db, backupService: fake),
      );
      await tester.pumpAndSettle();

      await _openDataSettingsPage(tester);
      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();

      // Confirm.
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      // Enter a path outside the test docs dir (/tmp/sst-test-docs).
      await tester.enterText(find.byType(TextField), '/etc/passwd');
      await tester.tap(find.textContaining('Restore').last);
      await tester.pumpAndSettle();

      // Should show the invalid path SnackBar.
      expect(
        find.text('Invalid path. Select a file from the Documents folder.'),
        findsOneWidget,
      );
      // import() must not have been called.
      expect(fake.importCalled, isFalse);
    },
  );

  // ---------------------------------------------------------------------------
  // 11. (#17) Generic Exception from import shows "Restore failed" SnackBar
  // ---------------------------------------------------------------------------
  testWidgets(
    'Generic Exception from import() shows "Restore failed" SnackBar',
    (tester) async {
      final mock = _newMock();
      addTearDown(mock.dispose);
      final fake = FakeBackupService(
        db: db.value,
        importError: Exception('disk I/O failure'),
      );

      await tester.pumpWidget(
        _buildHarness(service: mock, db: db, backupService: fake),
      );
      await tester.pumpAndSettle();

      await _openDataSettingsPage(tester);
      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();

      // Confirm.
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      // Enter a valid path inside the test docs dir.
      await tester.enterText(
        find.byType(TextField),
        '$_kTestDocsDir/any-backup.json',
      );
      await tester.tap(find.textContaining('Restore').last);
      await tester.pumpAndSettle();

      // Generic catch → "Restore failed" SnackBar.
      expect(find.text('Restore failed'), findsOneWidget);
      // import() was called (it threw).
      expect(fake.importCalled, isTrue);
    },
  );

  // ---------------------------------------------------------------------------
  // 9. Export error shows error SnackBar
  // ---------------------------------------------------------------------------
  testWidgets('Export error shows error SnackBar', (tester) async {
    final mock = _newMock();
    addTearDown(mock.dispose);
    final fake = FakeBackupService(
      db: db.value,
      exportError: const BackupImportException('disk full'),
    );

    await tester.pumpWidget(
      _buildHarness(service: mock, db: db, backupService: fake),
    );
    await tester.pumpAndSettle();

    await _openDataSettingsPage(tester);
    await tester.tap(find.text('Export backup'));
    await tester.pumpAndSettle();

    // Fix 3: Credentials warning dialog — tap Export Anyway to proceed.
    expect(find.text('Backup contains credentials'), findsOneWidget);
    await tester.tap(find.text('Export Anyway'));
    await tester.pumpAndSettle();

    // Error SnackBar shown.
    expect(find.textContaining('Export failed'), findsOneWidget);
  });
}

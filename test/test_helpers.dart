// Shared test harness. Every BLE / state / page / integration test that
// touches DevDataStore directly or transitively imports this and calls
// `useDevDataStoreReset()` at the top of its `main()` so the
// process-global store can't leak across tests when `flutter test` runs
// them in the same isolate.
//
// `dev_data_store_test.dart` deliberately does NOT use this — it owns its
// own `setUp` because that file is the unit under test for the reset
// behavior itself.

import 'package:flutter_test/flutter_test.dart';
import 'package:scout_camera/ble/dev_data_store.dart';

/// Registers a `setUp` that resets the process-global [DevDataStore]
/// before every test in the enclosing group / file.
void useDevDataStoreReset() {
  setUp(() {
    DevDataStore.instance.reset();
  });
}

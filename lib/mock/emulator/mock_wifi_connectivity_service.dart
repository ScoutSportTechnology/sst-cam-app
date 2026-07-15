import 'dart:async';

import '../../core/wifi/wifi_connectivity_service.dart';

/// Emulated phone-Wi-Fi observer for the dev backend + tests. Starts "available"
/// (the emulator's phone is always on Wi-Fi), and [emit] lets a test script a
/// loss/recovery to exercise the shared-WiFi auto-revert (U5).
class MockWifiConnectivityService implements WifiConnectivityService {
  MockWifiConnectivityService({bool initiallyAvailable = true})
    : _available = initiallyAvailable;

  final _controller = StreamController<bool>.broadcast();
  bool _available;

  /// Push a new phone-Wi-Fi availability state to listeners.
  void emit(bool available) {
    _available = available;
    _controller.add(available);
  }

  @override
  Stream<bool> wifiAvailable() async* {
    // Replay the current state on listen (mirrors the native seed), then follow
    // transitions.
    yield _available;
    yield* _controller.stream;
  }

  Future<void> dispose() => _controller.close();
}

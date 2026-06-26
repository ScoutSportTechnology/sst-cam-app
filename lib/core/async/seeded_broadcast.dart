import 'dart:async';

/// A broadcast stream that replays its most recent value to every new
/// subscriber ("current-value" semantics).
///
/// Plain `StreamController.broadcast()` drops events that fire before a listener
/// attaches, so a late subscriber sees nothing until the *next* event. That is
/// the root of the hardware bring-up race class: the real BLE/WiFi services hand
/// out raw broadcast streams, so a widget that subscribes after a state change
/// (connection, telemetry, match, wifi, discovery) misses it entirely and shows
/// stale UI. The emulator mocks already replay (via `Stream.multi` / `async*`
/// snapshots), which is exactly why those races were invisible in emulation.
///
/// [SeededBroadcast] is the single primitive both the real impls and (where
/// practical) the mocks route through, so replay semantics cannot diverge again.
/// New subscribers synchronously receive the last value (if any) before live
/// events, with no gap between the replay and the live subscription.
class SeededBroadcast<T> {
  SeededBroadcast([T? initial]) : _last = initial, _hasValue = initial != null;

  final _controller = StreamController<T>.broadcast();
  T? _last;
  bool _hasValue;

  /// The most recently emitted value, or null if nothing has been added yet.
  T? get value => _last;

  bool get hasValue => _hasValue;

  bool get isClosed => _controller.isClosed;

  /// Emits [event] to current subscribers and stores it as the value replayed to
  /// future subscribers.
  void add(T event) {
    if (_controller.isClosed) return;
    _last = event;
    _hasValue = true;
    _controller.add(event);
  }

  /// A stream that replays the current value (if any) to each new listener, then
  /// forwards live events. Uses [Stream.multi] so the replay and the live
  /// subscription happen in one synchronous step — no event can slip through the
  /// gap a naive `async*` (yield-then-yield*) would leave.
  Stream<T> get stream => Stream<T>.multi((controller) {
    if (_hasValue) controller.add(_last as T);
    final sub = _controller.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = sub.cancel;
  });

  Future<void> close() => _controller.close();
}

// Pure, side-effect-free seams factored out of BleServiceImpl so the trickiest
// bits of the BLE plumbing — scan start/stop latching and inbound-frame
// classification — are unit-testable without a real adapter or platform stack.

/// Latches the FlutterBluePlus `isScanning` boolean stream into a single
/// "the scan has ended" signal.
///
/// FlutterBluePlus can replay a stale `false` at subscribe time, before the
/// scan has begun. Tearing down on that would clear the slot a fresh
/// `startScan` just claimed. This tracker only reports "ended" once a `true`
/// has actually been observed.
class ScanLifecycleTracker {
  bool _sawScanning = false;

  /// Feed each `isScanning` value. Returns true exactly when this transition
  /// means the scan has ended and teardown should run (a `false` that follows
  /// an observed `true`). A `false` seen before any `true` returns false.
  bool onScanningChanged(bool scanning) {
    if (scanning) {
      _sawScanning = true;
      return false;
    }
    return _sawScanning;
  }
}

/// Classification of an inbound BLE frame, keyed off `total_chunks` (mirrors
/// the firmware convention): 0 = a ChunkAck (outbound flow-control), 1 = a
/// single-chunk payload (fast path), >=2 = one chunk of a multi-chunk payload.
enum InboundFrameKind { ack, singlePayload, multiPayload }

/// Pure mapping from a frame's `total_chunks` to its [InboundFrameKind].
InboundFrameKind classifyInboundFrame(int totalChunks) {
  if (totalChunks == 0) return InboundFrameKind.ack;
  if (totalChunks == 1) return InboundFrameKind.singlePayload;
  return InboundFrameKind.multiPayload;
}

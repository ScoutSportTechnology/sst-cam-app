import Flutter
import UIKit

/// No-op StreamHandler for the WiFi Direct EventChannel on iOS.
/// Immediately closes the stream on listen — WiFi Direct is Android-only.
/// A concrete handler (not nil) is required; nil unregisters the handler and
/// causes MissingPluginException when Dart subscribes.
private class _NoOpStreamHandler: NSObject, FlutterStreamHandler {
  func onListen(withArguments arguments: Any?,
                eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    events(FlutterEndOfEventStream)
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { nil }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Stored as instance properties so they remain alive for the application lifetime.
  // FlutterMethodChannel and FlutterEventChannel do not retain themselves; the only
  // strong reference is the one the owner holds. Local variables are released at
  // end-of-scope, silently unregistering the handlers.
  private var wifiMethodChannel: FlutterMethodChannel?
  private var wifiEventChannel: FlutterEventChannel?
  private let wifiStreamHandler = _NoOpStreamHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // No-op stubs for com.sst.sstcam/wifi{,/state} — WiFi Direct is Android-only.
    // result(nil) on the method channel avoids MissingPluginException on any code
    // path that reaches the channel before the Platform.isIOS guard in WifiServiceImpl.
    if let controller = window?.rootViewController as? FlutterViewController {
      wifiMethodChannel = FlutterMethodChannel(
        name: "com.sst.sstcam/wifi",
        binaryMessenger: controller.binaryMessenger
      )
      wifiMethodChannel?.setMethodCallHandler { (_: FlutterMethodCall, result: @escaping FlutterResult) in
        result(nil)
      }

      // EventChannel stub — a nil StreamHandler unregisters the handler entirely
      // and causes MissingPluginException on subscribe. Use a concrete no-op handler
      // that immediately closes the stream via FlutterEndOfEventStream.
      wifiEventChannel = FlutterEventChannel(
        name: "com.sst.sstcam/wifi/state",
        binaryMessenger: controller.binaryMessenger
      )
      wifiEventChannel?.setStreamHandler(wifiStreamHandler)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

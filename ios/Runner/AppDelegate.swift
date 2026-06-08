import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // Retained as a property so ARC does not release the channel before the
  // closure captures it. Local variables are released at end-of-scope.
  private var wifiMethodChannel: FlutterMethodChannel?
  private var wifiEventChannel: FlutterEventChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // No-op stubs for com.sst.sstcam/wifi{,/state} — WiFi Direct is Android-only.
    // Silent result(nil) avoids MissingPluginException on any code path that
    // reaches these channels before the Platform.isIOS guard in WifiServiceImpl.
    if let controller = window?.rootViewController as? FlutterViewController {
      wifiMethodChannel = FlutterMethodChannel(
        name: "com.sst.sstcam/wifi",
        binaryMessenger: controller.binaryMessenger
      )
      wifiMethodChannel?.setMethodCallHandler { (_: FlutterMethodCall, result: @escaping FlutterResult) in
        result(nil)
      }

      // EventChannel stub — required because WifiP2pChannel.stateStream calls
      // receiveBroadcastStream() which triggers onListen on the native side.
      // Without a registered StreamHandler, Flutter throws MissingPluginException.
      wifiEventChannel = FlutterEventChannel(
        name: "com.sst.sstcam/wifi/state",
        binaryMessenger: controller.binaryMessenger
      )
      wifiEventChannel?.setStreamHandler(nil)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

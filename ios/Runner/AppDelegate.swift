import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // No-op stub for com.sst.sstcam/wifi — WiFi Direct is Android-only.
    // Returning FlutterMethodNotImplemented prevents MissingPluginException
    // if any code path reaches this channel before the platform guard fires.
    if let controller = window?.rootViewController as? FlutterViewController {
      let wifiChannel = FlutterMethodChannel(
        name: "com.sst.sstcam/wifi",
        binaryMessenger: controller.binaryMessenger
      )
      wifiChannel.setMethodCallHandler { (_: FlutterMethodCall, result: @escaping FlutterResult) in
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

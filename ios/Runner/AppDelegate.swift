import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Adds one platform channel the `camera` plugin has no equivalent for:
    // the phone's real horizontal field of view, read directly from
    // AVFoundation rather than assumed as a constant. See
    // mobile/lib/src/core/camera/camera_intrinsics_reader.dart.
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "mdf_tracker/camera_intrinsics",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        AppDelegate.handleCameraIntrinsics(call: call, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// [cameraId] is the id the `camera` plugin already uses as
  /// `CameraDescription.name` on iOS - the capturing device's own `uniqueID`
  /// - so the caller can pass that straight through without any translation.
  ///
  /// Returns nil when the id does not resolve to a device, so the caller can
  /// fall back to its configured default rather than guessing.
  private static func handleCameraIntrinsics(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "horizontalFovDegrees" else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard
      let arguments = call.arguments as? [String: Any],
      let cameraId = arguments["cameraId"] as? String,
      let device = AVCaptureDevice(uniqueID: cameraId)
    else {
      result(nil)
      return
    }

    result(Double(device.activeFormat.videoFieldOfView))
  }
}

import 'package:flutter/services.dart';

/// Reads the phone's actual horizontal field of view for a given camera from
/// native code - Camera2's sensor-size and focal-length characteristics on
/// Android, AVFoundation's own field-of-view figure on iOS. The Flutter
/// `camera` plugin exposes neither (`CameraDescription` carries only a name,
/// lens direction, sensor orientation and a coarse wide/tele/ultrawide
/// label), so this talks to a small platform channel added alongside it -
/// see MainActivity.kt and AppDelegate.swift.
class CameraIntrinsicsReader {
  static const _channel = MethodChannel('mdf_tracker/camera_intrinsics');

  /// [cameraId] is `CameraDescription.name` - the `camera` plugin already
  /// sets it to whichever id each platform's native side expects here (a
  /// Camera2 camera id on Android, an `AVCaptureDevice.uniqueID` on iOS), so
  /// it can be passed straight through with no translation.
  ///
  /// Returns null on any failure - unusual hardware missing the needed
  /// characteristics, an id that fails to resolve, or a platform build that
  /// predates this channel - so the caller can fall back to its configured
  /// default rather than guessing.
  Future<double?> horizontalFovDegrees(String cameraId) async {
    try {
      final result = await _channel.invokeMethod<double>(
        'horizontalFovDegrees',
        {'cameraId': cameraId},
      );
      return (result != null && result.isFinite && result > 0) ? result : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

import 'dart:ui';

import '../location/session_location.dart';
import 'device_orientation.dart';
import 'geo_projection.dart';
import '../imu/motion_estimator.dart';

/// The estimated real-world position of the tracked object.
class TargetGeoEstimate {
  const TargetGeoEstimate({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  Map<String, dynamic> toJson() => {
        'targetLatitude': double.parse(latitude.toStringAsFixed(6)),
        'targetLongitude': double.parse(longitude.toStringAsFixed(6)),
      };
}

/// Combines the session's origin GPS fix, the phone's current attitude and a
/// tracked pixel into an estimated geographic point for the target.
///
/// This is the feature the spec describes as optional: geolocating what the
/// camera sees using phone GPS, camera orientation, field of view and the
/// target's position in the frame, assuming the target sits on the ground.
/// Every input can be missing or the geometry can be unusable (camera
/// pointing above the horizon, target implausibly far away), in which case
/// this returns null - a degraded estimate would be worse than none, since
/// there is no way for a consumer to tell a bad estimate from a good one.
class TargetGeoLocator {
  TargetGeoLocator({
    required this.origin,
    this.assumedCameraHeightMeters = 1.4,
    double horizontalFovDegrees = 67,
    double verticalFovDegrees = 50,
    GeoProjection projection = const GeoProjection(),
  })  : _projection = projection,
        _angles = MotionEstimator(
          horizontalFovDegrees: horizontalFovDegrees,
          verticalFovDegrees: verticalFovDegrees,
        );

  /// Where the session started. Used as the phone's position for every
  /// frame: re-reading GPS per frame would cost battery for a precision GPS
  /// drift will not resolve during a tracking run that lasts tens of seconds.
  final SessionLocation origin;

  /// Height of the camera above the ground the target is assumed to stand
  /// on, in metres. No sensor gives this directly - configurable in Settings
  /// for a user who wants to correct the default toward how they actually
  /// hold the phone.
  final double assumedCameraHeightMeters;

  final GeoProjection _projection;
  final MotionEstimator _angles;

  TargetGeoEstimate? estimate({
    required CameraAttitude attitude,
    required Rect boxInImageSpace,
    required Size imageSize,
  }) {
    if (!CameraAttitudeEstimator.bearingIsWellDefined(attitude.elevationDegrees)) {
      return null;
    }

    final centre = boxInImageSpace.center;
    final imageCentre = Offset(imageSize.width / 2, imageSize.height / 2);
    final pixelOffset = centre - imageCentre;

    final angle = _angles.angleOfPixelOffset(pixelOffset, imageSize);

    final point = _projection.project(
      originLatitude: origin.latitude,
      originLongitude: origin.longitude,
      cameraHeightMeters: assumedCameraHeightMeters,
      cameraElevationDegrees: attitude.elevationDegrees,
      cameraAzimuthDegrees: attitude.azimuthDegrees,
      targetAngleXDegrees: angle.dx,
      targetAngleYDegrees: angle.dy,
    );

    if (point == null) return null;
    return TargetGeoEstimate(latitude: point.latitude, longitude: point.longitude);
  }
}

import 'dart:math' as math;

/// A computed geographic point, along with the inputs that produced it so a
/// consumer can judge how much to trust it.
class TargetGeoPoint {
  const TargetGeoPoint({
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.bearingDegrees,
  });

  final double latitude;
  final double longitude;

  /// Horizontal distance from the phone to the target, under the ground-plane
  /// assumption below.
  final double distanceMeters;

  final double bearingDegrees;
}

/// Projects a tracked pixel onto a geographic point on the ground.
///
/// This is the technique the spec describes: given where the phone is (GPS),
/// which way its camera is pointing (elevation and bearing), how wide its
/// view is (field of view), and where the target sits in the frame, compute
/// the target's real-world coordinates. It assumes the target sits on the
/// ground at a known height below the camera - there is no depth sensor here,
/// so that assumption is unavoidable, and it is the same one the spec's own
/// description of the technique relies on.
///
/// Roll is ignored, which the spec explicitly permits: the camera's tilt
/// around its own viewing axis rotates the image but does not change which
/// compass direction or elevation angle the centre of the frame points at.
class GeoProjection {
  const GeoProjection();

  /// Mean Earth radius, adequate for the sub-kilometre distances this
  /// feature deals with; the ellipsoid correction is smaller than GPS error.
  static const double _earthRadiusMeters = 6371000;

  /// Angle below the horizon past which the ground-plane assumption is
  /// trusted. Shallower than this, a tiny error in the measured elevation
  /// angle turns into a huge error in distance (distance scales with
  /// 1/tan(angle), which blows up as the angle approaches zero) - the classic
  /// failure mode of any camera-to-ground-range technique.
  static const double _minElevationBelowHorizonDegrees = 3;

  /// Beyond this the ground-plane estimate is treated as unreliable rather
  /// than returned as if it were precise.
  static const double _maxDistanceMeters = 500;

  /// Returns null when the geometry does not support an estimate: the camera
  /// is not looking far enough below the horizon, or the projected point
  /// would be implausibly far away.
  TargetGeoPoint? project({
    required double originLatitude,
    required double originLongitude,
    required double cameraHeightMeters,
    required double cameraElevationDegrees,
    required double cameraAzimuthDegrees,
    required double targetAngleXDegrees,
    required double targetAngleYDegrees,
  }) {
    // Pixels below image centre point the target further down than the
    // camera's own boresight, so they lower the effective elevation angle;
    // pixels to the right rotate the bearing clockwise.
    final targetElevation = cameraElevationDegrees - targetAngleYDegrees;
    final targetBearing = _normalize360(cameraAzimuthDegrees + targetAngleXDegrees);

    if (targetElevation > -_minElevationBelowHorizonDegrees) {
      return null;
    }

    final distance = cameraHeightMeters / math.tan(_toRadians(-targetElevation));
    if (!distance.isFinite || distance <= 0 || distance > _maxDistanceMeters) {
      return null;
    }

    final destination = destinationPoint(
      latitude: originLatitude,
      longitude: originLongitude,
      distanceMeters: distance,
      bearingDegrees: targetBearing,
    );

    return TargetGeoPoint(
      latitude: destination.$1,
      longitude: destination.$2,
      distanceMeters: distance,
      bearingDegrees: targetBearing,
    );
  }

  /// Standard great-circle destination formula: given a start point, a
  /// bearing and a distance, where do you end up. Exposed separately from
  /// [project] because it is useful on its own and easy to verify against
  /// known reference values (1 degree of latitude is very close to 111.32 km).
  (double, double) destinationPoint({
    required double latitude,
    required double longitude,
    required double distanceMeters,
    required double bearingDegrees,
  }) {
    final angularDistance = distanceMeters / _earthRadiusMeters;
    final bearing = _toRadians(bearingDegrees);
    final lat1 = _toRadians(latitude);
    final lon1 = _toRadians(longitude);

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angularDistance) +
          math.cos(lat1) * math.sin(angularDistance) * math.cos(bearing),
    );

    final lon2 = lon1 +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(lat1),
          math.cos(angularDistance) - math.sin(lat1) * math.sin(lat2),
        );

    return (lat2 * 180 / math.pi, _normalizeLongitude(lon2 * 180 / math.pi));
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  static double _normalize360(double degrees) {
    final wrapped = degrees % 360;
    return wrapped < 0 ? wrapped + 360 : wrapped;
  }

  static double _normalizeLongitude(double degrees) {
    var value = degrees;
    while (value > 180) {
      value -= 360;
    }
    while (value < -180) {
      value += 360;
    }
    return value;
  }
}

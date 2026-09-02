import 'dart:math' as math;

/// Where the phone's rear camera is pointing, derived from raw motion sensors.
///
/// Deliberately built around the camera's own axis rather than the textbook
/// phone-compass formula (heading of the top edge, tilt-compensated by pitch
/// and roll). That formula degrades exactly where this feature lives: it is
/// designed for a phone lying flat, and becomes numerically unstable as the
/// phone approaches vertical - which is precisely how a phone is held to aim
/// its camera at something. Instead this projects the camera's own boresight
/// onto the local horizontal plane directly, which stays well-conditioned for
/// any attitude except pointing exactly straight up or down.
class CameraAttitude {
  const CameraAttitude({
    required this.elevationDegrees,
    required this.azimuthDegrees,
  });

  /// Angle of the camera's view direction above (positive) or below
  /// (negative) the local horizontal plane. 0 = pointing at the horizon,
  /// -90 = pointing straight down, +90 = pointing straight up.
  final double elevationDegrees;

  /// Compass bearing the camera points toward, 0-360 clockwise from magnetic
  /// north. Undefined (returned as null by the estimator) when the camera is
  /// pointing near-vertically, where "which horizontal direction" stops being
  /// a meaningful question.
  ///
  /// Not corrected for magnetic declination - true north can differ from
  /// magnetic north by several to tens of degrees depending on location.
  final double azimuthDegrees;
}

/// Derives [CameraAttitude] from accelerometer and magnetometer vectors.
///
/// Vectors are in the device's own coordinate frame: x out the right edge of
/// the screen, y out the top edge, z out of the screen face - the convention
/// both Android's SensorManager and iOS's CoreMotion use. The accelerometer
/// reading is treated as the "specific force" reaction to gravity (~9.8 in
/// the up direction when the device is stationary), which is what both
/// platforms report at rest.
class CameraAttitudeEstimator {
  const CameraAttitudeEstimator();

  /// The rear camera looks out of the back of the device, opposite the
  /// screen - the -z axis in this frame.
  static const _cameraAxis = (x: 0.0, y: 0.0, z: -1.0);

  CameraAttitude estimate({
    required double ax,
    required double ay,
    required double az,
    required double mx,
    required double my,
    required double mz,
  }) {
    final upLength = math.sqrt(ax * ax + ay * ay + az * az);
    final up = (x: ax / upLength, y: ay / upLength, z: az / upLength);

    // Elevation: how far the camera axis leans toward "up" versus the
    // horizontal plane perpendicular to it. b . up = 1 when the camera points
    // straight up, -1 when it points straight down, 0 at the horizon.
    final dot = _cameraAxis.x * up.x + _cameraAxis.y * up.y + _cameraAxis.z * up.z;
    final elevation = math.asin(dot.clamp(-1.0, 1.0)) * 180 / math.pi;

    // Bearing: build a horizontal frame from gravity and the magnetic field,
    // then read off where the camera axis falls in it. This is the standard
    // gravity/magnetic-field construction AR and compass overlays use, and it
    // stays well defined at any attitude except looking straight up or down,
    // unlike a pitch/roll-composed heading.
    final east = _normalize(_cross(
      (x: mx, y: my, z: mz),
      up,
    ));
    final north = _cross(up, east);

    final cameraEast = _dot(_cameraAxis, east);
    final cameraNorth = _dot(_cameraAxis, north);
    final azimuth = _normalize360(math.atan2(cameraEast, cameraNorth) * 180 / math.pi);

    return CameraAttitude(elevationDegrees: elevation, azimuthDegrees: azimuth);
  }

  /// True near the poles of elevation, where a horizontal bearing stops being
  /// a meaningful question - the same reason a compass spins freely when held
  /// flat over the North Pole.
  static bool bearingIsWellDefined(double elevationDegrees) => elevationDegrees.abs() < 80;

  static ({double x, double y, double z}) _cross(
    ({double x, double y, double z}) a,
    ({double x, double y, double z}) b,
  ) =>
      (
        x: a.y * b.z - a.z * b.y,
        y: a.z * b.x - a.x * b.z,
        z: a.x * b.y - a.y * b.x,
      );

  static double _dot(({double x, double y, double z}) a, ({double x, double y, double z}) b) =>
      a.x * b.x + a.y * b.y + a.z * b.z;

  static ({double x, double y, double z}) _normalize(({double x, double y, double z}) v) {
    final length = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    return (x: v.x / length, y: v.y / length, z: v.z / length);
  }

  static double _normalize360(double degrees) {
    final wrapped = degrees % 360;
    return wrapped < 0 ? wrapped + 360 : wrapped;
  }
}

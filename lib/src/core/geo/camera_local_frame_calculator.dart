import 'dart:math' as math;
import 'dart:ui';

/// Real-world position of the tracked object in the camera's own local
/// frame, in metres: X is the lateral offset (positive to the right of the
/// local frame's forward axis), Y is the fixed camera height above the
/// ground, Z is forward depth. See camera.md for the derivation.
class LocalFramePosition {
  const LocalFramePosition({required this.x, required this.y, required this.z});

  final double x;
  final double y;
  final double z;

  Map<String, dynamic> toJson() => {
        'targetX': double.parse(x.toStringAsFixed(3)),
        'targetY': double.parse(y.toStringAsFixed(3)),
        'targetZ': double.parse(z.toStringAsFixed(3)),
      };
}

/// Ray-plane intersection described in camera.md: the tracked pixel's
/// angular offset from the optical axis is fused with the phone's own
/// pitch/yaw rotation (accumulated since the tracker was seeded - see
/// [ImuMotionCompensator]) to get the *total* angle from the local frame's
/// forward axis out to the target, and that ray is then intersected with the
/// ground plane at the fixed camera height to get metric X/Z.
///
/// Fusing measured rotation with the pixel angle - rather than assuming a
/// level, unmoving camera, as a plain pinhole projection would - is what
/// keeps the estimate stable while the phone's own orientation drifts: a
/// target that has not actually moved keeps the same total angle no matter
/// how the phone rotates around it.
///
/// Unlike [TargetGeoLocator], this needs no GPS fix and no compass reading -
/// only the frame size, the gyro's rotation since seed, and where the
/// tracked box sits in the frame - so it is available on every tracked frame.
class CameraLocalFrameCalculator {
  CameraLocalFrameCalculator({
    required double imageWidth,
    required double imageHeight,
    this.cameraHeightMeters = 0.5,
    double fovHorizontalDegrees = defaultFovHorizontalDegrees,
  })  : _cx = imageWidth / 2,
        _cy = imageHeight / 2,
        _fx = imageWidth / (2 * math.tan(_toRadians(fovHorizontalDegrees) / 2));

  /// Used when the phone's actual horizontal FOV cannot be measured from its
  /// camera hardware - see `CameraIntrinsicsReader`. A reasonable estimate
  /// for a typical phone's rear main lens, per camera.md.
  static const double defaultFovHorizontalDegrees = 78.4;

  /// Fixed height of the camera above the ground, in metres.
  final double cameraHeightMeters;

  final double _cx;
  final double _cy;
  final double _fx;

  /// Square pixels assumed, per camera.md.
  double get _fy => _fx;

  /// Smallest total-pitch magnitude treated as non-zero - camera.md's own
  /// guard against dividing by tan(0) when the fused ray points exactly at
  /// the horizon.
  static const double _minPitchMagnitudeRadians = 1e-6;

  /// [targetPixel] is the tracked box centre in raw camera-image pixels.
  ///
  /// [yawRadians]/[pitchRadians] are the phone's own rotation integrated
  /// since the tracker was last seeded - `ImuMotionCompensator.yawRadians`
  /// and `.pitchRadians` directly, in that class's convention: positive yaw
  /// is the camera panning right, positive pitch is the camera tipping to
  /// point further upward. [pitchRadians] is negated internally to get the
  /// downward depression angle the ground-plane intersection needs. Both
  /// default to zero, which reproduces a level, unmoving camera.
  LocalFramePosition calculate(
    Offset targetPixel, {
    double yawRadians = 0,
    double pitchRadians = 0,
  }) {
    final alphaH = math.atan((targetPixel.dx - _cx) / _fx);
    final alphaV = math.atan((targetPixel.dy - _cy) / _fy);

    var totalPitch = -pitchRadians + alphaV;
    final totalYaw = yawRadians + alphaH;

    if (totalPitch.abs() < _minPitchMagnitudeRadians) {
      totalPitch = _minPitchMagnitudeRadians;
    }

    final z = cameraHeightMeters / math.tan(totalPitch);
    final x = z * math.tan(totalYaw);

    return LocalFramePosition(x: x, y: cameraHeightMeters, z: z);
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}

import 'dart:math' as math;
import 'dart:ui';

/// Turns a phone rotation rate into how far the camera's view appears to have
/// swept across the frame, using a pinhole camera model.
///
/// Pure and stateless on purpose: everything here is testable with synthetic
/// numbers, which matters because the sensor plumbing around it cannot be
/// exercised without a physical device (see [ImuMotionCompensator]).
class MotionEstimator {
  const MotionEstimator({
    required this.horizontalFovDegrees,
    required this.verticalFovDegrees,
  });

  final double horizontalFovDegrees;
  final double verticalFovDegrees;

  /// Focal length in pixels for a sensor of [widthPx] under this horizontal FOV.
  /// Standard pinhole relation: f = (w/2) / tan(FOV/2).
  double focalLengthXPx(double widthPx) =>
      (widthPx / 2) / math.tan(_toRadians(horizontalFovDegrees) / 2);

  double focalLengthYPx(double heightPx) =>
      (heightPx / 2) / math.tan(_toRadians(verticalFovDegrees) / 2);

  /// How far the scene appears to shift, in image pixels, over [elapsed] given
  /// an instantaneous angular velocity in radians/second around the phone's
  /// pitch axis ([angularVelocityPitch]) and yaw axis ([angularVelocityYaw]).
  ///
  /// Sign convention: a positive yaw rate (phone turning right) sweeps the
  /// camera's view rightward, which means scene content moves left in the
  /// image - hence the negation on dx. A positive pitch rate (phone tipping
  /// so the top moves away from the user) sweeps the view upward, moving scene
  /// content down - hence dy is not negated. Both follow the same convention
  /// Android's TYPE_GYROSCOPE and iOS's CMGyroData use for their axes.
  ///
  /// Uses a zero-order hold (the instantaneous rate times the elapsed time)
  /// rather than integrating a series of samples, which is accurate enough
  /// over the few tens of milliseconds between camera frames and avoids
  /// keeping a sample history.
  Offset sceneShiftFor({
    required double angularVelocityYaw,
    required double angularVelocityPitch,
    required Duration elapsed,
    required Size frameSize,
  }) {
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final angleYaw = angularVelocityYaw * seconds;
    final anglePitch = angularVelocityPitch * seconds;

    final dx = -focalLengthXPx(frameSize.width) * math.tan(angleYaw);
    final dy = focalLengthYPx(frameSize.height) * math.tan(anglePitch);

    return Offset(dx, dy);
  }

  /// The angular offset of an image point from the boresight (image centre),
  /// under this pinhole model. Used to turn "the target is at this pixel"
  /// into "the target is this many degrees off where the camera is pointing".
  ///
  /// [pixelOffsetFromCentre] is target position minus image centre, so a
  /// point to the right of centre has a positive x, and one below centre has
  /// a positive y (standard image coordinates, y grows downward).
  Offset angleOfPixelOffset(Offset pixelOffsetFromCentre, Size frameSize) {
    final fx = focalLengthXPx(frameSize.width);
    final fy = focalLengthYPx(frameSize.height);
    final angleX = math.atan(pixelOffsetFromCentre.dx / fx);
    final angleY = math.atan(pixelOffsetFromCentre.dy / fy);
    return Offset(_toDegrees(angleX), _toDegrees(angleY));
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
  static double _toDegrees(double radians) => radians * 180 / math.pi;
}

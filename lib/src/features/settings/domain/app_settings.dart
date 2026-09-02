import 'dart:ui';

import '../../tracking/domain/camera_lens.dart';
import '../../tracking/domain/tracker_algorithm.dart';

/// User-tunable knobs from the Settings screen.
class AppSettings {
  const AppSettings({
    this.algorithm = TrackerAlgorithm.mil,
    this.lens = CameraLens.back,
    this.boxColor = const Color(0xFF00E676),
    this.processingScale = 0.5,
    this.cameraHorizontalFovDegrees = defaultHorizontalFov,
    this.assumedCameraHeightMeters = defaultCameraHeight,
  });

  /// Tracker used to seed a session.
  final TrackerAlgorithm algorithm;

  /// Front or back camera.
  final CameraLens lens;

  /// Colour of the bounding box drawn over the preview.
  final Color boxColor;

  /// Frames are downscaled by this factor before hitting the tracker. Lower is
  /// faster, at the cost of precision on small targets.
  final double processingScale;

  /// Horizontal field of view of the rear camera, in degrees. No device
  /// database is available, so this is a reasonable default for a typical
  /// phone's main rear lens - adjustable here for anyone who knows their
  /// device's actual spec and wants the target geo-location estimate to be
  /// more accurate.
  final double cameraHorizontalFovDegrees;

  /// Assumed height of the camera above the ground the target stands on, in
  /// metres, used by the same estimate. No sensor gives this directly.
  final double assumedCameraHeightMeters;

  static const double minProcessingScale = 0.25;
  static const double maxProcessingScale = 1.0;

  static const double defaultHorizontalFov = 67.0;
  static const double minHorizontalFov = 40.0;
  static const double maxHorizontalFov = 100.0;

  static const double defaultCameraHeight = 1.4;
  static const double minCameraHeight = 0.5;
  static const double maxCameraHeight = 2.2;

  AppSettings copyWith({
    TrackerAlgorithm? algorithm,
    CameraLens? lens,
    Color? boxColor,
    double? processingScale,
    double? cameraHorizontalFovDegrees,
    double? assumedCameraHeightMeters,
  }) {
    return AppSettings(
      algorithm: algorithm ?? this.algorithm,
      lens: lens ?? this.lens,
      boxColor: boxColor ?? this.boxColor,
      processingScale: processingScale ?? this.processingScale,
      cameraHorizontalFovDegrees:
          cameraHorizontalFovDegrees ?? this.cameraHorizontalFovDegrees,
      assumedCameraHeightMeters:
          assumedCameraHeightMeters ?? this.assumedCameraHeightMeters,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.algorithm == algorithm &&
      other.lens == lens &&
      other.boxColor.toARGB32() == boxColor.toARGB32() &&
      other.processingScale == processingScale &&
      other.cameraHorizontalFovDegrees == cameraHorizontalFovDegrees &&
      other.assumedCameraHeightMeters == assumedCameraHeightMeters;

  @override
  int get hashCode => Object.hash(
        algorithm,
        lens,
        boxColor.toARGB32(),
        processingScale,
        cameraHorizontalFovDegrees,
        assumedCameraHeightMeters,
      );
}

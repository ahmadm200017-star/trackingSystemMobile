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

  static const double minProcessingScale = 0.25;
  static const double maxProcessingScale = 1.0;

  AppSettings copyWith({
    TrackerAlgorithm? algorithm,
    CameraLens? lens,
    Color? boxColor,
    double? processingScale,
  }) {
    return AppSettings(
      algorithm: algorithm ?? this.algorithm,
      lens: lens ?? this.lens,
      boxColor: boxColor ?? this.boxColor,
      processingScale: processingScale ?? this.processingScale,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.algorithm == algorithm &&
      other.lens == lens &&
      other.boxColor.toARGB32() == boxColor.toARGB32() &&
      other.processingScale == processingScale;

  @override
  int get hashCode =>
      Object.hash(algorithm, lens, boxColor.toARGB32(), processingScale);
}

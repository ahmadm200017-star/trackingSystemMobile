import 'dart:ui';

import '../data/tracking_socket.dart';
import '../domain/frame_geometry.dart';
import '../domain/tracker_algorithm.dart';
import '../domain/tracking_status.dart';

/// Everything the tracking screen renders from.
class TrackingState {
  const TrackingState({
    this.cameraReady = false,
    this.status = TrackingStatus.idle,
    this.algorithm = TrackerAlgorithm.mil,
    this.box,
    this.geometry,
    this.fps = 0,
    this.socketStatus = SocketStatus.disconnected,
    this.sessionNumber,
    this.droppedFrames = 0,
    this.errorMessage,
    this.objectDescription,
    this.describing = false,
    this.descriptionError,
    this.descriptionGrayscale = false,
    this.imuActive = false,
    this.targetLatitude,
    this.targetLongitude,
    this.imuRecoveryUsed = false,
  });

  /// The `CameraController` finished initialising and the preview can be shown.
  final bool cameraReady;

  final TrackingStatus status;
  final TrackerAlgorithm algorithm;

  /// Latest tracked box in full-resolution camera-image coordinates.
  final Rect? box;

  /// Rotation/mirroring needed to map [box] onto the preview.
  final FrameGeometry? geometry;

  final double fps;
  final SocketStatus socketStatus;

  /// Backend-issued session number, shown once a session is live.
  final String? sessionNumber;

  final int droppedFrames;
  final String? errorMessage;

  /// What Groq said the tracked object is, once the backend has answered.
  final String? objectDescription;

  /// The first-frame crop is in flight. Purely cosmetic - tracking never waits on it.
  final bool describing;

  /// Why the description could not be produced, shown on the HUD. Without this the
  /// failure is invisible on a release build, which is exactly where it matters.
  final String? descriptionError;

  /// The colour conversion fell back to luminance, so the description will not
  /// mention colour. Surfaced so a degraded result is not mistaken for a broken one.
  final bool descriptionGrayscale;

  /// Whether the gyroscope actually reported a reading this session. Some
  /// devices have none; the HUD shows this rather than assuming it does.
  final bool imuActive;

  /// Most recent estimated real-world position of the tracked object. Null
  /// whenever the geometry does not support an estimate on the current frame.
  final double? targetLatitude;
  final double? targetLongitude;

  /// The tracker lost the target and a gyroscope-informed re-seed recovered
  /// it without the user re-tapping. Shown briefly so a recovery is visible
  /// rather than looking identical to tracking that was never interrupted.
  final bool imuRecoveryUsed;

  bool get isSessionLive => sessionNumber != null;

  TrackingState copyWith({
    bool? cameraReady,
    TrackingStatus? status,
    TrackerAlgorithm? algorithm,
    Rect? box,
    bool clearBox = false,
    FrameGeometry? geometry,
    double? fps,
    SocketStatus? socketStatus,
    String? sessionNumber,
    bool clearSessionNumber = false,
    int? droppedFrames,
    String? errorMessage,
    bool clearError = false,
    String? objectDescription,
    bool clearObjectDescription = false,
    bool? describing,
    String? descriptionError,
    bool clearDescriptionError = false,
    bool? descriptionGrayscale,
    bool? imuActive,
    double? targetLatitude,
    bool clearTargetLocation = false,
    double? targetLongitude,
    bool? imuRecoveryUsed,
  }) {
    return TrackingState(
      cameraReady: cameraReady ?? this.cameraReady,
      status: status ?? this.status,
      algorithm: algorithm ?? this.algorithm,
      box: clearBox ? null : (box ?? this.box),
      geometry: geometry ?? this.geometry,
      fps: fps ?? this.fps,
      socketStatus: socketStatus ?? this.socketStatus,
      sessionNumber:
          clearSessionNumber ? null : (sessionNumber ?? this.sessionNumber),
      droppedFrames: droppedFrames ?? this.droppedFrames,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      objectDescription: clearObjectDescription
          ? null
          : (objectDescription ?? this.objectDescription),
      describing: describing ?? this.describing,
      descriptionError: clearDescriptionError
          ? null
          : (descriptionError ?? this.descriptionError),
      descriptionGrayscale: descriptionGrayscale ?? this.descriptionGrayscale,
      imuActive: imuActive ?? this.imuActive,
      targetLatitude:
          clearTargetLocation ? null : (targetLatitude ?? this.targetLatitude),
      targetLongitude:
          clearTargetLocation ? null : (targetLongitude ?? this.targetLongitude),
      imuRecoveryUsed: imuRecoveryUsed ?? this.imuRecoveryUsed,
    );
  }
}

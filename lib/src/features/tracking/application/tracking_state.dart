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
    );
  }
}

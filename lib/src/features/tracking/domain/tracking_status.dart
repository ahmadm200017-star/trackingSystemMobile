/// Lifecycle of the on-screen tracker, driving the HUD status indicator.
enum TrackingStatus {
  /// Camera is live, no target picked yet.
  idle,

  /// A target was tapped; the tracker is being seeded with the first frame.
  initializing,

  /// The tracker is returning a box every frame.
  tracking,

  /// The tracker stopped returning a box; the target may come back.
  lost,

  /// The session summary is being flushed to the backend.
  finishing,
}

extension TrackingStatusX on TrackingStatus {
  bool get isRunning =>
      this == TrackingStatus.tracking ||
      this == TrackingStatus.lost ||
      this == TrackingStatus.initializing;

  String get label => switch (this) {
        TrackingStatus.idle => 'Tap a target',
        TrackingStatus.initializing => 'Initializing',
        TrackingStatus.tracking => 'Tracking',
        TrackingStatus.lost => 'Lost Object',
        TrackingStatus.finishing => 'Saving session',
      };
}

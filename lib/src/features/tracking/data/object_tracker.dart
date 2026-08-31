import 'dart:ui';

import 'package:opencv_core/opencv.dart' as cv;

import '../domain/tracker_algorithm.dart';

/// Outcome of a single `tracker.update(frame)` call.
class TrackerUpdate {
  const TrackerUpdate.found(this.box)
      : ok = true,
        assert(box != null);
  const TrackerUpdate.lost()
      : ok = false,
        box = null;

  final bool ok;

  /// Box in the coordinate space of the frame that was passed in.
  final Rect? box;
}

/// Wraps one OpenCV tracker instance for the lifetime of a session.
abstract interface class ObjectTracker {
  TrackerAlgorithm get algorithm;

  /// Seeds the tracker with the first frame and the user-selected region.
  Future<void> init(cv.Mat frame, Rect box);

  /// Advances the tracker by one frame.
  Future<TrackerUpdate> update(cv.Mat frame);

  void dispose();
}

/// Which algorithms the currently linked OpenCV build actually exposes.
///
/// All three are available: the vendored dartcv snapshot under
/// `packages/dartcv_native` links `opencv_tracking` and wraps `cv::TrackerCSRT`
/// and `cv::TrackerKCF` alongside the upstream `cv::TrackerMIL`. Upstream
/// `opencv_core` 1.4.5 binds MIL only, so this list is only correct as long as
/// the dependency_overrides in pubspec.yaml stay in place.
class TrackerAvailability {
  const TrackerAvailability._();

  static const Set<TrackerAlgorithm> available = {
    TrackerAlgorithm.csrt,
    TrackerAlgorithm.kcf,
    TrackerAlgorithm.mil,
  };

  static bool isAvailable(TrackerAlgorithm algorithm) =>
      available.contains(algorithm);

  static String unavailableReason(TrackerAlgorithm algorithm) =>
      '${algorithm.label} is not bound by the bundled OpenCV package.';
}

class TrackerUnavailableException implements Exception {
  TrackerUnavailableException(this.algorithm)
      : message = TrackerAvailability.unavailableReason(algorithm);

  final TrackerAlgorithm algorithm;
  final String message;

  @override
  String toString() => message;
}

/// Builds [ObjectTracker]s backed by OpenCV.
class OpenCvTrackerFactory {
  const OpenCvTrackerFactory();

  ObjectTracker create(TrackerAlgorithm algorithm) {
    return switch (algorithm) {
      TrackerAlgorithm.csrt => _CsrtTracker(),
      TrackerAlgorithm.kcf => _KcfTracker(),
      TrackerAlgorithm.mil => _MilTracker(),
    };
  }
}

/// OpenCV asserts on boxes that leave the image, so trim before handing over.
cv.Rect _clampToFrame(Rect box, cv.Mat frame) {
  final left = box.left.floor().clamp(0, frame.cols - 1);
  final top = box.top.floor().clamp(0, frame.rows - 1);
  final width = box.width.round().clamp(1, frame.cols - left);
  final height = box.height.round().clamp(1, frame.rows - top);
  return cv.Rect(left, top, width, height);
}

TrackerUpdate _toUpdate(bool ok, cv.Rect rect) {
  if (!ok || rect.width <= 0 || rect.height <= 0) {
    return const TrackerUpdate.lost();
  }
  return TrackerUpdate.found(
    Rect.fromLTWH(
      rect.x.toDouble(),
      rect.y.toDouble(),
      rect.width.toDouble(),
      rect.height.toDouble(),
    ),
  );
}

/// Channel and Spatial Reliability tracker - the accurate one. Unlike MIL and
/// KCF it estimates scale, so the box follows a target that moves towards or
/// away from the camera.
class _CsrtTracker implements ObjectTracker {
  _CsrtTracker() : _tracker = cv.TrackerCSRT.create();

  final cv.TrackerCSRT _tracker;
  bool _disposed = false;

  @override
  TrackerAlgorithm get algorithm => TrackerAlgorithm.csrt;

  @override
  Future<void> init(cv.Mat frame, Rect box) async {
    final rect = _clampToFrame(box, frame);
    try {
      await _tracker.initAsync(frame, rect);
    } finally {
      rect.dispose();
    }
  }

  @override
  Future<TrackerUpdate> update(cv.Mat frame) async {
    final (ok, rect) = await _tracker.updateAsync(frame);
    try {
      return _toUpdate(ok, rect);
    } finally {
      rect.dispose();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _tracker.dispose();
  }
}

/// Kernelized Correlation Filter - the fast one. No scale estimation, so the
/// box keeps its seeded size.
class _KcfTracker implements ObjectTracker {
  _KcfTracker() : _tracker = cv.TrackerKCF.create();

  final cv.TrackerKCF _tracker;
  bool _disposed = false;

  @override
  TrackerAlgorithm get algorithm => TrackerAlgorithm.kcf;

  @override
  Future<void> init(cv.Mat frame, Rect box) async {
    final rect = _clampToFrame(box, frame);
    try {
      await _tracker.initAsync(frame, rect);
    } finally {
      rect.dispose();
    }
  }

  @override
  Future<TrackerUpdate> update(cv.Mat frame) async {
    final (ok, rect) = await _tracker.updateAsync(frame);
    try {
      return _toUpdate(ok, rect);
    } finally {
      rect.dispose();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _tracker.dispose();
  }
}

class _MilTracker implements ObjectTracker {
  _MilTracker() : _tracker = cv.TrackerMIL.create();

  final cv.TrackerMIL _tracker;
  bool _disposed = false;

  @override
  TrackerAlgorithm get algorithm => TrackerAlgorithm.mil;

  @override
  Future<void> init(cv.Mat frame, Rect box) async {
    final rect = _clampToFrame(box, frame);
    try {
      // Async variants hand the work to OpenCV's native thread pool, so the
      // Dart isolate keeps rendering while the tracker crunches the frame.
      await _tracker.initAsync(frame, rect);
    } finally {
      rect.dispose();
    }
  }

  @override
  Future<TrackerUpdate> update(cv.Mat frame) async {
    final (ok, rect) = await _tracker.updateAsync(frame);
    try {
      return _toUpdate(ok, rect);
    } finally {
      rect.dispose();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _tracker.dispose();
  }
}

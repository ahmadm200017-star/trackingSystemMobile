import 'dart:async';
import 'dart:ui';

import 'package:sensors_plus/sensors_plus.dart';

import 'motion_estimator.dart';

/// Keeps the latest gyroscope reading and turns it into a predicted scene
/// shift on demand.
///
/// Deliberately holds only the most recent sample rather than a queue: the
/// estimator uses a zero-order hold (see [MotionEstimator]), so nothing older
/// than "now" is useful, and a session runs for tens of seconds at most.
class ImuMotionCompensator {
  ImuMotionCompensator({
    double horizontalFovDegrees = 67,
    double verticalFovDegrees = 50,
  }) : _estimator = MotionEstimator(
          horizontalFovDegrees: horizontalFovDegrees,
          verticalFovDegrees: verticalFovDegrees,
        );

  final MotionEstimator _estimator;
  StreamSubscription<GyroscopeEvent>? _subscription;
  GyroscopeEvent? _latest;
  DateTime? _lastSampleAt;

  /// Rotation accumulated since the last [resetOrientation], integrated
  /// (trapezoidally) from the gyroscope rate stream. Used to subtract
  /// hand-shake rotation from the tracked pixel before projecting it to
  /// metric coordinates - see CameraLocalFrameCalculator. Zero whenever no
  /// gyroscope has reported, which reproduces the uncompensated projection.
  double _yawRadians = 0;
  double _pitchRadians = 0;

  double get yawRadians => _yawRadians;
  double get pitchRadians => _pitchRadians;

  /// True once a gyroscope reading has actually arrived. Some devices (rare,
  /// but real - certain low-end handsets and every emulator) report no
  /// gyroscope at all; imu_enabled on the session reflects this rather than
  /// a hopeful assumption that the sensor exists.
  bool get isActive => _latest != null;

  /// Starts listening and resolves once it is known whether this device
  /// actually has a gyroscope: either a first reading arrives, an error is
  /// reported, or [probeTimeout] elapses with neither. The subscription is
  /// kept open afterwards regardless, so a slow first sample on a real
  /// gyroscope is not mistaken for "no sensor" - only the probe answer,
  /// used once to decide what to tell the backend, is time-bounded.
  ///
  /// Safe to call once per session; a second call is a no-op that resolves
  /// immediately with the current [isActive] value.
  Future<bool> start({Duration probeTimeout = const Duration(milliseconds: 400)}) {
    if (_subscription != null) return Future.value(isActive);

    final probe = Completer<bool>();
    void resolveOnce(bool value) {
      if (!probe.isCompleted) probe.complete(value);
    }

    _subscription = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      (event) {
        _integrate(event);
        _latest = event;
        resolveOnce(true);
      },
      onError: (_) {
        // No gyroscope, or the platform refused the stream. isActive simply
        // stays false; the caller falls back to un-compensated tracking.
        _latest = null;
        resolveOnce(false);
      },
      cancelOnError: false,
    );

    unawaited(Future.delayed(probeTimeout, () => resolveOnce(isActive)));
    return probe.future;
  }

  /// Trapezoidal integration between this sample and the previous one - more
  /// accurate than a zero-order hold over the tens-of-milliseconds gaps
  /// `SensorInterval.gameInterval` produces, and cheap enough to do on every
  /// sample since only the running total is kept.
  void _integrate(GyroscopeEvent event) {
    final now = DateTime.now();
    final previous = _latest;
    final lastAt = _lastSampleAt;
    if (previous != null && lastAt != null) {
      final dt = now.difference(lastAt).inMicroseconds / Duration.microsecondsPerSecond;
      _yawRadians += (previous.y + event.y) / 2 * dt;
      _pitchRadians += (previous.x + event.x) / 2 * dt;
    }
    _lastSampleAt = now;
  }

  /// Zeroes the accumulated rotation, establishing "now" as the reference
  /// orientation for metric stabilization. Called whenever the tracker is
  /// (re)seeded, since the local-frame workspace is anchored to the camera's
  /// pose at that moment - see `TrackingController._createAndInitTracker`.
  void resetOrientation() {
    _yawRadians = 0;
    _pitchRadians = 0;
    _lastSampleAt = null;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _latest = null;
    _lastSampleAt = null;
    _yawRadians = 0;
    _pitchRadians = 0;
  }

  /// The scene shift predicted over [elapsed], or [Offset.zero] when there is
  /// no reading yet. Never throws and never returns null, so a caller can use
  /// it unconditionally without a null check on every frame.
  Offset predictedShiftOver(Duration elapsed, Size frameSize) {
    final reading = _latest;
    if (reading == null) return Offset.zero;

    return _estimator.sceneShiftFor(
      angularVelocityYaw: reading.y,
      angularVelocityPitch: reading.x,
      elapsed: elapsed,
      frameSize: frameSize,
    );
  }
}

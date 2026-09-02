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

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _latest = null;
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

import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import 'device_orientation.dart';

/// Keeps the latest accelerometer and magnetometer readings and derives the
/// camera's current attitude from them on demand.
class CameraAttitudeReader {
  CameraAttitudeReader({this.estimator = const CameraAttitudeEstimator()});

  final CameraAttitudeEstimator estimator;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  AccelerometerEvent? _accel;
  MagnetometerEvent? _mag;

  bool get isActive => _accel != null && _mag != null;

  void start() {
    _accelSub ??= accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(
      (event) => _accel = event,
      onError: (_) => _accel = null,
      cancelOnError: false,
    );

    _magSub ??= magnetometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(
      (event) => _mag = event,
      onError: (_) => _mag = null,
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    await _accelSub?.cancel();
    await _magSub?.cancel();
    _accelSub = null;
    _magSub = null;
    _accel = null;
    _mag = null;
  }

  /// The camera's current attitude, or null when either sensor has not
  /// reported yet - most commonly the magnetometer, which some devices are
  /// slower to calibrate than others.
  CameraAttitude? current() {
    final accel = _accel;
    final mag = _mag;
    if (accel == null || mag == null) return null;

    return estimator.estimate(
      ax: accel.x,
      ay: accel.y,
      az: accel.z,
      mx: mag.x,
      my: mag.y,
      mz: mag.z,
    );
  }
}

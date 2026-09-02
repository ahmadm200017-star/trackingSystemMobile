import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mdf_tracker/src/core/geo/device_orientation.dart';
import 'package:mdf_tracker/src/core/geo/geo_projection.dart';
import 'package:mdf_tracker/src/core/imu/motion_estimator.dart';

void main() {
  group('MotionEstimator', () {
    const estimator = MotionEstimator(horizontalFovDegrees: 60, verticalFovDegrees: 45);

    test('no rotation produces no shift', () {
      final shift = estimator.sceneShiftFor(
        angularVelocityYaw: 0,
        angularVelocityPitch: 0,
        elapsed: const Duration(milliseconds: 33),
        frameSize: const Size(1280, 720),
      );
      expect(shift.dx, closeTo(0, 1e-9));
      expect(shift.dy, closeTo(0, 1e-9));
    });

    test('yawing right shifts the scene left', () {
      final shift = estimator.sceneShiftFor(
        angularVelocityYaw: 0.5, // rad/s, phone turning right
        angularVelocityPitch: 0,
        elapsed: const Duration(milliseconds: 100),
        frameSize: const Size(1280, 720),
      );
      expect(shift.dx, lessThan(0));
      expect(shift.dy, closeTo(0, 1e-6));
    });

    test('a faster rotation over the same time produces a larger shift', () {
      final slow = estimator.sceneShiftFor(
        angularVelocityYaw: 0.2,
        angularVelocityPitch: 0,
        elapsed: const Duration(milliseconds: 100),
        frameSize: const Size(1280, 720),
      );
      final fast = estimator.sceneShiftFor(
        angularVelocityYaw: 1.0,
        angularVelocityPitch: 0,
        elapsed: const Duration(milliseconds: 100),
        frameSize: const Size(1280, 720),
      );
      expect(fast.dx.abs(), greaterThan(slow.dx.abs()));
    });

    test('angle of a point at image centre is zero', () {
      final angle = estimator.angleOfPixelOffset(Offset.zero, const Size(1280, 720));
      expect(angle.dx, closeTo(0, 1e-9));
      expect(angle.dy, closeTo(0, 1e-9));
    });

    test('angle of a point at the right edge is half the horizontal FOV', () {
      final angle = estimator.angleOfPixelOffset(const Offset(640, 0), const Size(1280, 720));
      expect(angle.dx, closeTo(30, 1e-6)); // half of 60 degrees HFOV
    });
  });

  group('CameraAttitudeEstimator', () {
    const estimator = CameraAttitudeEstimator();

    test('phone flat, screen up: camera points straight down', () {
      final attitude = estimator.estimate(ax: 0, ay: 0, az: 9.8, mx: 0, my: 1, mz: 0);
      expect(attitude.elevationDegrees, closeTo(-90, 1e-3));
      expect(CameraAttitudeEstimator.bearingIsWellDefined(attitude.elevationDegrees), isFalse);
    });

    test('phone flat, screen down: camera points straight up', () {
      final attitude = estimator.estimate(ax: 0, ay: 0, az: -9.8, mx: 0, my: 1, mz: 0);
      expect(attitude.elevationDegrees, closeTo(90, 1e-3));
    });

    test('phone held upright: camera points at the horizon', () {
      final attitude = estimator.estimate(ax: 0, ay: 9.8, az: 0, mx: 0, my: 0, mz: -1);
      expect(attitude.elevationDegrees, closeTo(0, 1e-3));
      expect(CameraAttitudeEstimator.bearingIsWellDefined(attitude.elevationDegrees), isTrue);
    });

    test('phone held upright, camera aimed at magnetic north', () {
      // Derived by hand for this exact stance: device y is "up", and this
      // magnetic-field reading corresponds to the camera's boresight (device
      // -z) coinciding with the magnetic-north direction.
      final attitude = estimator.estimate(ax: 0, ay: 9.8, az: 0, mx: 0, my: 0, mz: -1);
      expect(attitude.azimuthDegrees, closeTo(0, 1e-3));
    });

    test('phone held upright, camera aimed at magnetic east', () {
      final attitude = estimator.estimate(ax: 0, ay: 9.8, az: 0, mx: -1, my: 0, mz: 0);
      expect(attitude.azimuthDegrees, closeTo(90, 1e-3));
    });
  });

  group('GeoProjection', () {
    const projection = GeoProjection();

    test('destination point one degree of latitude north matches the known constant', () {
      final (lat, lon) = projection.destinationPoint(
        latitude: 0,
        longitude: 0,
        distanceMeters: 111320, // ~1 degree of latitude
        bearingDegrees: 0,
      );
      expect(lat, closeTo(1.0, 0.01));
      expect(lon, closeTo(0.0, 0.01));
    });

    test('destination point due east at the equator matches one degree of longitude', () {
      final (lat, lon) = projection.destinationPoint(
        latitude: 0,
        longitude: 0,
        distanceMeters: 111320,
        bearingDegrees: 90,
      );
      expect(lat, closeTo(0.0, 0.01));
      expect(lon, closeTo(1.0, 0.01));
    });

    test('a target on the horizon or above cannot be ground-projected', () {
      final point = projection.project(
        originLatitude: 33.5,
        originLongitude: 36.3,
        cameraHeightMeters: 1.4,
        cameraElevationDegrees: 0,
        cameraAzimuthDegrees: 90,
        targetAngleXDegrees: 0,
        targetAngleYDegrees: 0,
      );
      expect(point, isNull);
    });

    test('a target too far away is treated as unreliable rather than returned', () {
      final point = projection.project(
        originLatitude: 33.5,
        originLongitude: 36.3,
        cameraHeightMeters: 1.4,
        cameraElevationDegrees: -0.5, // barely below the horizon
        cameraAzimuthDegrees: 0,
        targetAngleXDegrees: 0,
        targetAngleYDegrees: 0,
      );
      expect(point, isNull);
    });

    test('a target straight ahead and clearly below the horizon projects forward', () {
      final point = projection.project(
        originLatitude: 0,
        originLongitude: 0,
        cameraHeightMeters: 1.4,
        cameraElevationDegrees: -30,
        cameraAzimuthDegrees: 0, // facing due north
        targetAngleXDegrees: 0,
        targetAngleYDegrees: 0,
      );
      expect(point, isNotNull);
      // tan(30 degrees) ~= 0.577, so distance ~= 1.4 / 0.577 ~= 2.42 m north.
      expect(point!.distanceMeters, closeTo(2.42, 0.05));
      expect(point.latitude, greaterThan(0)); // moved north
      expect(point.longitude, closeTo(0, 1e-6));
    });
  });
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Where a session was recorded.
class SessionLocation {
  const SessionLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
  });

  final double latitude;
  final double longitude;

  /// Horizontal accuracy in metres, as reported by the platform.
  final double? accuracyMeters;

  /// Six decimal places is roughly 0.11 m at the equator, well past what GPS
  /// resolves, and matches the `decimal(9,6)` columns on the server.
  Map<String, dynamic> toJson() => {
        'latitude': double.parse(latitude.toStringAsFixed(6)),
        'longitude': double.parse(longitude.toStringAsFixed(6)),
        if (accuracyMeters != null)
          'locationAccuracyMeters': double.parse(accuracyMeters!.toStringAsFixed(2)),
      };
}

/// Reads a single position when a session starts.
///
/// Every path returns null rather than throwing. A session must start whether or
/// not a fix is available: the user may have denied the permission, disabled
/// location services, or simply be indoors, and none of those are reasons to
/// refuse to track an object.
class SessionLocationReader {
  /// A GPS fix can take tens of seconds from cold. Tracking is already underway
  /// by then, so the wait is capped and the last known position is used instead.
  static const Duration fixTimeout = Duration(seconds: 4);

  /// Returns null when no usable position could be obtained.
  Future<SessionLocation?> read() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        // Services off: a cached position would be stale and misleading.
        return null;
      }

      if (!await _hasPermission()) return null;

      // Try for a current fix first, then fall back to whatever the platform
      // already has. Medium accuracy is plenty to say where a run happened and
      // settles far faster than `best`.
      final position = await _currentPosition() ?? await _lastKnownPosition();
      if (position == null) return null;

      return SessionLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy > 0 ? position.accuracy : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Requests the permission once if it has not been decided yet. A permanent
  /// denial is respected rather than re-prompted, which the OS would ignore anyway.
  Future<bool> _hasPermission() async {
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<Position?> _currentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: fixTimeout,
        ),
      );
    } catch (_) {
      // TimeoutException when no fix arrives in time, or a platform error.
      return null;
    }
  }

  Future<Position?> _lastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }
}

final sessionLocationReaderProvider =
    Provider<SessionLocationReader>((ref) => SessionLocationReader());

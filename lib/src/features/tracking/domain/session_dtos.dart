import '../../../core/device/device_profile.dart';
import '../../../core/geo/target_geo_locator.dart';
import '../../../core/location/session_location.dart';
import '../../../features/tracking/domain/camera_lens.dart';
import 'tracker_algorithm.dart';

/// Wire contracts for `MdfTracker.Api`. JSON keys are camelCase; the API maps
/// them onto the snake_case columns described in Backend.md.

class StartSessionRequest {
  const StartSessionRequest({
    required this.cameraType,
    required this.trackerAlgorithm,
    required this.startTime,
    required this.screenWidth,
    required this.screenHeight,
    required this.processingScale,
    required this.imuEnabled,
    this.device = const DeviceProfile(),
    this.location,
  });

  final CameraLens cameraType;
  final TrackerAlgorithm trackerAlgorithm;
  final DateTime startTime;
  final int screenWidth;
  final int screenHeight;

  /// Downscale factor the tracker ran at. Recorded alongside the FPS it
  /// produced, because the two are meaningless apart.
  final double processingScale;

  /// Handset identity; every field inside is optional.
  final DeviceProfile device;

  /// Where the run started. Null when there was no fix or the permission was
  /// declined, in which case the coordinate keys are omitted entirely - the API
  /// rejects half a pair.
  final SessionLocation? location;

  /// Whether the gyroscope was actually available and used to help the tracker
  /// recover from sudden phone movement during this run. Reflects reality
  /// rather than a hopeful assumption: some devices, and every emulator, have
  /// no gyroscope, and the app finds out by probing for a reading rather than
  /// trusting a capability flag.
  final bool imuEnabled;

  Map<String, dynamic> toJson() => {
        'cameraType': cameraType.wireName,
        'trackerAlgorithm': trackerAlgorithm.wireName,
        'startTime': startTime.toUtc().toIso8601String(),
        'screenWidth': screenWidth,
        'screenHeight': screenHeight,
        'processingScale': double.parse(processingScale.toStringAsFixed(2)),
        'imuEnabled': imuEnabled,
        ...device.toJson(),
        ...?location?.toJson(),
      };
}

class SessionSummary {
  const SessionSummary({required this.id, required this.sessionNumber});

  factory SessionSummary.fromJson(Map<String, dynamic> json) => SessionSummary(
        id: json['id'] as String,
        sessionNumber: (json['sessionNumber'] ?? '') as String,
      );

  final String id;
  final String sessionNumber;
}

class CompleteSessionRequest {
  const CompleteSessionRequest({
    required this.endTime,
    required this.averageFps,
    required this.isSuccessful,
  });

  final DateTime endTime;
  final double averageFps;

  /// True when the user stopped the session while the target was still locked;
  /// false when the run ended with the tracker in the lost state.
  final bool isSuccessful;

  Map<String, dynamic> toJson() => {
        'endTime': endTime.toUtc().toIso8601String(),
        'averageFps': double.parse(averageFps.toStringAsFixed(2)),
        'isSuccessful': isSuccessful,
      };
}

/// Body of `POST /api/sessions/{id}/description`: the colour crop of the first
/// tracked frame. The server calls Groq with it, so no API key lives on device.
class DescribeObjectRequest {
  const DescribeObjectRequest({required this.imageBase64, this.mimeType = 'image/jpeg'});

  final String imageBase64;
  final String mimeType;

  Map<String, dynamic> toJson() => {
        'imageBase64': imageBase64,
        'mimeType': mimeType,
      };
}

enum SessionEventType {
  lost('lost'),
  reacquired('reacquired');

  const SessionEventType(this.wireName);

  final String wireName;
}

class SessionEventRequest {
  const SessionEventRequest({required this.eventType, required this.occurredAt});

  final SessionEventType eventType;
  final DateTime occurredAt;

  Map<String, dynamic> toJson() => {
        'eventType': eventType.wireName,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
      };
}

/// One tracked frame, streamed over the WebSocket while a session is running.
class FramePayload {
  const FramePayload({
    required this.frameTimestamp,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.target,
  });

  final DateTime frameTimestamp;
  final int x;
  final int y;
  final int width;
  final int height;

  /// Estimated real-world position of the tracked object, when the geometry
  /// supports one - see [TargetGeoEstimate]. Null on most frames: it needs a
  /// session-start GPS fix, a settled compass reading, and a camera angle
  /// pointed below the horizon, none of which are guaranteed every frame.
  final TargetGeoEstimate? target;

  Map<String, dynamic> toJson() => {
        'frameTimestamp': frameTimestamp.toUtc().toIso8601String(),
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        ...?target?.toJson(),
      };
}

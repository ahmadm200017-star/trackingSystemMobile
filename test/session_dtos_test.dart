import 'package:flutter_test/flutter_test.dart';
import 'package:mdf_tracker/src/features/tracking/domain/camera_lens.dart';
import 'package:mdf_tracker/src/features/tracking/domain/session_dtos.dart';
import 'package:mdf_tracker/src/features/tracking/domain/tracker_algorithm.dart';

void main() {
  group('wire contract', () {
    test('start payload uses camelCase keys and backend enum values', () {
      final json = StartSessionRequest(
        cameraType: CameraLens.front,
        trackerAlgorithm: TrackerAlgorithm.csrt,
        startTime: DateTime.utc(2026, 8, 27, 21, 27, 18),
        screenWidth: 640,
        screenHeight: 480,
      ).toJson();

      expect(json, {
        'cameraType': 'front',
        'trackerAlgorithm': 'csrt',
        'startTime': '2026-08-27T21:27:18.000Z',
        'screenWidth': 640,
        'screenHeight': 480,
      });
    });

    test('local timestamps are normalised to UTC before sending', () {
      final local = DateTime(2026, 8, 27, 21, 27, 18);
      final json = CompleteSessionRequest(
        endTime: local,
        averageFps: 24.456,
        isSuccessful: true,
      ).toJson();

      expect(json['endTime'], local.toUtc().toIso8601String());
      // average_fps is decimal(6,2) on the backend.
      expect(json['averageFps'], 24.46);
    });

    test('session summary tolerates a missing session number', () {
      final summary = SessionSummary.fromJson({'id': 'abc'});
      expect(summary.id, 'abc');
      expect(summary.sessionNumber, '');
    });

    test('unknown algorithm names fall back to the one that always runs', () {
      expect(TrackerAlgorithm.fromWire('kcf'), TrackerAlgorithm.kcf);
      expect(TrackerAlgorithm.fromWire('nonsense'), TrackerAlgorithm.mil);
      expect(CameraLens.fromWire('front'), CameraLens.front);
      expect(CameraLens.fromWire('nonsense'), CameraLens.back);
    });
  });
}

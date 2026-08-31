import 'package:flutter_test/flutter_test.dart';
import 'package:mdf_tracker/src/features/tracking/data/fps_meter.dart';

void main() {
  group('FpsMeter', () {
    test('reports nothing before the first frame', () {
      final meter = FpsMeter();
      expect(meter.frameCount, 0);
      expect(meter.currentFps, 0);
      expect(meter.averageFps, 0);
    });

    test('the first sample seeds the smoothed value exactly', () {
      final meter = FpsMeter();
      meter.addSample(const Duration(milliseconds: 50));
      expect(meter.currentFps, closeTo(20, 1e-9));
    });

    test('the session average is frames over total processing time', () {
      final meter = FpsMeter();
      meter.addSample(const Duration(milliseconds: 50)); // 20 fps
      meter.addSample(const Duration(milliseconds: 100)); // 10 fps
      // 2 frames in 0.15s.
      expect(meter.averageFps, closeTo(13.3333, 1e-3));
      expect(meter.frameCount, 2);
    });

    test('the smoothed value trails a step change instead of jumping', () {
      final meter = FpsMeter(smoothing: 0.2);
      meter.addSample(const Duration(milliseconds: 50)); // 20 fps
      meter.addSample(const Duration(milliseconds: 200)); // 5 fps
      // 20 + 0.2 * (5 - 20) = 17
      expect(meter.currentFps, closeTo(17, 1e-9));
    });

    test('zero-length samples are ignored rather than reported as infinite', () {
      final meter = FpsMeter();
      meter.addSample(Duration.zero);
      expect(meter.frameCount, 0);
      expect(meter.currentFps, 0);
    });

    test('reset clears the session', () {
      final meter = FpsMeter()..addSample(const Duration(milliseconds: 40));
      meter.reset();
      expect(meter.frameCount, 0);
      expect(meter.averageFps, 0);
    });
  });
}

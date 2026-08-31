import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mdf_tracker/src/features/tracking/domain/frame_geometry.dart';

void main() {
  // A typical back camera: 640x480 sensor frame, 90 degrees off the portrait UI.
  const backCamera = FrameGeometry(
    imageSize: Size(640, 480),
    quarterTurns: 1,
    mirror: false,
  );

  // A typical front camera: same rotation, mirrored.
  const frontCamera = FrameGeometry(
    imageSize: Size(640, 480),
    quarterTurns: 1,
    mirror: true,
  );

  group('FrameGeometry', () {
    test('rotating an odd number of turns swaps the display dimensions', () {
      expect(backCamera.displaySize, const Size(480, 640));
      expect(
        const FrameGeometry(
          imageSize: Size(640, 480),
          quarterTurns: 2,
          mirror: false,
        ).displaySize,
        const Size(640, 480),
      );
    });

    test('image -> display -> image is the identity, back camera', () {
      const point = Offset(123, 77);
      final round = backCamera.displayToImage(backCamera.imageToDisplay(point));
      expect(round.dx, closeTo(point.dx, 1e-9));
      expect(round.dy, closeTo(point.dy, 1e-9));
    });

    test('image -> display -> image is the identity, mirrored front camera', () {
      const point = Offset(123, 77);
      final round = frontCamera.displayToImage(frontCamera.imageToDisplay(point));
      expect(round.dx, closeTo(point.dx, 1e-9));
      expect(round.dy, closeTo(point.dy, 1e-9));
    });

    test('a quarter turn maps the sensor top-left to the display top-right', () {
      expect(backCamera.imageToDisplay(Offset.zero), const Offset(480, 0));
    });

    test('mirroring flips the same corner back to the left edge', () {
      expect(frontCamera.imageToDisplay(Offset.zero), const Offset(0, 0));
    });

    test('rectangles stay normalised after rotation', () {
      final rect = backCamera.imageRectToDisplay(
        const Rect.fromLTWH(100, 50, 40, 20),
      );
      expect(rect.width, 20);
      expect(rect.height, 40);
      expect(rect.left, lessThan(rect.right));
      expect(rect.top, lessThan(rect.bottom));
    });
  });

  group('FrameProjection', () {
    // Portrait viewport, wider aspect than the frame -> cover crops vertically.
    final projection = FrameProjection(
      geometry: backCamera,
      viewport: const Size(480, 800),
    );

    test('a tap maps back to the image pixel it landed on', () {
      const tap = Offset(240, 400);
      final image = projection.viewportToImage(tap);
      final back = projection.imageRectToViewport(
        Rect.fromCenter(center: image, width: 0, height: 0),
      );
      expect(back.center.dx, closeTo(tap.dx, 1e-6));
      expect(back.center.dy, closeTo(tap.dy, 1e-6));
    });

    test('viewport lengths convert to image pixels at the cover scale', () {
      // Cover scale here is 800/640 = 1.25, so 100 screen px is 80 image px.
      expect(projection.viewportLengthToImage(100), closeTo(80, 1e-9));
    });

    test('a full-frame box covers at least the whole viewport', () {
      final rect = projection.imageRectToViewport(
        const Rect.fromLTWH(0, 0, 640, 480),
      );
      expect(rect.width, greaterThanOrEqualTo(480));
      expect(rect.height, greaterThanOrEqualTo(800));
    });
  });
}

import 'dart:math' as math;
import 'dart:ui';

/// Maps between camera-sensor pixels and what the user actually sees.
///
/// Camera frames arrive in sensor orientation (landscape on virtually every
/// phone) while the preview is rendered upright, and front cameras are mirrored
/// on top of that. Every touch coordinate and every tracker box has to cross
/// that boundary, so the transform lives in one place.
class FrameGeometry {
  const FrameGeometry({
    required this.imageSize,
    required this.quarterTurns,
    required this.mirror,
  });

  /// Native size of the [CameraImage], in sensor orientation.
  final Size imageSize;

  /// Clockwise 90-degree turns applied to the image to make it upright.
  final int quarterTurns;

  /// Whether the upright image is mirrored horizontally (front camera).
  final bool mirror;

  /// Size of the image after rotation - the space the preview is laid out in.
  Size get displaySize => quarterTurns.isOdd
      ? Size(imageSize.height, imageSize.width)
      : imageSize;

  Offset imageToDisplay(Offset point) {
    final w = imageSize.width;
    final h = imageSize.height;
    final rotated = switch (quarterTurns % 4) {
      1 => Offset(h - point.dy, point.dx),
      2 => Offset(w - point.dx, h - point.dy),
      3 => Offset(point.dy, w - point.dx),
      _ => point,
    };
    return mirror ? Offset(displaySize.width - rotated.dx, rotated.dy) : rotated;
  }

  Offset displayToImage(Offset point) {
    final unmirrored =
        mirror ? Offset(displaySize.width - point.dx, point.dy) : point;
    final w = imageSize.width;
    final h = imageSize.height;
    return switch (quarterTurns % 4) {
      1 => Offset(unmirrored.dy, h - unmirrored.dx),
      2 => Offset(w - unmirrored.dx, h - unmirrored.dy),
      3 => Offset(w - unmirrored.dy, unmirrored.dx),
      _ => unmirrored,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is FrameGeometry &&
      other.imageSize == imageSize &&
      other.quarterTurns == quarterTurns &&
      other.mirror == mirror;

  @override
  int get hashCode => Object.hash(imageSize, quarterTurns, mirror);

  /// Right angles map rectangles onto rectangles, so the corner pair is enough.
  Rect imageRectToDisplay(Rect rect) {
    final a = imageToDisplay(rect.topLeft);
    final b = imageToDisplay(rect.bottomRight);
    return Rect.fromLTRB(
      math.min(a.dx, b.dx),
      math.min(a.dy, b.dy),
      math.max(a.dx, b.dx),
      math.max(a.dy, b.dy),
    );
  }
}

/// Places the rotated frame inside a widget using `BoxFit.cover`, matching how
/// `CameraPreview` fills its slot, and converts coordinates both ways.
class FrameProjection {
  FrameProjection({required this.geometry, required this.viewport});

  final FrameGeometry geometry;
  final Size viewport;

  double get _scale {
    final display = geometry.displaySize;
    if (display.width <= 0 || display.height <= 0) return 1;
    return math.max(
      viewport.width / display.width,
      viewport.height / display.height,
    );
  }

  Offset get _origin {
    final display = geometry.displaySize;
    return Offset(
      (viewport.width - display.width * _scale) / 2,
      (viewport.height - display.height * _scale) / 2,
    );
  }

  Rect imageRectToViewport(Rect rect) {
    final display = geometry.imageRectToDisplay(rect);
    final scale = _scale;
    final origin = _origin;
    return Rect.fromLTWH(
      origin.dx + display.left * scale,
      origin.dy + display.top * scale,
      display.width * scale,
      display.height * scale,
    );
  }

  /// Inverse of [imageRectToViewport] for a single point - used to turn a tap
  /// into the seed region handed to the tracker.
  Offset viewportToImage(Offset point) {
    final scale = _scale;
    final origin = _origin;
    if (scale == 0) return Offset.zero;
    return geometry.displayToImage(
      Offset((point.dx - origin.dx) / scale, (point.dy - origin.dy) / scale),
    );
  }

  /// Converts a length in viewport pixels to the equivalent in image pixels.
  double viewportLengthToImage(double length) {
    final scale = _scale;
    return scale == 0 ? length : length / scale;
  }
}

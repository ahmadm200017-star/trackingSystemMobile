import 'package:flutter/material.dart';

import '../../domain/frame_geometry.dart';
import '../../domain/tracking_status.dart';

/// Draws the tracker box over the camera preview.
///
/// The box arrives in camera-image coordinates; [FrameProjection] applies the
/// same rotate/mirror/cover transform the preview itself uses, so the rectangle
/// sits exactly on the target.
class BoundingBoxPainter extends CustomPainter {
  const BoundingBoxPainter({
    required this.box,
    required this.geometry,
    required this.color,
    required this.status,
    this.selection,
  });

  /// Box in full-resolution camera-image pixels.
  final Rect? box;
  final FrameGeometry? geometry;
  final Color color;
  final TrackingStatus status;

  /// Region currently being dragged out, already in viewport pixels.
  final Rect? selection;

  @override
  void paint(Canvas canvas, Size size) {
    final selection = this.selection;
    if (selection != null) {
      _paintSelection(canvas, selection);
      // While drawing, the region under the finger is the only useful thing to
      // show - the stale tracker box would just clutter it.
      return;
    }

    final box = this.box;
    final geometry = this.geometry;
    if (box == null || geometry == null) return;

    final rect = FrameProjection(geometry: geometry, viewport: size)
        .imageRectToViewport(box);

    // A lost target keeps its last known box, dimmed, so the user can see where
    // the tracker gave up.
    final effective = status == TrackingStatus.lost
        ? Color.lerp(color, const Color(0xFFE53935), 0.7)!
        : color;
    final opacity = status == TrackingStatus.lost ? 0.55 : 1.0;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = effective.withValues(alpha: opacity);

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas.drawRRect(rrect, stroke);

    // Corner ticks read better than a plain rectangle against a busy scene.
    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = effective.withValues(alpha: opacity);

    final length = rect.shortestSide * 0.22;
    for (final (corner, dx, dy) in <(Offset, double, double)>[
      (rect.topLeft, 1, 1),
      (rect.topRight, -1, 1),
      (rect.bottomLeft, 1, -1),
      (rect.bottomRight, -1, -1),
    ]) {
      canvas.drawLine(corner, corner.translate(length * dx, 0), tick);
      canvas.drawLine(corner, corner.translate(0, length * dy), tick);
    }

    final centre = rect.center;
    canvas.drawCircle(centre, 3, Paint()..color = effective.withValues(alpha: opacity));
  }

  /// The region being drawn, shown filled so it reads as a live selection
  /// rather than as a tracker result.
  void _paintSelection(Canvas canvas, Rect rect) {
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(BoundingBoxPainter oldDelegate) =>
      oldDelegate.box != box ||
      oldDelegate.color != color ||
      oldDelegate.status != status ||
      oldDelegate.geometry != geometry ||
      oldDelegate.selection != selection;
}

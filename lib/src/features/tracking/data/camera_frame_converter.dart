import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:opencv_core/opencv.dart' as cv;

/// A single-channel frame handed to the tracker, plus the mapping back to the
/// full-resolution camera image.
class GrayFrame {
  GrayFrame({
    required this.mat,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.scale,
  });

  /// CV_8UC1 luminance image, already downscaled by [scale].
  final cv.Mat mat;

  /// Dimensions of the original [CameraImage].
  final int sourceWidth;
  final int sourceHeight;

  /// Factor applied to get from source pixels to [mat] pixels.
  final double scale;

  int get width => mat.cols;
  int get height => mat.rows;

  void dispose() => mat.dispose();
}

/// Turns a [CameraImage] into an OpenCV matrix.
///
/// Only the luminance channel is used: every tracker in OpenCV's `video` module
/// works on grayscale, and skipping the YUV->BGR conversion is the single
/// biggest win available in the per-frame budget.
class CameraFrameConverter {
  /// Converts [image], downscaling by [scale] (1.0 keeps the native size).
  ///
  /// Throws [UnsupportedError] for image formats the app was not built for.
  Future<GrayFrame> convert(CameraImage image, {double scale = 1.0}) async {
    final gray = await switch (image.format.group) {
      ImageFormatGroup.yuv420 || ImageFormatGroup.nv21 => _fromLuminancePlane(image),
      ImageFormatGroup.bgra8888 => _fromBgra(image),
      _ => throw UnsupportedError(
          'Unsupported camera image format: ${image.format.group}',
        ),
    };

    if (scale >= 0.999) {
      return GrayFrame(
        mat: gray,
        sourceWidth: image.width,
        sourceHeight: image.height,
        scale: 1.0,
      );
    }

    final targetWidth = (image.width * scale).round().clamp(16, image.width);
    final targetHeight = (image.height * scale).round().clamp(16, image.height);
    final resized = await cv.resizeAsync(
      gray,
      (targetWidth, targetHeight),
      interpolation: cv.INTER_AREA,
    );
    gray.dispose();

    return GrayFrame(
      mat: resized,
      sourceWidth: image.width,
      sourceHeight: image.height,
      // Recomputed from the rounded size so box math stays exact.
      scale: targetWidth / image.width,
    );
  }

  /// YUV420 / NV21: plane 0 is already the 8-bit luminance channel.
  Future<cv.Mat> _fromLuminancePlane(CameraImage image) async {
    final plane = image.planes.first;
    final packed = _packRows(
      plane.bytes,
      plane.bytesPerRow,
      image.width,
      image.height,
      1,
    );
    return _matFromBytes(packed, image.width, image.height, cv.MatType.CV_8UC1);
  }

  /// BGRA8888 (iOS): convert the interleaved buffer down to one channel.
  Future<cv.Mat> _fromBgra(CameraImage image) async {
    final plane = image.planes.first;
    final packed = _packRows(
      plane.bytes,
      plane.bytesPerRow,
      image.width,
      image.height,
      4,
    );
    final bgra = _matFromBytes(packed, image.width, image.height, cv.MatType.CV_8UC4);
    final gray = await cv.cvtColorAsync(bgra, cv.COLOR_BGRA2GRAY);
    bgra.dispose();
    return gray;
  }

  cv.Mat _matFromBytes(Uint8List bytes, int width, int height, cv.MatType type) {
    final vec = cv.VecUChar.fromList(bytes);
    try {
      return cv.Mat.fromVec(vec, rows: height, cols: width, type: type);
    } finally {
      vec.dispose();
    }
  }

  /// Camera planes are padded to a stride; OpenCV wants tightly packed rows.
  Uint8List _packRows(
    Uint8List source,
    int bytesPerRow,
    int width,
    int height,
    int bytesPerPixel,
  ) {
    final rowBytes = width * bytesPerPixel;
    if (bytesPerRow == rowBytes && source.length >= rowBytes * height) {
      return source.length == rowBytes * height
          ? source
          : Uint8List.sublistView(source, 0, rowBytes * height);
    }

    final packed = Uint8List(rowBytes * height);
    for (var row = 0; row < height; row++) {
      final start = row * bytesPerRow;
      packed.setRange(row * rowBytes, (row + 1) * rowBytes, source, start);
    }
    return packed;
  }
}

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:opencv_core/opencv.dart' as cv;

/// A colour JPEG crop of the tracked object, ready to upload for description.
class ObjectSnapshot {
  const ObjectSnapshot({required this.base64Jpeg, required this.byteLength});

  /// Raw base64, no `data:` prefix — the API accepts either, but the prefix
  /// would just inflate the upload.
  final String base64Jpeg;

  /// Size of the encoded JPEG before base64, for logging and sanity checks.
  final int byteLength;
}

/// Outcome of one capture attempt.
///
/// A failure carries a short reason rather than a bare null, because this runs on a real
/// handset in a release build where nothing is logged: without the reason reaching the UI
/// there is no way to tell a broken colour conversion from a user who never tapped.
class ObjectSnapshotAttempt {
  const ObjectSnapshotAttempt.success(this.snapshot, {required this.grayscale})
      : failure = null;

  const ObjectSnapshotAttempt.failed(this.failure)
      : snapshot = null,
        grayscale = false;

  final ObjectSnapshot? snapshot;

  /// Null on success; a short human-readable reason otherwise.
  final String? failure;

  /// True when the colour path failed and the luminance fallback was used, so the
  /// description will not mention colour.
  final bool grayscale;

  bool get ok => snapshot != null;
}

/// Cuts the region around the seed box out of one camera frame, in colour.
///
/// The tracker's own pipeline ([CameraFrameConverter]) throws colour away — it
/// keeps only the luminance plane, because that is all OpenCV's trackers read.
/// A description needs the colour back ("a red mug" beats "a mug"), so this
/// walks the chroma planes as well. It runs exactly once per session, on the
/// frame that seeds the tracker, so the extra conversion never touches the
/// per-frame budget.
class ObjectSnapshotCapture {
  /// Fraction of the box size added on every side, so the model sees the object
  /// in context rather than a texture swatch. 0.5 roughly doubles each edge.
  static const double contextPadding = 0.5;

  /// Longest edge of the uploaded crop.
  ///
  /// Dropped from 512 to shrink the phone-to-server upload, which is the one leg of the
  /// round trip that runs over mobile data and cannot be measured from a desktop. The
  /// model's answer does not change: a 384 px crop and a 512 px crop of the same scene
  /// both cost about 1,350 image tokens and both come back in 0.13 s of Groq compute.
  static const int maxEdge = 384;

  /// 75 rather than 82: roughly a third fewer bytes on the wire for a crop this small,
  /// with no visible difference at the size a vision model reads.
  static const int jpegQuality = 75;

  /// Never throws: a missing description must not interrupt tracking. A failure comes
  /// back as [ObjectSnapshotAttempt.failed] carrying the reason.
  Future<ObjectSnapshotAttempt> capture(
    CameraImage image, {
    required Rect boxInImageSpace,
    required int quarterTurns,
    required bool mirror,
  }) async {
    cv.Mat? mat;
    try {
      var grayscale = false;

      // Colour is worth having — "a red mug" beats "a mug" — but the chroma layout varies
      // by handset, so a failure there falls back to the luminance plane rather than
      // losing the description entirely. Luminance is the same data the tracker itself
      // runs on, so wherever tracking works this path works too.
      mat = await _tryColour(image);
      if (mat == null) {
        mat = await _tryLuminance(image);
        grayscale = true;
      }

      if (mat == null) {
        return ObjectSnapshotAttempt.failed(
          'camera format ${image.format.group.name} not supported',
        );
      }

      final crop = _cropRect(boxInImageSpace, mat.cols, mat.rows);
      if (crop == null) {
        return const ObjectSnapshotAttempt.failed('selection too small to crop');
      }

      final snapshot = await _encode(mat, crop, quarterTurns, mirror);
      if (snapshot == null) {
        return const ObjectSnapshotAttempt.failed('JPEG encoding failed');
      }

      return ObjectSnapshotAttempt.success(snapshot, grayscale: grayscale);
    } catch (error) {
      return ObjectSnapshotAttempt.failed(_shortReason(error));
    } finally {
      mat?.dispose();
    }
  }

  /// Keeps OpenCV's assertion text short enough for a HUD line.
  static String _shortReason(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > 110 ? '${text.substring(0, 110)}...' : text;
  }

  /// Colour conversion, or null if this frame's layout defeats it.
  Future<cv.Mat?> _tryColour(CameraImage image) async {
    try {
      return await _toBgr(image);
    } catch (_) {
      return null;
    }
  }

  /// Single-channel fallback: plane 0 is already 8-bit luminance on Android, and on iOS
  /// the interleaved BGRA buffer converts down to one channel.
  Future<cv.Mat?> _tryLuminance(CameraImage image) async {
    try {
      switch (image.format.group) {
        case ImageFormatGroup.yuv420:
        case ImageFormatGroup.nv21:
          final plane = image.planes.first;
          final packed =
              _packRows(plane.bytes, plane.bytesPerRow, image.width, image.height, 1);
          return _matFromBytes(packed, image.width, image.height, cv.MatType.CV_8UC1);
        case ImageFormatGroup.bgra8888:
          final plane = image.planes.first;
          final packed =
              _packRows(plane.bytes, plane.bytesPerRow, image.width, image.height, 4);
          final bgra =
              _matFromBytes(packed, image.width, image.height, cv.MatType.CV_8UC4);
          try {
            return await cv.cvtColorAsync(bgra, cv.COLOR_BGRA2GRAY);
          } finally {
            bgra.dispose();
          }
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------- conversion --

  Future<cv.Mat?> _toBgr(CameraImage image) => switch (image.format.group) {
        ImageFormatGroup.yuv420 || ImageFormatGroup.nv21 => _fromYuv420(image),
        ImageFormatGroup.bgra8888 => _fromBgra(image),
        _ => Future<cv.Mat?>.value(null),
      };

  /// Android hands out YUV_420_888, which is either planar (I420) or semi-planar
  /// (NV21/NV12) depending on the device. `bytesPerPixel` on the chroma plane is
  /// what distinguishes them: 2 means U and V are interleaved in one buffer.
  Future<cv.Mat?> _fromYuv420(CameraImage image) async {
    if (image.planes.length < 3) return null;

    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final ySize = width * height;
    final chromaWidth = width ~/ 2;
    final chromaHeight = height ~/ 2;
    final chromaSize = chromaWidth * chromaHeight;

    final y = _packRows(yPlane.bytes, yPlane.bytesPerRow, width, height, 1);

    if (uPlane.bytesPerPixel == 2) {
      // Semi-planar. The V plane's buffer starts at the first V sample and the U
      // samples sit between them, so reading it as VU pairs yields NV21 directly.
      final vu = _packRows(vPlane.bytes, vPlane.bytesPerRow, chromaWidth, chromaHeight, 2);
      final buffer = Uint8List(ySize + chromaSize * 2);
      buffer.setRange(0, ySize, y);
      final copy = math.min(vu.length, buffer.length - ySize);
      buffer.setRange(ySize, ySize + copy, vu);

      return _convert(buffer, width, height, cv.COLOR_YUV2BGR_NV21);
    }

    // Planar: Y, then a full U plane, then a full V plane.
    final u = _packRows(uPlane.bytes, uPlane.bytesPerRow, chromaWidth, chromaHeight, 1);
    final v = _packRows(vPlane.bytes, vPlane.bytesPerRow, chromaWidth, chromaHeight, 1);

    final buffer = Uint8List(ySize + chromaSize * 2);
    buffer.setRange(0, ySize, y);
    buffer.setRange(ySize, ySize + math.min(u.length, chromaSize), u);
    buffer.setRange(
      ySize + chromaSize,
      ySize + chromaSize + math.min(v.length, chromaSize),
      v,
    );

    return _convert(buffer, width, height, cv.COLOR_YUV2BGR_I420);
  }

  /// Builds the tall single-channel Mat OpenCV expects for YUV 4:2:0 (1.5 rows
  /// of chroma-padded height) and converts it in one call.
  Future<cv.Mat> _convert(Uint8List buffer, int width, int height, int code) async {
    final yuv = _matFromBytes(buffer, width, height + height ~/ 2, cv.MatType.CV_8UC1);
    try {
      return await cv.cvtColorAsync(yuv, code);
    } finally {
      yuv.dispose();
    }
  }

  /// iOS delivers BGRA8888 in a single interleaved plane.
  Future<cv.Mat> _fromBgra(CameraImage image) async {
    final plane = image.planes.first;
    final packed = _packRows(plane.bytes, plane.bytesPerRow, image.width, image.height, 4);
    final bgra = _matFromBytes(packed, image.width, image.height, cv.MatType.CV_8UC4);
    try {
      return await cv.cvtColorAsync(bgra, cv.COLOR_BGRA2BGR);
    } finally {
      bgra.dispose();
    }
  }

  // ------------------------------------------------------------------ crop --

  /// Pads the box for context and clamps it to the frame, in integer pixels.
  cv.Rect? _cropRect(Rect box, int frameWidth, int frameHeight) {
    final padX = box.width * contextPadding;
    final padY = box.height * contextPadding;

    final left = (box.left - padX).clamp(0.0, frameWidth.toDouble()).floor();
    final top = (box.top - padY).clamp(0.0, frameHeight.toDouble()).floor();
    final right = (box.right + padX).clamp(0.0, frameWidth.toDouble()).ceil();
    final bottom = (box.bottom + padY).clamp(0.0, frameHeight.toDouble()).ceil();

    final width = right - left;
    final height = bottom - top;
    if (width < 8 || height < 8) return null;

    return cv.Rect(left, top, width, height);
  }

  Future<ObjectSnapshot?> _encode(
    cv.Mat source,
    cv.Rect crop,
    int quarterTurns,
    bool mirror,
  ) async {
    // region() is a view into `source`, so it must not outlive it — clone before
    // the caller disposes the full frame.
    final view = source.region(crop);
    var working = view.clone();
    view.dispose();

    try {
      working = _replace(working, await _fit(working));
      working = _replace(working, await _orient(working, quarterTurns, mirror));

      final params = cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, jpegQuality]);
      try {
        final (ok, bytes) = await cv.imencodeAsync('.jpg', working, params: params);
        if (!ok || bytes.isEmpty) return null;
        return ObjectSnapshot(base64Jpeg: base64Encode(bytes), byteLength: bytes.length);
      } finally {
        params.dispose();
      }
    } finally {
      working.dispose();
    }
  }

  /// Downscales to [maxEdge] on the longest side. Returns null when already small.
  Future<cv.Mat?> _fit(cv.Mat mat) async {
    final longest = math.max(mat.cols, mat.rows);
    if (longest <= maxEdge) return null;

    final scale = maxEdge / longest;
    return cv.resizeAsync(
      mat,
      ((mat.cols * scale).round(), (mat.rows * scale).round()),
      interpolation: cv.INTER_AREA,
    );
  }

  /// Puts the crop upright the way the user saw it. A sideways or mirrored image
  /// measurably degrades what the model reports, and both are cheap to undo.
  Future<cv.Mat?> _orient(cv.Mat mat, int quarterTurns, bool mirror) async {
    final rotation = switch (quarterTurns % 4) {
      1 => cv.ROTATE_90_CLOCKWISE,
      2 => cv.ROTATE_180,
      3 => cv.ROTATE_90_COUNTERCLOCKWISE,
      _ => null,
    };

    if (rotation == null && !mirror) return null;

    var result = rotation == null ? mat.clone() : await cv.rotateAsync(mat, rotation);
    if (mirror) {
      final flipped = await cv.flipAsync(result, 1);
      result.dispose();
      result = flipped;
    }
    return result;
  }

  /// Swaps [current] for [next], disposing the old Mat. Null means "keep it".
  cv.Mat _replace(cv.Mat current, cv.Mat? next) {
    if (next == null) return current;
    current.dispose();
    return next;
  }

  // ----------------------------------------------------------------- bytes --

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
      // The final chroma row is often short by the stride padding.
      final available = math.min(rowBytes, source.length - start);
      if (available <= 0) break;
      packed.setRange(row * rowBytes, row * rowBytes + available, source, start);
    }
    return packed;
  }
}

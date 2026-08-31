import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/device/device_profile.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/domain/app_settings.dart';
import '../data/camera_frame_converter.dart';
import '../data/fps_meter.dart';
import '../data/object_snapshot.dart';
import '../data/object_tracker.dart';
import '../data/session_api.dart';
import '../data/tracking_socket.dart';
import '../domain/camera_lens.dart';
import '../domain/frame_geometry.dart';
import '../domain/session_dtos.dart';
import '../domain/tracking_status.dart';
import 'tracking_state.dart';

final trackingControllerProvider =
    NotifierProvider<TrackingController, TrackingState>(TrackingController.new);

/// Owns the camera, the OpenCV tracker and the backend session for one run.
///
/// The frame loop is deliberately drop-first: startImageStream fires at the
/// sensor rate, and a frame that arrives while the previous one is still in the
/// tracker is discarded rather than queued. That keeps latency bounded and
/// makes the FPS number honest - it counts frames the tracker really handled.
class TrackingController extends Notifier<TrackingState> {
  /// Side of the seed box, in logical pixels on screen, drawn around a tap.
  static const double seedBoxSideOnScreen = 96;

  /// Smallest usable seed, in camera-image pixels. Below roughly this size the
  /// tracker has too few features to lock onto and loses the target instantly.
  static const double minimumSeedSide = 16;

  static const _trackerFactory = OpenCvTrackerFactory();

  final _converter = CameraFrameConverter();
  final _snapshots = ObjectSnapshotCapture();
  final _fps = FpsMeter();
  final _stopwatch = Stopwatch();

  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  ObjectTracker? _tracker;
  TrackingSocket? _socket;
  StreamSubscription<SocketStatus>? _socketStatusSub;

  String? _sessionId;
  Future<void>? _sessionStart;
  Rect? _pendingSeed;

  /// Seed box still waiting for its colour crop, cleared once one is taken.
  /// Only the first seed of a session is described; re-tapping does not spend
  /// another Groq call on the same run.
  Rect? _pendingSnapshotSeed;
  double _processingScale = 0.5;
  bool _processing = false;
  bool _streaming = false;
  bool _closing = false;
  bool _lostAtLeastOnce = false;

  CameraController? get cameraController => _camera;

  @override
  TrackingState build() {
    final settings = ref.read(settingsControllerProvider);
    _processingScale = settings.processingScale;

    ref.listen<AppSettings>(settingsControllerProvider, (previous, next) {
      _processingScale = next.processingScale;
      if (previous?.lens != next.lens) {
        unawaited(_switchLens(next.lens));
      }
      if (previous?.algorithm != next.algorithm &&
          state.status == TrackingStatus.idle) {
        state = state.copyWith(algorithm: next.algorithm);
      }
    });

    ref.onDispose(() {
      unawaited(_releaseCamera());
      _tracker?.dispose();
      _tracker = null;
      unawaited(_socketStatusSub?.cancel());
    });

    return TrackingState(algorithm: settings.algorithm);
  }

  // ---------------------------------------------------------------- camera --

  /// Opens the camera selected in settings and starts the frame stream.
  Future<void> initializeCamera() async {
    if (_camera != null) return;
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        state = state.copyWith(errorMessage: 'No camera available on this device.');
        return;
      }
      await _openCamera(ref.read(settingsControllerProvider).lens);
    } on CameraException catch (error) {
      state = state.copyWith(errorMessage: _describeCameraError(error));
    } catch (error) {
      state = state.copyWith(errorMessage: 'Camera error: $error');
    }
  }

  /// The `camera` plugin raises the OS permission prompt from `initialize()`,
  /// so a denial arrives here rather than through a permission API.
  String _describeCameraError(CameraException error) => switch (error.code) {
        'CameraAccessDenied' ||
        'CameraAccessDeniedWithoutPrompt' ||
        'CameraAccessRestricted' =>
          'Camera permission is required to track objects. '
              'Enable it in system settings and reopen the app.',
        _ => 'Camera error: ${error.code} ${error.description ?? ''}'.trim(),
      };

  Future<void> _openCamera(CameraLens lens) async {
    final controller = CameraController(
      _describeCamera(lens),
      ResolutionPreset.medium,
      enableAudio: false,
      // The luminance plane is all the tracker needs, on either platform.
      imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );

    await controller.initialize();
    _camera = controller;
    state = state.copyWith(cameraReady: true, clearError: true);

    await controller.startImageStream(_onFrame);
    _streaming = true;
  }

  CameraDescription _describeCamera(CameraLens lens) {
    final wanted = lens == CameraLens.front
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    return _cameras.firstWhere(
      (camera) => camera.lensDirection == wanted,
      orElse: () => _cameras.first,
    );
  }

  /// Front/back toggle. Any running session is closed first: the backend stores
  /// one camera_type per session, so the lens cannot change mid-run.
  Future<void> _switchLens(CameraLens lens) async {
    if (_camera == null) return;
    if (state.status.isRunning) await stopSession();
    await _releaseCamera();
    state = state.copyWith(cameraReady: false, clearBox: true);
    try {
      await _openCamera(lens);
    } on CameraException catch (error) {
      state = state.copyWith(errorMessage: _describeCameraError(error));
    } catch (error) {
      state = state.copyWith(errorMessage: 'Camera error: $error');
    }
  }

  Future<void> _releaseCamera() async {
    final controller = _camera;
    _camera = null;
    if (controller == null) return;
    try {
      if (_streaming) await controller.stopImageStream();
    } catch (_) {
      // The stream may already be torn down; disposing is what matters.
    }
    _streaming = false;
    await controller.dispose();
  }

  /// Releases the camera when the app is backgrounded. Android hands the camera
  /// to whichever app comes to the front, so holding it is not an option.
  Future<void> handleAppPaused() async {
    if (state.status.isRunning) await stopSession();
    await _releaseCamera();
    state = state.copyWith(cameraReady: false, clearBox: true);
  }

  Future<void> handleAppResumed() async {
    if (_camera != null) return;
    await initializeCamera();
  }

  // ------------------------------------------------------------- selection --

  /// Handles a tap on the preview. [imagePoint] and [seedSide] are already in
  /// camera-image coordinates; the seed box is centred and clamped to the frame.
  ///
  /// A tap can only guess at the target's extent, so prefer [selectTargetRect]
  /// when the user has drawn a region: the tracker's accuracy depends heavily on
  /// the seed actually enclosing the object and little else.
  void selectTarget(Offset imagePoint, {required double seedSide}) {
    final geometry = state.geometry;
    if (geometry == null) return;

    final imageSize = geometry.imageSize;
    final side = seedSide.clamp(
      minimumSeedSide,
      imageSize.shortestSide,
    );
    final half = side / 2;

    selectTargetRect(
      Rect.fromLTWH(imagePoint.dx - half, imagePoint.dy - half, side, side),
    );
  }

  /// Seeds the tracker with a region the user drew around the target.
  ///
  /// [imageRect] is in full-resolution camera-image pixels and may extend past
  /// the frame or run in any direction; it is normalised and clipped here.
  void selectTargetRect(Rect imageRect) {
    final geometry = state.geometry;
    if (geometry == null) return;

    final seed = _clipToFrame(imageRect, geometry.imageSize);
    if (seed == null) return;

    _pendingSeed = seed;
    _fps.reset();
    _lostAtLeastOnce = false;
    state = state.copyWith(
      status: TrackingStatus.initializing,
      box: seed,
      fps: 0,
      clearError: true,
    );

    if (_sessionId == null) {
      // First seed of the run: this is the frame that gets described.
      _pendingSnapshotSeed = seed;
      _sessionStart = _startSession();
      unawaited(_sessionStart);
    }
  }

  // --------------------------------------------------------------- session --

  Future<void> _startSession() async {
    final settings = ref.read(settingsControllerProvider);
    final geometry = state.geometry;

    try {
      final device = await ref.read(deviceProfileReaderProvider).read();

      final summary = await ref.read(sessionApiProvider).startSession(
            StartSessionRequest(
              cameraType: settings.lens,
              trackerAlgorithm: settings.algorithm,
              startTime: DateTime.now().toUtc(),
              // The dashboard live grid maps coordinates against this.
              screenWidth: geometry?.imageSize.width.round() ?? 0,
              screenHeight: geometry?.imageSize.height.round() ?? 0,
              processingScale: settings.processingScale,
              device: device,
            ),
          );

      _sessionId = summary.id;
      state = state.copyWith(
        sessionNumber: summary.sessionNumber,
        clearObjectDescription: true,
      );
      await _openSocket(summary.id);
    } catch (error) {
      // Tracking still works offline; only the recording is lost.
      state = state.copyWith(errorMessage: 'Session not recorded: $error');
    }
  }

  Future<void> _openSocket(String sessionId) async {
    final socket = ref.read(trackingSocketProvider);
    _socket = socket;
    await _socketStatusSub?.cancel();
    _socketStatusSub = socket.statusStream.listen((status) {
      state = state.copyWith(
        socketStatus: status,
        droppedFrames: socket.droppedFrames,
      );
    });
    await socket.connect(sessionId);
  }

  /// Ends the run: stops the tracker, flushes the stream, posts the summary.
  Future<void> stopSession() async {
    if (_closing || !state.status.isRunning) return;
    _closing = true;

    final endedLost = state.status == TrackingStatus.lost;
    state = state.copyWith(status: TrackingStatus.finishing);

    _tracker?.dispose();
    _tracker = null;
    _pendingSeed = null;
    _pendingSnapshotSeed = null;
    _sessionStart = null;

    final sessionId = _sessionId;
    _sessionId = null;
    final averageFps = _fps.averageFps;

    try {
      if (sessionId != null) {
        await _socket?.close();
        await ref.read(sessionApiProvider).completeSession(
              sessionId,
              CompleteSessionRequest(
                endTime: DateTime.now().toUtc(),
                averageFps: averageFps,
                // Successful means the user stopped the run with the target
                // still locked, which is what is_successful records.
                isSuccessful: !endedLost,
              ),
            );
      }
    } catch (error) {
      state = state.copyWith(errorMessage: 'Session summary not saved: $error');
    } finally {
      await _socketStatusSub?.cancel();
      _socketStatusSub = null;
      _socket = null;
      _closing = false;
      state = state.copyWith(
        status: TrackingStatus.idle,
        clearBox: true,
        clearSessionNumber: true,
        socketStatus: SocketStatus.disconnected,
        fps: averageFps,
        describing: false,
      );
    }
  }

  // ----------------------------------------------------------- description --

  /// Cuts the colour crop out of the frame that seeded the tracker and sends it
  /// to the backend, which asks Groq what the object is.
  ///
  /// The crop itself is taken inline because [CameraImage] buffers are only
  /// valid for the duration of the stream callback; the upload that follows is
  /// fire-and-forget, so a slow or failed description never stalls tracking.
  Future<void> _captureObjectSnapshot(CameraImage image) async {
    final seed = _pendingSnapshotSeed;
    if (seed == null) return;
    _pendingSnapshotSeed = null;

    final geometry = state.geometry;
    final snapshot = await _snapshots.capture(
      image,
      boxInImageSpace: seed,
      quarterTurns: geometry?.quarterTurns ?? 0,
      mirror: geometry?.mirror ?? false,
    );

    if (snapshot == null) return;

    state = state.copyWith(describing: true);
    unawaited(_describeObject(snapshot));
  }

  Future<void> _describeObject(ObjectSnapshot snapshot) async {
    try {
      // The session id arrives from POST /api/sessions, which may still be in
      // flight when the seed frame is processed.
      await _sessionStart;
      final sessionId = _sessionId;
      if (sessionId == null) return;

      final description = await ref.read(sessionApiProvider).describeObject(
            sessionId,
            DescribeObjectRequest(imageBase64: snapshot.base64Jpeg),
          );

      // The run can end while the model is thinking; don't label the next one.
      if (_sessionId != sessionId) return;
      state = state.copyWith(objectDescription: description, describing: false);
    } catch (error) {
      if (kDebugMode) debugPrint('Object description unavailable: $error');
      state = state.copyWith(describing: false);
    }
  }

  // ------------------------------------------------------------ frame loop --

  Future<void> _onFrame(CameraImage image) async {
    _updateGeometry(image);

    final status = state.status;
    if (status == TrackingStatus.idle || status == TrackingStatus.finishing) {
      return;
    }
    if (_processing) return; // Drop rather than queue.
    _processing = true;

    _stopwatch
      ..reset()
      ..start();

    GrayFrame? frame;
    try {
      frame = await _converter.convert(image, scale: _processingScale);
      final seed = _pendingSeed;
      if (seed != null) {
        await _seedTracker(frame, seed);
        // Must happen before _onFrame returns: the plugin recycles the plane
        // buffers behind `image` as soon as this callback completes.
        await _captureObjectSnapshot(image);
      } else {
        await _advanceTracker(frame);
      }

      _stopwatch.stop();
      _fps.addSample(_stopwatch.elapsed);
      state = state.copyWith(fps: _fps.currentFps);
    } on TrackerUnavailableException catch (error) {
      _pendingSeed = null;
      state = state.copyWith(
        status: TrackingStatus.idle,
        clearBox: true,
        errorMessage: error.message,
      );
    } catch (error) {
      state = state.copyWith(errorMessage: 'Frame error: $error');
    } finally {
      frame?.dispose();
      _processing = false;
    }
  }

  Future<void> _seedTracker(GrayFrame frame, Rect seedInImageSpace) async {
    _pendingSeed = null;
    _tracker?.dispose();

    final algorithm = ref.read(settingsControllerProvider).algorithm;
    final tracker = _trackerFactory.create(algorithm);
    _tracker = tracker;

    await tracker.init(frame.mat, _toFrameSpace(seedInImageSpace, frame.scale));
    state = state.copyWith(status: TrackingStatus.tracking, algorithm: algorithm);
  }

  Future<void> _advanceTracker(GrayFrame frame) async {
    final tracker = _tracker;
    if (tracker == null) return;

    final result = await tracker.update(frame.mat);
    final now = DateTime.now().toUtc();

    if (!result.ok || result.box == null) {
      if (state.status != TrackingStatus.lost) {
        _lostAtLeastOnce = true;
        _socket?.sendEvent(
          SessionEventRequest(eventType: SessionEventType.lost, occurredAt: now),
        );
        state = state.copyWith(status: TrackingStatus.lost);
      }
      return;
    }

    final box = _toImageSpace(result.box!, frame.scale);

    if (state.status == TrackingStatus.lost && _lostAtLeastOnce) {
      _socket?.sendEvent(
        SessionEventRequest(
          eventType: SessionEventType.reacquired,
          occurredAt: now,
        ),
      );
    }

    _socket?.sendFrame(
      FramePayload(
        frameTimestamp: now,
        x: box.left.round(),
        y: box.top.round(),
        width: box.width.round(),
        height: box.height.round(),
      ),
      // Sent per frame so the dashboard HUD shows a live rate rather than
      // waiting for the session average at the end.
      fps: _fps.currentFps,
    );

    state = state.copyWith(status: TrackingStatus.tracking, box: box);
  }

  void _updateGeometry(CameraImage image) {
    final camera = _camera;
    if (camera == null) return;

    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final mirror = camera.description.lensDirection == CameraLensDirection.front;
    final existing = state.geometry;
    if (existing != null &&
        existing.imageSize == imageSize &&
        existing.mirror == mirror) {
      return;
    }

    state = state.copyWith(
      geometry: FrameGeometry(
        imageSize: imageSize,
        // The UI is locked to portrait, so sensor rotation alone puts the frame
        // upright.
        quarterTurns: (camera.description.sensorOrientation ~/ 90) % 4,
        mirror: mirror,
      ),
    );
  }

  /// Normalises a drawn region and clips it to the frame, or returns null when
  /// what survives is too small to track.
  Rect? _clipToFrame(Rect rect, Size imageSize) {
    final normalised = Rect.fromLTRB(
      math.min(rect.left, rect.right),
      math.min(rect.top, rect.bottom),
      math.max(rect.left, rect.right),
      math.max(rect.top, rect.bottom),
    );

    final clipped = Rect.fromLTRB(
      normalised.left.clamp(0.0, imageSize.width),
      normalised.top.clamp(0.0, imageSize.height),
      normalised.right.clamp(0.0, imageSize.width),
      normalised.bottom.clamp(0.0, imageSize.height),
    );

    if (clipped.width < minimumSeedSide || clipped.height < minimumSeedSide) {
      return null;
    }
    return clipped;
  }

  /// Full-resolution image pixels -> downscaled tracker pixels.
  Rect _toFrameSpace(Rect rect, double scale) => Rect.fromLTWH(
        rect.left * scale,
        rect.top * scale,
        rect.width * scale,
        rect.height * scale,
      );

  /// Downscaled tracker pixels -> full-resolution image pixels.
  Rect _toImageSpace(Rect rect, double scale) => Rect.fromLTWH(
        rect.left / scale,
        rect.top / scale,
        rect.width / scale,
        rect.height / scale,
      );
}

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/application/settings_controller.dart';
import '../../settings/presentation/settings_screen.dart';
import '../application/tracking_controller.dart';
import '../domain/frame_geometry.dart';
import '../domain/tracking_status.dart';
import 'widgets/bounding_box_painter.dart';
import 'widgets/hud_overlay.dart';

/// Full-screen preview with the tap-to-track overlay and the HUD.
class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen>
    with WidgetsBindingObserver {
  /// Shorter drags are treated as taps rather than as a drawn region.
  static const double _minimumDragSide = 24;

  Offset? _dragStart;
  Offset? _dragEnd;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Providers must not be mutated during the first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(trackingControllerProvider.notifier).initializeCamera();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(trackingControllerProvider.notifier);
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        controller.handleAppPaused();
      case AppLifecycleState.resumed:
        controller.handleAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trackingControllerProvider);
    final controller = ref.watch(trackingControllerProvider.notifier);
    final settings = ref.watch(settingsControllerProvider);
    final camera = controller.cameraController;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (state.cameraReady && camera != null && camera.value.isInitialized)
            _PreviewSurface(
              camera: camera,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = Size(constraints.maxWidth, constraints.maxHeight);
                  final geometry = state.geometry;

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: geometry == null
                        ? null
                        : (details) => _selectTarget(
                              details.localPosition,
                              geometry,
                              viewport,
                            ),
                    onPanStart: geometry == null
                        ? null
                        : (details) => setState(() {
                              _dragStart = details.localPosition;
                              _dragEnd = details.localPosition;
                            }),
                    onPanUpdate: geometry == null
                        ? null
                        : (details) =>
                            setState(() => _dragEnd = details.localPosition),
                    onPanEnd: geometry == null
                        ? null
                        : (_) => _commitDrag(geometry, viewport),
                    onPanCancel: () => setState(() {
                      _dragStart = null;
                      _dragEnd = null;
                    }),
                    child: CustomPaint(
                      size: viewport,
                      painter: BoundingBoxPainter(
                        box: state.box,
                        geometry: geometry,
                        color: settings.boxColor,
                        status: state.status,
                        selection: _selectionRect,
                      ),
                    ),
                  );
                },
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white70)),
          Positioned(top: 0, left: 0, right: 0, child: HudOverlay(state: state)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ControlBar(
              status: state.status,
              onStop: controller.stopSession,
              onSettings: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _selectTarget(Offset localPosition, FrameGeometry geometry, Size viewport) {
    final projection = FrameProjection(geometry: geometry, viewport: viewport);
    ref.read(trackingControllerProvider.notifier).selectTarget(
          projection.viewportToImage(localPosition),
          seedSide: projection.viewportLengthToImage(
            TrackingController.seedBoxSideOnScreen,
          ),
        );
  }

  /// Rectangle being dragged out, in viewport pixels, or null when idle.
  Rect? get _selectionRect {
    final start = _dragStart;
    final end = _dragEnd;
    if (start == null || end == null) return null;
    return Rect.fromPoints(start, end);
  }

  /// Turns the drawn rectangle into the tracker's seed region.
  ///
  /// The two corners are projected individually rather than the rectangle as a
  /// whole: rotation and mirroring can swap which corner ends up top-left, and
  /// `Rect.fromPoints` re-normalises afterwards.
  void _commitDrag(FrameGeometry geometry, Size viewport) {
    final selection = _selectionRect;
    setState(() {
      _dragStart = null;
      _dragEnd = null;
    });

    // A stray flick during a tap should not reseed the tracker.
    if (selection == null || selection.shortestSide < _minimumDragSide) return;

    final projection = FrameProjection(geometry: geometry, viewport: viewport);
    ref.read(trackingControllerProvider.notifier).selectTargetRect(
          Rect.fromPoints(
            projection.viewportToImage(selection.topLeft),
            projection.viewportToImage(selection.bottomRight),
          ),
        );
  }
}

/// Sizes the preview so it covers the screen, matching the `BoxFit.cover`
/// assumption the projection math makes.
class _PreviewSurface extends StatelessWidget {
  const _PreviewSurface({required this.camera, required this.child});

  final CameraController camera;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = camera.value.previewSize;
        // previewSize is reported in sensor orientation; the widget is upright.
        final aspect = previewSize == null
            ? 1 / camera.value.aspectRatio
            : previewSize.height / previewSize.width;

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxWidth / aspect,
                  child: CameraPreview(camera),
                ),
              ),
              child,
            ],
          ),
        );
      },
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.status,
    required this.onStop,
    required this.onSettings,
  });

  final TrackingStatus status;
  final Future<void> Function() onStop;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Row(
          children: [
            Expanded(
              child: Text(
                status.isRunning
                    ? 'Drag a new box to re-seed the tracker'
                    : 'Drag a box around the object, or tap it',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            if (status.isRunning)
              FilledButton.icon(
                onPressed: onStop,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE53935),
                ),
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Stop'),
              ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: onSettings,
              icon: const Icon(Icons.tune_rounded),
              tooltip: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

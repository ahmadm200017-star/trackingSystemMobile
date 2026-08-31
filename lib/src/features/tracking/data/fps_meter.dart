/// Tracks throughput of the tracking loop.
///
/// The HUD shows a smoothed instantaneous value so it does not flicker, while
/// the session summary sent to the backend uses the true arithmetic mean over
/// every processed frame.
class FpsMeter {
  FpsMeter({this.smoothing = 0.2});

  /// Weight of the newest sample in the exponential moving average.
  final double smoothing;

  double _totalSeconds = 0;
  int _frames = 0;
  double _smoothedFps = 0;

  int get frameCount => _frames;

  /// Smoothed frames-per-second, for display.
  double get currentFps => _smoothedFps;

  /// Mean frames-per-second across the whole session.
  double get averageFps => _totalSeconds <= 0 ? 0 : _frames / _totalSeconds;

  /// Records the wall time spent producing one tracked frame.
  void addSample(Duration elapsed) {
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0) return;

    _frames++;
    _totalSeconds += seconds;

    final instant = 1 / seconds;
    _smoothedFps = _frames == 1
        ? instant
        : _smoothedFps + smoothing * (instant - _smoothedFps);
  }

  void reset() {
    _totalSeconds = 0;
    _frames = 0;
    _smoothedFps = 0;
  }
}

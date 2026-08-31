import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/config/app_config.dart';
import '../domain/session_dtos.dart';

enum SocketStatus { disconnected, connecting, connected }

/// Not auto-disposed: the controller holds it through `ref.read`, which would
/// leave an auto-disposed provider with no listener and tear the socket down
/// mid-session.
final trackingSocketProvider = Provider<TrackingSocket>((ref) {
  final socket = TrackingSocket(config: ref.watch(appConfigProvider));
  ref.onDispose(socket.dispose);
  return socket;
});

/// Streams tracked frames to the backend so the dashboard "Live Tracking Room"
/// can redraw the bounding box in real time.
///
/// Wire format is flat, one message per line — see `backend/README.md`:
///   `{"type": "frame",  "frameTimestamp": ..., "x": .., "y": .., "width": .., "height": .., "fps": ..}`
///   `{"type": "status", "state": "lost" | "reacquired", "occurredAt": ...}`
/// The session is identified by the `sessionId` query parameter on the socket
/// itself, so it is not repeated in each message.
///
/// The socket is deliberately lossy. Frames arrive at camera rate and a stalled
/// connection must never grow the heap or stall the tracking loop, so pending
/// frames sit in a bounded queue and the oldest are dropped first.
class TrackingSocket {
  TrackingSocket({
    required AppConfig config,
    this.maxQueuedFrames = 600,
    this.maxBackoff = const Duration(seconds: 15),
  }) : _config = config;

  final AppConfig _config;

  /// Roughly 20 seconds of frames at 30 fps.
  final int maxQueuedFrames;
  final Duration maxBackoff;

  final _statusController = StreamController<SocketStatus>.broadcast();
  final _pending = <Map<String, dynamic>>[];

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  String? _sessionId;
  int _attempt = 0;
  int _droppedFrames = 0;
  bool _closedByUser = false;
  bool _disposed = false;
  SocketStatus _status = SocketStatus.disconnected;

  Stream<SocketStatus> get statusStream => _statusController.stream;

  SocketStatus get status => _status;

  /// Frames discarded because the connection could not keep up. Surfaced in the
  /// HUD so a degraded stream is visible rather than silent.
  int get droppedFrames => _droppedFrames;

  /// Opens the stream for [sessionId]. Safe to call once per session.
  Future<void> connect(String sessionId) async {
    _closedByUser = false;
    _sessionId = sessionId;
    _attempt = 0;
    _droppedFrames = 0;
    await _open();
  }

  /// [fps] is the tracker's current rate; the dashboard HUD shows it live.
  void sendFrame(FramePayload frame, {double? fps}) => _enqueue({
        'type': 'frame',
        ...frame.toJson(),
        if (fps != null && fps > 0) 'fps': double.parse(fps.toStringAsFixed(2)),
      });

  void sendEvent(SessionEventRequest event) => _enqueue({
        'type': 'status',
        'state': event.eventType.wireName,
        'occurredAt': event.occurredAt.toUtc().toIso8601String(),
      });

  /// Ends the session stream. Pending frames are flushed on a best-effort basis.
  Future<void> close() async {
    _closedByUser = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_status == SocketStatus.connected) _flush();
    await _teardown();
    _pending.clear();
    _sessionId = null;
    _setStatus(SocketStatus.disconnected);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await close();
    await _statusController.close();
  }

  Future<void> _open() async {
    if (_disposed || _closedByUser || _sessionId == null) return;

    _setStatus(SocketStatus.connecting);
    try {
      final uri = _config.socket('/ws/track', {'sessionId': _sessionId!});
      final channel = WebSocketChannel.connect(uri);
      await channel.ready;

      _channel = channel;
      _subscription = channel.stream.listen(
        // The mobile app is write-only today; the dashboard is the reader.
        (_) {},
        onError: (Object _) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );

      _attempt = 0;
      _setStatus(SocketStatus.connected);
      _flush();
    } catch (_) {
      await _teardown();
      _scheduleReconnect();
    }
  }

  void _enqueue(Map<String, dynamic> message) {
    if (_disposed || _closedByUser || _sessionId == null) return;

    if (_status == SocketStatus.connected && _pending.isEmpty) {
      _write(message);
      return;
    }

    _pending.add(message);
    while (_pending.length > maxQueuedFrames) {
      final dropped = _pending.removeAt(0);
      if (dropped['type'] == 'frame') _droppedFrames++;
    }
    if (_status == SocketStatus.connected) _flush();
  }

  void _flush() {
    while (_pending.isNotEmpty && _status == SocketStatus.connected) {
      _write(_pending.removeAt(0));
    }
  }

  void _write(Map<String, dynamic> message) {
    final sink = _channel?.sink;
    if (sink == null) {
      _pending.insert(0, message);
      return;
    }
    try {
      sink.add(jsonEncode(message));
    } catch (_) {
      _pending.insert(0, message);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed || _closedByUser || _reconnectTimer != null) return;

    _setStatus(SocketStatus.disconnected);
    unawaited(_teardown());

    final delayMs = (1000 * (1 << _attempt.clamp(0, 4))).clamp(1000, maxBackoff.inMilliseconds);
    _attempt++;
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      _reconnectTimer = null;
      unawaited(_open());
    });
  }

  Future<void> _teardown() async {
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;

    await subscription?.cancel();
    try {
      await channel?.sink.close();
    } catch (_) {
      // Closing an already-broken socket is not interesting.
    }
  }

  void _setStatus(SocketStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }
}

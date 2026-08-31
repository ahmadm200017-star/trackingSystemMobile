import 'package:flutter/material.dart';

import '../../application/tracking_state.dart';
import '../../data/tracking_socket.dart';
import '../../domain/tracking_status.dart';

/// Heads-up display pinned to the top of the tracking screen: which algorithm
/// is running, how fast it is running, and whether the target is still held.
class HudOverlay extends StatelessWidget {
  const HudOverlay({super.key, required this.state});

  final TrackingState state;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    _HudChip(
                      label: 'Tracker',
                      value: state.algorithm.label,
                    ),
                    const SizedBox(width: 18),
                    _HudChip(
                      label: 'FPS',
                      value: state.fps <= 0 ? '--' : state.fps.toStringAsFixed(1),
                    ),
                    const Spacer(),
                    _StatusPill(status: state.status),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            _ConnectionLine(state: state),
            if (state.describing || state.objectDescription != null) ...[
              const SizedBox(height: 8),
              _ObjectLine(
                description: state.objectDescription,
                pending: state.describing,
              ),
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: 8),
              _ErrorBanner(message: state.errorMessage!),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the backend's vision model made of the object the user selected. Shown
/// as feedback only - a description that never arrives changes nothing else.
class _ObjectLine extends StatelessWidget {
  const _ObjectLine({required this.description, required this.pending});

  final String? description;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (pending)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: Colors.white70),
              )
            else
              const Icon(Icons.auto_awesome, size: 14, color: Colors.white70),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                description ?? 'Identifying object...',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: pending ? Colors.white70 : Colors.white,
                  fontSize: 13,
                  fontStyle: pending ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HudChip extends StatelessWidget {
  const _HudChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final TrackingStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TrackingStatus.tracking => const Color(0xFF00E676),
      TrackingStatus.lost => const Color(0xFFFF5252),
      TrackingStatus.initializing => const Color(0xFFFFC400),
      TrackingStatus.finishing => const Color(0xFF40C4FF),
      TrackingStatus.idle => Colors.white54,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            status.label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionLine extends StatelessWidget {
  const _ConnectionLine({required this.state});

  final TrackingState state;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (state.socketStatus) {
      SocketStatus.connected => (
          Icons.cloud_done_outlined,
          const Color(0xFF00E676),
          state.sessionNumber == null
              ? 'Streaming'
              : 'Streaming - ${state.sessionNumber}',
        ),
      SocketStatus.connecting => (
          Icons.cloud_sync_outlined,
          const Color(0xFFFFC400),
          'Connecting to backend',
        ),
      SocketStatus.disconnected => (
          Icons.cloud_off_outlined,
          Colors.white54,
          state.isSessionLive ? 'Reconnecting - buffering frames' : 'Offline',
        ),
    };

    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 12),
          ),
        ),
        if (state.droppedFrames > 0) ...[
          const SizedBox(width: 10),
          Text(
            '${state.droppedFrames} dropped',
            style: const TextStyle(color: Color(0xFFFF8A65), fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFB71C1C).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

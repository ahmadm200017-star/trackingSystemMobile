import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/domain/camera_lens.dart';
import '../../tracking/domain/tracker_algorithm.dart';
import '../data/settings_repository.dart';
import '../domain/app_settings.dart';

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsRepositoryProvider).read();

  void setAlgorithm(TrackerAlgorithm algorithm) =>
      _update(state.copyWith(algorithm: algorithm));

  void setLens(CameraLens lens) => _update(state.copyWith(lens: lens));

  void setBoxColor(Color color) => _update(state.copyWith(boxColor: color));

  void setProcessingScale(double scale) => _update(
        state.copyWith(
          processingScale: scale.clamp(
            AppSettings.minProcessingScale,
            AppSettings.maxProcessingScale,
          ),
        ),
      );

  void setCameraHorizontalFovDegrees(double degrees) => _update(
        state.copyWith(
          cameraHorizontalFovDegrees: degrees.clamp(
            AppSettings.minHorizontalFov,
            AppSettings.maxHorizontalFov,
          ),
        ),
      );

  void setAssumedCameraHeightMeters(double metres) => _update(
        state.copyWith(
          assumedCameraHeightMeters: metres.clamp(
            AppSettings.minCameraHeight,
            AppSettings.maxCameraHeight,
          ),
        ),
      );

  void _update(AppSettings next) {
    if (next == state) return;
    state = next;
    // Fire-and-forget: the in-memory state is the source of truth for the
    // running session, persistence only has to survive an app restart.
    unawaited(ref.read(settingsRepositoryProvider).write(next));
  }
}

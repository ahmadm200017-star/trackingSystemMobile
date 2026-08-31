import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../tracking/domain/camera_lens.dart';
import '../../tracking/domain/tracker_algorithm.dart';
import '../domain/app_settings.dart';

/// Bound in `main()` once `SharedPreferences` has been opened.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(sharedPreferencesProvider)),
);

class SettingsRepository {
  SettingsRepository(this._prefs);

  static const _kAlgorithm = 'settings.algorithm';
  static const _kLens = 'settings.lens';
  static const _kBoxColor = 'settings.boxColor';
  static const _kProcessingScale = 'settings.processingScale';

  final SharedPreferences _prefs;

  AppSettings read() {
    const fallback = AppSettings();
    final algorithm = _prefs.getString(_kAlgorithm);
    final lens = _prefs.getString(_kLens);
    final color = _prefs.getInt(_kBoxColor);
    final scale = _prefs.getDouble(_kProcessingScale);

    return AppSettings(
      algorithm:
          algorithm == null ? fallback.algorithm : TrackerAlgorithm.fromWire(algorithm),
      lens: lens == null ? fallback.lens : CameraLens.fromWire(lens),
      boxColor: color == null ? fallback.boxColor : Color(color),
      processingScale: scale == null
          ? fallback.processingScale
          : scale.clamp(
              AppSettings.minProcessingScale,
              AppSettings.maxProcessingScale,
            ),
    );
  }

  Future<void> write(AppSettings settings) async {
    await Future.wait([
      _prefs.setString(_kAlgorithm, settings.algorithm.wireName),
      _prefs.setString(_kLens, settings.lens.wireName),
      _prefs.setInt(_kBoxColor, settings.boxColor.toARGB32()),
      _prefs.setDouble(_kProcessingScale, settings.processingScale),
    ]);
  }
}

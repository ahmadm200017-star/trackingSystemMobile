import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Identifies the handset a session was recorded on.
///
/// Sent once with `POST /api/sessions` so the dashboard can attribute an FPS
/// number to a device rather than to the app in the abstract - the same tracker
/// at the same resolution behaves very differently across handsets.
class DeviceProfile {
  const DeviceProfile({this.model, this.osVersion, this.appVersion});

  /// Manufacturer and model, e.g. "Google Pixel 7" or "Apple iPhone 14 Pro".
  final String? model;

  /// Platform and release, e.g. "Android 14 (SDK 34)".
  final String? osVersion;

  /// App version and build number, e.g. "1.0.0+1".
  final String? appVersion;

  Map<String, dynamic> toJson() => {
        if (model != null) 'deviceModel': model,
        if (osVersion != null) 'osVersion': osVersion,
        if (appVersion != null) 'appVersion': appVersion,
      };
}

/// Reads the device identity once and caches it for the process.
///
/// Every field is optional: a plugin failure must never stop a session from
/// starting, so failures collapse to nulls rather than exceptions.
class DeviceProfileReader {
  DeviceProfile? _cached;

  Future<DeviceProfile> read() async {
    final cached = _cached;
    if (cached != null) return cached;

    final profile = DeviceProfile(
      model: await _model(),
      osVersion: await _osVersion(),
      appVersion: await _appVersion(),
    );
    _cached = profile;
    return profile;
  }

  Future<String?> _model() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        return _join(android.manufacturer, android.model);
      }
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        // utsname.machine is the hardware id ("iPhone15,2"); `model` is the
        // friendlier family name and is what a reader expects to see.
        return _join('Apple', ios.model);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _osVersion() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        return 'Android ${android.version.release} (SDK ${android.version.sdkInt})';
      }
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return '${ios.systemName} ${ios.systemVersion}';
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = info.buildNumber;
      return build.isEmpty ? info.version : '${info.version}+$build';
    } catch (_) {
      return null;
    }
  }

  /// Avoids "Google Google Pixel" when the model already names the maker.
  static String? _join(String? maker, String? model) {
    final make = maker?.trim() ?? '';
    final name = model?.trim() ?? '';
    if (name.isEmpty) return make.isEmpty ? null : make;
    if (make.isEmpty) return name;
    if (name.toLowerCase().startsWith(make.toLowerCase())) return name;
    return '$make $name';
  }
}

final deviceProfileReaderProvider =
    Provider<DeviceProfileReader>((ref) => DeviceProfileReader());

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runtime endpoints for the tracker backend.
///
/// Override at build time, e.g.
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:5201`.
/// The default points at `10.0.2.2`, which is how the Android emulator reaches
/// the host machine where `MdfTracker.Api` listens (see launchSettings.json).
class AppConfig {
  const AppConfig({required this.apiBaseUrl, required this.wsBaseUrl});

  factory AppConfig.fromEnvironment() {
    const api = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:5201',
    );
    const ws = String.fromEnvironment('WS_BASE_URL');
    return AppConfig(
      apiBaseUrl: _stripTrailingSlash(api),
      wsBaseUrl: ws.isEmpty ? _deriveWsBase(api) : _stripTrailingSlash(ws),
    );
  }

  final String apiBaseUrl;
  final String wsBaseUrl;

  Uri rest(String path) => Uri.parse('$apiBaseUrl$path');

  Uri socket(String path, [Map<String, String> query = const {}]) {
    final uri = Uri.parse('$wsBaseUrl$path');
    return query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  static String _stripTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;

  static String _deriveWsBase(String apiBaseUrl) {
    final uri = Uri.parse(_stripTrailingSlash(apiBaseUrl));
    return uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws').toString();
  }
}

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment());

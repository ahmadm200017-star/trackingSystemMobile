/// Raised when the tracker backend answers with a non-2xx status or is
/// unreachable. Carries enough context for the HUD to show something useful.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.uri});

  final String message;
  final int? statusCode;
  final Uri? uri;

  @override
  String toString() {
    final code = statusCode == null ? '' : ' ($statusCode)';
    return 'ApiException$code: $message';
  }
}

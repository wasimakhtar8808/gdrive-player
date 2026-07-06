class ServerException implements Exception {
  final String message;
  ServerException([this.message = 'An unexpected server error occurred.']);

  @override
  String toString() => message;
}

class CacheException implements Exception {
  final String message;
  CacheException([this.message = 'An error occurred while accessing stored data.']);

  @override
  String toString() => message;
}

class NetworkException implements Exception {
  final String message;
  NetworkException([this.message = 'Please check your internet connection and try again.']);

  @override
  String toString() => message;
}

class AuthException implements Exception {
  final String message;
  AuthException([this.message = 'Invalid API key or Access Token.']);

  @override
  String toString() => message;
}

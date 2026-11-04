class ServerException implements Exception {
  final String message;
  final int? statusCode;

  const ServerException(this.message, [this.statusCode]);

  @override
  String toString() => 'ServerException: $message ($statusCode)';
}

class NetworkException implements Exception {
  final String message;

  const NetworkException([this.message = 'Network error']);

  @override
  String toString() => 'NetworkException: $message';
}

class ParsingException implements Exception {
  final String message;

  const ParsingException([this.message = 'Data parsing failed']);

  @override
  String toString() => 'ParsingException: $message';
}


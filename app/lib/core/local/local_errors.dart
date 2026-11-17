/// Domain errors for the local application engine.
///
/// The class names are retained from the former network client so existing
/// feature error handlers remain stable, but there is no HTTP API behind them.
class ApiException implements Exception {
  ApiException(this.message, {this.code = 'LOCAL', this.statusCode});
  final String message;
  final String code;
  final int? statusCode;

  @override
  String toString() => message;
}

class OfflineException extends ApiException {
  OfflineException([String message = '本地数据暂时不可用']) : super(message);
}

class AuthRequiredException extends ApiException {
  AuthRequiredException([String message = '本地应用不需要登录'])
    : super(message, code: 'AUTH_REQUIRED', statusCode: 401);
}

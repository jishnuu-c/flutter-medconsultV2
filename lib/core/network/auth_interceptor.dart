import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class AuthInterceptor extends Interceptor {
  final String? Function() getToken;
  final VoidCallback? onUnauthorized;

  AuthInterceptor({
    required this.getToken,
    this.onUnauthorized,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = getToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      if (onUnauthorized != null) {
        onUnauthorized!();
      }
    }
    super.onError(err, handler);
  }
}

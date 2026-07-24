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
      // Any single 401, from ANY request anywhere in the app, force-logs the
      // user out (see onUnauthorized below) and the router then bounces them
      // back to /login. That's why a doctor can land on a dashboard for a
      // moment and then get kicked straight back to the login screen — some
      // OTHER request fired in the background (e.g. the schedule screen's
      // own data fetch) came back 401 even though the login itself was fine.
      // Logging the exact request here is the only way to know which
      // endpoint is doing that.
      print('--- 401 UNAUTHORIZED — this will force a logout ---');
      print('Request: ${err.requestOptions.method} ${err.requestOptions.path}');
      print('Response: ${err.response?.data}');
      print('----------------------------------------------------');
      if (onUnauthorized != null) {
        onUnauthorized!();
      }
    }
    super.onError(err, handler);
  }
}

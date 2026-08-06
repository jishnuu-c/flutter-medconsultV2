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
      // Angular reference (auth.interceptor.ts) does NOT force logout on
      // 401 at all — it only toasts on 403. A 401 here is often a specific
      // endpoint's own authorization response (e.g. doctor hitting a
      // patient's health-profile they're not permitted for), not proof the
      // session token itself is invalid. Force-logging-out on every 401
      // from every endpoint was kicking the user out mid-session whenever
      // any background call (health-profile, vitals, etc.) came back 401.
      //
      // Only treat it as a real session expiry when it's the endpoint that
      // actually verifies the session (/users/me, /auth/*). Everything else
      // just logs and lets the caller's own error handling (already in
      // place via .catchError in the screens) deal with it — same as
      // Angular.
      final path = err.requestOptions.path;
      final isSessionEndpoint =
          path.contains('/users/me') || path.contains('/auth/');

      print('--- 401 UNAUTHORIZED ---');
      print('Request: ${err.requestOptions.method} ${err.requestOptions.path}');
      print('Response: ${err.response?.data}');
      print('Forcing logout: $isSessionEndpoint');
      print('------------------------');

      if (isSessionEndpoint && onUnauthorized != null) {
        onUnauthorized!();
      }
    }
    super.onError(err, handler);
  }
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_interceptor.dart';
import '../auth/auth_session.dart';

const String kBaseUrl = String.fromEnvironment(
  'API_URL',
  // defaultValue: 'http://192.168.1.110:8080',
  defaultValue: 'http://192.168.1.142:8080',
  // defaultValue: 'http://103.199.210.172:8080',
);

final apiClientProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: kBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
      },
    ),
  );

  dio.interceptors.add(
    AuthInterceptor(
      getToken: () => AuthSession.token,
      onUnauthorized: () => AuthSession.onUnauthorized?.call(),
    ),
  );

  return dio;
});

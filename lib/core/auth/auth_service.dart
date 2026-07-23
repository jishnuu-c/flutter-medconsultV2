import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../models/auth_models.dart';

class AuthService {
  final Dio dio;

  AuthService({required this.dio});

  Future<AuthResponseDto> login(Map<String, dynamic> credentials) async {
    final response = await dio.post(
      '/api/medconsult/auth/login',
      data: credentials,
    );
    print('Status: ${response.statusCode}');
    print('Headers: ${response.headers}');
    print('Data: ${response.data}');

    debugPrint('Response: ${response.data}');
    return AuthResponseDto.fromJson(response.data);
  }

  Future<AuthResponseDto> register(Map<String, dynamic> payload) async {
    final response = await dio.post(
      '/api/medconsult/auth/register',
      data: payload,
    );
    return AuthResponseDto.fromJson(response.data);
  }

  Future<UserModel> fetchCurrentUser() async {
    final response = await dio.get('/api/medconsult/users/me');
    return UserModel.fromJson(response.data);
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return AuthService(dio: dio);
});

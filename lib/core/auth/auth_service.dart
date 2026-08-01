import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../models/auth_models.dart';

class AuthService {
  final Dio dio;

  AuthService({required this.dio});

  Future<AuthResponseDto> login(Map<String, dynamic> credentials) async {
    print('Login credentials: $credentials');
    print('🔗 API URL: ${dio.options.baseUrl}/api/medconsult/auth/login');
    try {
      final response = await dio.post(
        '/api/medconsult/auth/login',
        data: credentials,
      );
      print('Status: ${response.statusCode}');
      print('Headers: ${response.headers}');
      print('Data: ${response.data}');

      debugPrint('Response: ${response.data}');
      return AuthResponseDto.fromJson(response.data);
    } on DioException catch (e) {
      print('--- LOGIN DIO EXCEPTION ---');
      print('Message: ${e.message}');
      print('Type: ${e.type}');
      print('Status Code: ${e.response?.statusCode}');
      print('Headers: ${e.response?.headers}');
      print('Response Data: ${e.response?.data}');
      print('Error: ${e.error}');
      print('---------------------------');
      rethrow;
    } catch (e, stack) {
      print('--- LOGIN ERROR ---');
      print('Error: $e');
      print('Stack: $stack');
      print('-------------------');
      rethrow;
    }
  }

  Future<AuthResponseDto> register(Map<String, dynamic> payload) async {
    final response = await dio.post(
      '/api/medconsult/auth/register',
      data: payload,
    );
    return AuthResponseDto.fromJson(response.data);
  }

  Future<UserModel> fetchCurrentUser() async {
    try {
      final response = await dio.get('/api/medconsult/users/me');
      print('--- /users/me RESPONSE ---');
      print('Status: ${response.statusCode}');
      print('Data: ${response.data}');
      print('--------------------------');
      return UserModel.fromJson(response.data);
    } on DioException catch (e) {
      print('--- /users/me DIO EXCEPTION ---');
      print('Status Code: ${e.response?.statusCode}');
      print('Response Data: ${e.response?.data}');
      print('Message: ${e.message}');
      print('-------------------------------');
      rethrow;
    }
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return AuthService(dio: dio);
});

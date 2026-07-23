import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/auth_models.dart';
import '../network/api_client.dart';

class UserService {
  final Dio dio;

  UserService({required this.dio});

  Future<List<UserModel>> getAllUsers() async {
    final response = await dio.get('/api/medconsult/users/all');
    final List list = response.data ?? [];
    return list.map((item) => UserModel.fromJson(item)).toList();
  }
}

final userServiceProvider = Provider<UserService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return UserService(dio: dio);
});

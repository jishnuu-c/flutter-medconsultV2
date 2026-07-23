import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class CaseRoomService {
  final Dio dio;

  CaseRoomService({required this.dio});

  Future<List<dynamic>> searchCaseRooms(Map<String, dynamic> searchRequest) async {
    final res = await dio.post('/api/medconsult/caserooms/search', data: searchRequest);
    if (res.data is Map && res.data['content'] != null) {
      return res.data['content'];
    }
    return res.data is List ? res.data : [];
  }

  Future<dynamic> openCaseRoom(Map<String, dynamic> dto) async {
    final res = await dio.post('/api/medconsult/caserooms/', data: dto);
    return res.data;
  }

  Future<List<dynamic>> getPostsForRoom(String caseRoomId, {int page = 0, int size = 10}) async {
    final res = await dio.get(
      '/api/medconsult/caserooms/posts/room/$caseRoomId',
      queryParameters: {'page': page, 'size': size},
    );
    if (res.data is Map && res.data['content'] != null) {
      return res.data['content'];
    }
    return res.data is List ? res.data : [];
  }

  Future<dynamic> createPost(Map<String, dynamic> dto) async {
    final res = await dio.post('/api/medconsult/caserooms/posts/', data: dto);
    return res.data;
  }
}

final caseRoomServiceProvider = Provider<CaseRoomService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return CaseRoomService(dio: dio);
});

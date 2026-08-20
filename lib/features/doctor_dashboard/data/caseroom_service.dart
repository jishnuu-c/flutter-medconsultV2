import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

// Mirrors case-room.service.ts (Angular) — endpoints under
// /api/medconsult/caserooms/*. Kept loosely typed (dynamic/Map) to match
// this app's existing convention for the doctor-dashboard feature services
// (see appointment_service.dart, consultation_service.dart).
class CaseRoomService {
  final Dio dio;

  CaseRoomService({required this.dio});

  List<dynamic> _extractList(dynamic data) {
    if (data is Map && data['content'] != null) return data['content'];
    return data is List ? data : [];
  }

  // --- Case Rooms ---

  Future<dynamic> openCaseRoom(Map<String, dynamic> dto) async {
    final res = await dio.post('/api/medconsult/caserooms/', data: dto);
    return res.data;
  }

  Future<dynamic> getCaseRoomById(String id) async {
    final res = await dio.get('/api/medconsult/caserooms/$id');
    return res.data;
  }

  Future<List<dynamic>> searchCaseRooms(
      Map<String, dynamic> searchRequest) async {
    final res =
        await dio.post('/api/medconsult/caserooms/search', data: searchRequest);
    return _extractList(res.data);
  }

  Future<dynamic> updateStatus(
      String id, Map<String, dynamic> statusRequest) async {
    final res = await dio.patch('/api/medconsult/caserooms/$id/status',
        data: statusRequest);
    return res.data;
  }

  // --- Posts ---

  Future<dynamic> createPost(Map<String, dynamic> dto) async {
    final res = await dio.post('/api/medconsult/caserooms/posts/', data: dto);
    return res.data;
  }

  Future<List<dynamic>> getPostsForRoom(String caseRoomId,
      {int page = 0, int size = 10}) async {
    final res = await dio.get(
      '/api/medconsult/caserooms/posts/room/$caseRoomId',
      queryParameters: {'page': page, 'size': size},
    );
    return _extractList(res.data);
  }

  Future<dynamic> updatePostActionStatus(
      String postId, Map<String, dynamic> statusRequest) async {
    final res = await dio.patch(
      '/api/medconsult/caserooms/posts/$postId/action-status',
      data: statusRequest,
    );
    return res.data;
  }

  // --- Members ---

  Future<dynamic> addMember(Map<String, dynamic> dto) async {
    final res = await dio.post('/api/medconsult/caserooms/members/', data: dto);
    return res.data;
  }

  Future<List<dynamic>> getMembersForRoom(String caseRoomId) async {
    final res =
        await dio.get('/api/medconsult/caserooms/members/room/$caseRoomId');
    return _extractList(res.data);
  }

  Future<dynamic> removeMember(String memberId) async {
    final res = await dio.delete('/api/medconsult/caserooms/members/$memberId');
    return res.data;
  }

  // --- General Files Upload/Download ---
  // Mirrors case-room.service.ts's uploadFile (generic files endpoint, not
  // caseroom-scoped) and clinical-record.service.ts's downloadFile (blob).

  Future<dynamic> uploadFile({
    String? filePath,
    Uint8List? bytes,
    required String fileName,
    String category = 'OTHER',
    String? patientId,
  }) async {
    MultipartFile multipartFile;
    if (bytes != null) {
      multipartFile = MultipartFile.fromBytes(bytes, filename: fileName);
    } else if (filePath != null) {
      multipartFile = await MultipartFile.fromFile(filePath, filename: fileName);
    } else {
      throw ArgumentError('Either bytes or filePath must be provided');
    }
    final formData = FormData.fromMap({
      'file': multipartFile,
      'category': category,
      if (patientId != null) 'patientId': patientId,
    });
    final res = await dio.post('/api/medconsult/files/', data: formData);
    return res.data;
  }

  Future<List<int>> downloadFile(String fileId) async {
    final res = await dio.get<List<int>>(
      '/api/medconsult/files/$fileId/download',
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? [];
  }
}

final caseRoomServiceProvider = Provider<CaseRoomService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return CaseRoomService(dio: dio);
});

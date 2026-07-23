import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class ConsultationService {
  final Dio dio;

  ConsultationService({required this.dio});

  Future<List<dynamic>> getMyDoctorConsultations({int page = 0, int size = 10}) async {
    final res = await dio.get(
      '/api/medconsult/consultations/my/doctor',
      queryParameters: {'page': page, 'size': size},
    );
    return res.data ?? [];
  }

  Future<dynamic> getConsultationById(String id) async {
    final res = await dio.get('/api/medconsult/consultations/$id');
    return res.data;
  }

  Future<dynamic> updateStatus(String id, Map<String, dynamic> dto) async {
    final res = await dio.patch(
      '/api/medconsult/consultations/$id/status',
      data: dto,
    );
    return res.data;
  }

  Future<List<dynamic>> getMessagesForConsultation(String consultationId) async {
    final res = await dio.get('/api/medconsult/consultations/messages/consultation/$consultationId');
    return res.data ?? [];
  }

  Future<dynamic> sendMessage(Map<String, dynamic> dto) async {
    final res = await dio.post('/api/medconsult/consultations/messages/', data: dto);
    return res.data;
  }
}

final consultationServiceProvider = Provider<ConsultationService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return ConsultationService(dio: dio);
});

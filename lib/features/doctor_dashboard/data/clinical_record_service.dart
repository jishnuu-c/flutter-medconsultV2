import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class ClinicalRecordService {
  final Dio dio;

  ClinicalRecordService({required this.dio});

  Future<List<dynamic>> searchPrescriptions({String? patientId, String? doctorId}) async {
    final res = await dio.get('/api/medconsult/prescriptions/search', queryParameters: {
      if (patientId != null) 'patientId': patientId,
      if (doctorId != null) 'doctorId': doctorId,
    });
    if (res.data is Map && res.data['content'] != null) {
      return res.data['content'];
    }
    return res.data is List ? res.data : [];
  }

  Future<List<dynamic>> searchVitals({String? patientId}) async {
    final res = await dio.get('/api/medconsult/vitals/search', queryParameters: {
      if (patientId != null) 'patientId': patientId,
    });
    if (res.data is Map && res.data['content'] != null) {
      return res.data['content'];
    }
    return res.data is List ? res.data : [];
  }
}

final clinicalRecordServiceProvider = Provider<ClinicalRecordService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return ClinicalRecordService(dio: dio);
});

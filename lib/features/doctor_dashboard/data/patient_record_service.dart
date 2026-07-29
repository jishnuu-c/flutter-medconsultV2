import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

/// Doctor-facing patient record lookups by patientId.
/// Mirrors the "Doctor Views" section of patient.service.ts.
class PatientRecordService {
  final Dio dio;

  PatientRecordService({required this.dio});

  List<dynamic> _extractList(dynamic data) {
    if (data is Map && data['content'] != null) return data['content'];
    return data is List ? data : [];
  }

  Future<Map<String, dynamic>?> getPatientHealthProfile(
      String patientId) async {
    final res = await dio.get('/api/patients/$patientId/health-profile');
    return res.data is Map ? Map<String, dynamic>.from(res.data) : null;
  }

  Future<List<dynamic>> getPatientAllergies(String patientId) async {
    final res = await dio.get('/api/patients/$patientId/allergies');
    return _extractList(res.data);
  }

  Future<List<dynamic>> getPatientChronicConditions(String patientId) async {
    final res = await dio.get('/api/patients/$patientId/chronic-conditions');
    return _extractList(res.data);
  }
}

final patientRecordServiceProvider = Provider<PatientRecordService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return PatientRecordService(dio: dio);
});

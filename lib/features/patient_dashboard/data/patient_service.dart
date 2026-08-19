import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class PatientService {
  final Dio dio;

  PatientService({required this.dio});

  // Profile
  Future<dynamic> getMyProfile() async {
    try {
      final res = await dio.get('/api/patients/me');
      if (res.data != null && res.data is Map) {
        return res.data;
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<dynamic> createProfile(Map<String, dynamic> dto) async {
    final res = await dio.post('/api/patients/add-profile', data: dto);
    return res.data;
  }

  Future<dynamic> updateProfile(Map<String, dynamic> dto) async {
    final res = await dio.patch('/api/patients/me/update', data: dto);
    return res.data;
  }

  // Health Profile
  Future<dynamic> getMyHealthProfile() async {
    final res = await dio.get('/api/patients/me/health-profile');
    return res.data;
  }

  Future<dynamic> addHealthProfile(Map<String, dynamic> dto) async {
    final res =
        await dio.post('/api/patients/me/health-profile/add', data: dto);
    return res.data;
  }

  Future<dynamic> updateHealthProfile(Map<String, dynamic> dto) async {
    final res =
        await dio.put('/api/patients/me/health-profile/update', data: dto);
    return res.data;
  }

  // Allergies
  Future<List<dynamic>> getMyAllergies() async {
    final res = await dio.get('/api/patients/me/allergies');
    return res.data is List ? res.data : [];
  }

  Future<dynamic> addAllergy(Map<String, dynamic> dto) async {
    final res = await dio.post('/api/patients/me/allergies/add', data: dto);
    return res.data;
  }

  Future<void> deleteAllergy(String allergyId) async {
    await dio.delete('/api/patients/me/allergies/$allergyId');
  }

  // Doctor-facing: view another patient's EMR by patientId
  Future<dynamic> getPatientHealthProfile(String patientId) async {
    final res = await dio.get('/api/patients/$patientId/health-profile');
    return res.data;
  }

  Future<List<dynamic>> getPatientAllergies(String patientId) async {
    final res = await dio.get('/api/patients/$patientId/allergies');
    return res.data is List ? res.data : [];
  }

  Future<List<dynamic>> getPatientChronicConditions(String patientId) async {
    final res = await dio.get('/api/patients/$patientId/chronic-conditions');
    return res.data is List ? res.data : [];
  }

  // Chronic Conditions
  Future<List<dynamic>> getMyChronicConditions() async {
    final res = await dio.get('/api/patients/me/chronic-conditions');
    return res.data is List ? res.data : [];
  }

  Future<dynamic> addChronicCondition(Map<String, dynamic> dto) async {
    final res =
        await dio.post('/api/patients/me/add-chronic-condition', data: dto);
    return res.data;
  }

  Future<void> deleteChronicCondition(String conditionId) async {
    await dio.delete('/api/patients/me/chronic-condition/$conditionId');
  }
}

final patientServiceProvider = Provider<PatientService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return PatientService(dio: dio);
});

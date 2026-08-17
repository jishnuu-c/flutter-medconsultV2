import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import 'clinic_models.dart';

class ClinicService {
  final Dio dio;

  ClinicService({required this.dio});

  Future<List<ClinicModel>> getAllClinics() async {
    try {
      final res = await dio.get('/api/medconsult/clinics/all');
      dynamic data = res.data;
      if (data is Map) {
        if (data.containsKey('content') && data['content'] is List) {
          data = data['content'];
        } else if (data.containsKey('data') && data['data'] is List) {
          data = data['data'];
        } else if (data.containsKey('clinics') && data['clinics'] is List) {
          data = data['clinics'];
        } else if (data.containsKey('items') && data['items'] is List) {
          data = data['items'];
        }
      }
      if (data is List) {
        final list = <ClinicModel>[];
        for (final item in data) {
          if (item is Map) {
            try {
              list.add(ClinicModel.fromJson(Map<String, dynamic>.from(item)));
            } catch (e) {
              // Ignore single item parsing failure and continue
            }
          }
        }
        return list;
      }
      return [];
    } catch (e) {
      rethrow;
    }
  }

  Future<ClinicDetailResponse> getClinicDetail(String id) async {
    final res = await dio.get('/api/medconsult/clinics/$id/detail');
    final data = res.data is Map ? Map<String, dynamic>.from(res.data) : <String, dynamic>{};
    return ClinicDetailResponse.fromJson(data);
  }

  // NOTE: the backend for these two endpoints expects multipart/form-data —
  // the DTO as a JSON blob under the field name "body", plus an optional
  // "logo" file part. This mirrors clinic.service.ts's createClinic/
  // updateClinic (see FormData + Blob usage there). Sending plain JSON here
  // used to silently fail against the real backend.
  Future<ClinicModel> createClinic(Map<String, dynamic> data,
      {String? logoFilePath}) async {
    final formData = FormData.fromMap({
      'body': MultipartFile.fromString(
        jsonEncode(data),
        contentType: MediaType('application', 'json'),
      ),
      if (logoFilePath != null)
        'logo': await MultipartFile.fromFile(logoFilePath),
    });
    final res = await dio.post('/api/medconsult/clinics/add', data: formData);
    return ClinicModel.fromJson(res.data);
  }

  Future<ClinicModel> updateClinic(String id, Map<String, dynamic> data,
      {String? logoFilePath}) async {
    final formData = FormData.fromMap({
      'body': MultipartFile.fromString(
        jsonEncode(data),
        contentType: MediaType('application', 'json'),
      ),
      if (logoFilePath != null)
        'logo': await MultipartFile.fromFile(logoFilePath),
    });
    final res = await dio.patch('/api/medconsult/clinics/$id', data: formData);
    return ClinicModel.fromJson(res.data);
  }

  Future<void> deleteClinic(String id) async {
    await dio.delete('/api/medconsult/clinics/$id');
  }

  // ── Branches ────────────────────────────────────────────────────────
  Future<List<ClinicBranchModel>> getClinicBranches(String clinicId) async {
    final res = await dio.get('/api/medconsult/clinics/$clinicId/branches');
    final List list = res.data ?? [];
    return list.map((e) => ClinicBranchModel.fromJson(e)).toList();
  }

  Future<ClinicBranchModel> createClinicBranch(
      String clinicId, Map<String, dynamic> data) async {
    final res = await dio.post('/api/medconsult/clinics/$clinicId/branches',
        data: data);
    return ClinicBranchModel.fromJson(res.data);
  }

  Future<ClinicBranchModel> updateClinicBranch(
      String branchId, Map<String, dynamic> data) async {
    final res = await dio.patch('/api/medconsult/clinics/branches/$branchId',
        data: data);
    return ClinicBranchModel.fromJson(res.data);
  }

  Future<void> deleteClinicBranch(String branchId) async {
    await dio.delete('/api/medconsult/clinics/branches/$branchId');
  }

  // ── Operating Hours ─────────────────────────────────────────────────
  Future<List<ClinicOperatingHourModel>> getBranchHours(String branchId) async {
    final res =
        await dio.get('/api/medconsult/clinics/branches/$branchId/hours');
    final List list = res.data ?? [];
    return list.map((e) => ClinicOperatingHourModel.fromJson(e)).toList();
  }

  Future<List<ClinicOperatingHourModel>> updateBranchHours(
      String branchId, List<Map<String, dynamic>> dtos) async {
    final res = await dio
        .put('/api/medconsult/clinics/branches/$branchId/hours', data: dtos);
    final List list = res.data ?? [];
    return list.map((e) => ClinicOperatingHourModel.fromJson(e)).toList();
  }

  // ── Specialties ─────────────────────────────────────────────────────
  Future<List<ClinicSpecialtyModel>> getClinicSpecialties(
      String clinicId) async {
    final res = await dio.get('/api/medconsult/clinics/$clinicId/specialties');
    final List list = res.data ?? [];
    return list.map((e) => ClinicSpecialtyModel.fromJson(e)).toList();
  }

  Future<ClinicSpecialtyModel> addClinicSpecialty(
      String clinicId, String specialtyId) async {
    final res = await dio
        .post('/api/medconsult/clinics/$clinicId/specialties/$specialtyId');
    return ClinicSpecialtyModel.fromJson(res.data);
  }

  Future<void> deleteClinicSpecialty(
      String clinicId, String specialtyId) async {
    await dio
        .delete('/api/medconsult/clinics/$clinicId/specialties/$specialtyId');
  }

  // ── Insurances ──────────────────────────────────────────────────────
  Future<List<ClinicInsuranceModel>> getClinicInsurances(
      String clinicId) async {
    final res = await dio.get('/api/medconsult/clinics/$clinicId/insurance');
    final List list = res.data ?? [];
    return list.map((e) => ClinicInsuranceModel.fromJson(e)).toList();
  }

  Future<ClinicInsuranceModel> addClinicInsurance(
      String clinicId, String providerId, Map<String, dynamic> data) async {
    final res = await dio.post(
        '/api/medconsult/clinics/$clinicId/insurance/$providerId',
        data: data);
    return ClinicInsuranceModel.fromJson(res.data);
  }

  Future<void> deleteClinicInsurance(String clinicId, String providerId) async {
    await dio.delete('/api/medconsult/clinics/$clinicId/insurance/$providerId');
  }

  // ── Languages ───────────────────────────────────────────────────────
  Future<List<ClinicLanguageModel>> getClinicLanguages(String clinicId) async {
    final res = await dio.get('/api/medconsult/clinics/$clinicId/languages');
    final List list = res.data ?? [];
    return list.map((e) => ClinicLanguageModel.fromJson(e)).toList();
  }

  Future<ClinicLanguageModel> addClinicLanguage(
      String clinicId, String languageId) async {
    final res = await dio
        .post('/api/medconsult/clinics/$clinicId/languages/$languageId');
    return ClinicLanguageModel.fromJson(res.data);
  }

  Future<void> deleteClinicLanguage(String clinicId, String languageId) async {
    await dio.delete('/api/medconsult/clinics/$clinicId/languages/$languageId');
  }
}

final clinicServiceProvider = Provider<ClinicService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return ClinicService(dio: dio);
});

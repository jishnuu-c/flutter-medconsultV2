import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class ClinicalRecordService {
  final Dio dio;

  ClinicalRecordService({required this.dio});

  List<dynamic> _extractList(dynamic data) {
    if (data is Map && data['content'] != null) return data['content'];
    return data is List ? data : [];
  }

  Future<List<dynamic>> searchPrescriptions({
    String? patientId,
    String? doctorId,
    String? status,
    int page = 0,
    int size = 20,
    String sortBy = 'issuedDate',
    String sortDir = 'desc',
  }) async {
    final res =
        await dio.get('/api/medconsult/prescriptions/search', queryParameters: {
      if (patientId != null) 'patientId': patientId,
      if (doctorId != null) 'doctorId': doctorId,
      if (status != null) 'status': status,
      'page': page,
      'size': size,
      'sortBy': sortBy,
      'sortDir': sortDir,
    });
    return _extractList(res.data);
  }

  Future<dynamic> createPrescription(Map<String, dynamic> dto) async {
    final res = await dio.post('/api/medconsult/prescriptions/add', data: dto);
    return res.data;
  }

  Future<List<dynamic>> getPrescriptionItems(String prescriptionId) async {
    final res =
        await dio.get('/api/medconsult/prescriptions/$prescriptionId/items');
    return _extractList(res.data);
  }

  Future<dynamic> addPrescriptionItem(
      String prescriptionId, Map<String, dynamic> dto) async {
    final res = await dio
        .post('/api/medconsult/prescriptions/$prescriptionId/items', data: dto);
    return res.data;
  }

  Future<List<dynamic>> searchVitals({
    String? patientId,
    String? source,
    int page = 0,
    int size = 20,
    String sortBy = 'recordedAt',
    String sortDir = 'desc',
  }) async {
    final res =
        await dio.get('/api/medconsult/vitals/search', queryParameters: {
      if (patientId != null) 'patientId': patientId,
      if (source != null) 'source': source,
      'page': page,
      'size': size,
      'sortBy': sortBy,
      'sortDir': sortDir,
    });
    return _extractList(res.data);
  }

  Future<dynamic> createVital(Map<String, dynamic> dto) async {
    final res = await dio.post('/api/medconsult/vitals/add', data: dto);
    return res.data;
  }

  Future<List<dynamic>> searchLabResults({
    String? patientId,
    String? orderedById,
    String? status,
    String? overallFlag,
    int page = 0,
    int size = 20,
    String sortBy = 'reportDate',
    String sortDir = 'desc',
  }) async {
    final res =
        await dio.get('/api/medconsult/lab-results/search', queryParameters: {
      if (patientId != null) 'patientId': patientId,
      if (orderedById != null) 'orderedById': orderedById,
      if (status != null) 'status': status,
      if (overallFlag != null) 'overallFlag': overallFlag,
      'page': page,
      'size': size,
      'sortBy': sortBy,
      'sortDir': sortDir,
    });
    return _extractList(res.data);
  }

  // Backend expects multipart/form-data here: the DTO as a JSON blob under
  // field "dto", plus an optional "file" part. Mirrors clinical-record.service.ts's
  // createLabResult (FormData + Blob). Sending plain JSON silently fails.
  Future<dynamic> createLabResult(Map<String, dynamic> dto,
      {String? filePath}) async {
    final formData = FormData.fromMap({
      'dto': MultipartFile.fromString(
        jsonEncode(dto),
        contentType: MediaType('application', 'json'),
      ),
      if (filePath != null) 'file': await MultipartFile.fromFile(filePath),
    });
    final res =
        await dio.post('/api/medconsult/lab-results/add', data: formData);
    return res.data;
  }
}

final clinicalRecordServiceProvider = Provider<ClinicalRecordService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return ClinicalRecordService(dio: dio);
});

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import 'doctor_models.dart';

class DoctorService {
  final Dio dio;

  DoctorService({required this.dio});

  Future<List<DoctorModel>> getAllDoctors() async {
    final res = await dio.get('/api/medconsult/doctors/all');
    final List list = res.data ?? [];
    return list.map((e) => DoctorModel.fromJson(e)).toList();
  }

  Future<DoctorDetailResponse> getDoctorProfile(String id) async {
    final res = await dio.get('/api/medconsult/doctors/profile/$id');
    return DoctorDetailResponse.fromJson(res.data);
  }

  Future<DoctorModel> addDoctor(Map<String, dynamic> dto) async {
    final res = await dio.post('/api/medconsult/doctors/add', data: dto);
    return DoctorModel.fromJson(res.data);
  }

  Future<DoctorModel> updateDoctor(String id, Map<String, dynamic> dto) async {
    final res =
        await dio.patch('/api/medconsult/doctors/$id/update', data: dto);
    return DoctorModel.fromJson(res.data);
  }

  Future<void> deleteDoctor(String id) async {
    await dio.delete('/api/medconsult/doctors/$id/delete');
  }

  // ── Schedules ───────────────────────────────────────────────────────
  Future<List<DoctorScheduleModel>> getDcSchedules(String dcId) async {
    final res =
        await dio.get('/api/medconsult/doctors/clinics/$dcId/schedules');
    final List list = res.data ?? [];
    return list.map((e) => DoctorScheduleModel.fromJson(e)).toList();
  }

  Future<DoctorScheduleModel> addSchedule(Map<String, dynamic> dto) async {
    final res =
        await dio.post('/api/medconsult/doctors/schedules/add', data: dto);
    return DoctorScheduleModel.fromJson(res.data);
  }

  Future<DoctorScheduleModel> updateSchedule(
      String id, Map<String, dynamic> dto) async {
    final res = await dio.patch('/api/medconsult/doctors/schedules/$id/update',
        data: dto);
    return DoctorScheduleModel.fromJson(res.data);
  }

  Future<void> removeSchedule(String id) async {
    await dio.delete('/api/medconsult/doctors/schedules/$id/remove');
  }

  // ── Leave ───────────────────────────────────────────────────────────
  Future<List<DoctorLeaveModel>> getDcLeave(String dcId) async {
    final res = await dio.get('/api/medconsult/doctors/clinics/$dcId/leave');
    final List list = res.data ?? [];
    return list.map((e) => DoctorLeaveModel.fromJson(e)).toList();
  }

  Future<DoctorLeaveModel> addLeave(Map<String, dynamic> dto) async {
    final res = await dio.post('/api/medconsult/doctors/leave/add', data: dto);
    return DoctorLeaveModel.fromJson(res.data);
  }

  Future<DoctorLeaveModel> updateLeave(
      String id, Map<String, dynamic> dto) async {
    final res =
        await dio.patch('/api/medconsult/doctors/leave/$id/update', data: dto);
    return DoctorLeaveModel.fromJson(res.data);
  }

  Future<void> removeLeave(String id) async {
    await dio.delete('/api/medconsult/doctors/leave/$id/remove');
  }

  // ── Slots ───────────────────────────────────────────────────────────
  Future<List<dynamic>> getAvailableSlots(String dcId, {String? date}) async {
    final res = await dio.get(
      '/api/medconsult/doctors/clinics/$dcId/slots',
      queryParameters: {if (date != null) 'date': date},
    );
    return res.data ?? [];
  }

  Future<dynamic> addSlot(Map<String, dynamic> dto) async {
    final res = await dio.post('/api/medconsult/doctors/slots/add', data: dto);
    return res.data;
  }

  Future<dynamic> updateSlot(String id, Map<String, dynamic> dto) async {
    final res =
        await dio.patch('/api/medconsult/doctors/slots/$id/update', data: dto);
    return res.data;
  }

  Future<void> removeSlot(String id) async {
    await dio.delete('/api/medconsult/doctors/slots/$id/remove');
  }

  // ── Doctor Clinics Placements ───────────────────────────────────────
  Future<List<DoctorClinicModel>> getDoctorClinics(String doctorId) async {
    final res = await dio.get('/api/medconsult/doctors/$doctorId/clinics');
    final List list = res.data ?? [];
    return list.map((e) => DoctorClinicModel.fromJson(e)).toList();
  }

  Future<DoctorClinicModel> addDoctorClinic(Map<String, dynamic> dto) async {
    final res =
        await dio.post('/api/medconsult/doctors/clinics/add', data: dto);
    return DoctorClinicModel.fromJson(res.data);
  }

  Future<DoctorClinicModel> updateDoctorClinic(
      String dcId, Map<String, dynamic> dto) async {
    final res = await dio.patch('/api/medconsult/doctors/clinics/$dcId/update',
        data: dto);
    return DoctorClinicModel.fromJson(res.data);
  }

  Future<void> removeDoctorClinic(String dcId) async {
    await dio.delete('/api/medconsult/doctors/clinics/$dcId/remove');
  }

  // ── Specialties ─────────────────────────────────────────────────────
  Future<List<DoctorSpecialtyModel>> getDoctorSpecialties(
      String doctorId) async {
    final res = await dio.get('/api/medconsult/doctors/$doctorId/specialties');
    final List list = res.data ?? [];
    return list.map((e) => DoctorSpecialtyModel.fromJson(e)).toList();
  }

  Future<DoctorSpecialtyModel> addSpecialty(Map<String, dynamic> dto) async {
    final res =
        await dio.post('/api/medconsult/doctors/specialties/add', data: dto);
    return DoctorSpecialtyModel.fromJson(res.data);
  }

  Future<DoctorSpecialtyModel> updateSpecialty(
      String id, Map<String, dynamic> dto) async {
    final res = await dio
        .patch('/api/medconsult/doctors/specialties/$id/update', data: dto);
    return DoctorSpecialtyModel.fromJson(res.data);
  }

  Future<void> removeSpecialty(String id) async {
    await dio.delete('/api/medconsult/doctors/specialties/$id/remove');
  }

  // ── Languages ───────────────────────────────────────────────────────
  Future<List<DoctorLanguageModel>> getDoctorLanguages(String doctorId) async {
    final res = await dio.get('/api/medconsult/doctors/$doctorId/languages');
    final List list = res.data ?? [];
    return list.map((e) => DoctorLanguageModel.fromJson(e)).toList();
  }

  Future<DoctorLanguageModel> addLanguage(Map<String, dynamic> dto) async {
    final res =
        await dio.post('/api/medconsult/doctors/languages/add', data: dto);
    return DoctorLanguageModel.fromJson(res.data);
  }

  Future<void> removeLanguage(String id) async {
    await dio.delete('/api/medconsult/doctors/languages/$id/remove');
  }

  // ── Qualifications ──────────────────────────────────────────────────
  Future<List<DoctorQualificationModel>> getDoctorQualifications(
      String doctorId) async {
    final res =
        await dio.get('/api/medconsult/doctors/$doctorId/qualifications');
    final List list = res.data ?? [];
    return list.map((e) => DoctorQualificationModel.fromJson(e)).toList();
  }

  Future<DoctorQualificationModel> addQualification(
      Map<String, dynamic> dto) async {
    final res =
        await dio.post('/api/medconsult/doctors/qualifications/add', data: dto);
    return DoctorQualificationModel.fromJson(res.data);
  }

  Future<void> removeQualification(String id) async {
    await dio.delete('/api/medconsult/doctors/qualifications/$id/remove');
  }
}

final doctorServiceProvider = Provider<DoctorService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return DoctorService(dio: dio);
});

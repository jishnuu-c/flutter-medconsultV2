import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class AppointmentService {
  final Dio dio;

  AppointmentService({required this.dio});

  Future<List<dynamic>> getDoctorUpcomingAppointments() async {
    final res = await dio.get('/api/medconsult/appointments/doctor/upcoming');
    // Defensive: unwrap if backend ever paginates this too.
    if (res.data is Map && res.data['content'] != null)
      return res.data['content'];
    return res.data ?? [];
  }

  Future<List<dynamic>> getMyUpcomingAppointments() async {
    final res = await dio.get('/api/medconsult/appointments/my/upcoming');
    return res.data ?? [];
  }

  /// Self-scoped (token-derived) appointments for the logged-in patient.
  /// Mirrors Angular's AppointmentService.getMyAppointments — NOT the same
  /// as getAppointmentsByPatient below, which hits a doctor/admin-facing
  /// endpoint that a plain PATIENT token gets 403'd on.
  Future<dynamic> getMyAppointments({int page = 0, int size = 10}) async {
    final res = await dio.get(
      '/api/medconsult/appointments/my',
      queryParameters: {'page': page, 'size': size},
    );
    return res.data;
  }

  Future<dynamic> bookAppointment(Map<String, dynamic> dto) async {
    final res = await dio.post('/api/medconsult/appointments/book', data: dto);
    return res.data;
  }

  Future<dynamic> getAppointmentById(String appointmentId) async {
    final res = await dio.get('/api/medconsult/appointments/$appointmentId');
    return res.data;
  }

  Future<dynamic> searchAppointments(Map<String, dynamic> searchRequest) async {
    final res = await dio.post('/api/medconsult/appointments/search',
        data: searchRequest);
    return res.data;
  }

  Future<List<dynamic>> getAppointmentsByPatient(String patientId,
      {int page = 0, int size = 10}) async {
    final res = await dio.get(
      '/api/medconsult/appointments/patient/$patientId',
      queryParameters: {'page': page, 'size': size},
    );
    // Paginated endpoint — backend returns a Spring Page object
    // ({content: [...], totalElements: ...}), not a bare list.
    if (res.data is Map && res.data['content'] != null)
      return res.data['content'];
    return res.data ?? [];
  }

  Future<List<dynamic>> getAppointmentsByDoctor(String doctorId,
      {int page = 0, int size = 10}) async {
    final res = await dio.get(
      '/api/medconsult/appointments/doctor/$doctorId',
      queryParameters: {'page': page, 'size': size},
    );
    // Paginated endpoint — backend returns a Spring Page object
    // ({content: [...], totalElements: ...}), not a bare list.
    if (res.data is Map && res.data['content'] != null)
      return res.data['content'];
    return res.data ?? [];
  }

  Future<dynamic> updateStatus(
      String appointmentId, Map<String, dynamic> statusRequest) async {
    final res = await dio.patch(
      '/api/medconsult/appointments/$appointmentId/status',
      data: statusRequest,
    );
    return res.data;
  }

  Future<dynamic> cancelAppointment(
      String appointmentId, Map<String, dynamic> cancelRequest) async {
    final res = await dio.patch(
      '/api/medconsult/appointments/$appointmentId/cancel',
      data: cancelRequest,
    );
    return res.data;
  }
}

final appointmentServiceProvider = Provider<AppointmentService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return AppointmentService(dio: dio);
});
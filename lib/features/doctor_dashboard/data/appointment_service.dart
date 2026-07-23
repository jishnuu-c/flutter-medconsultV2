import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class AppointmentService {
  final Dio dio;

  AppointmentService({required this.dio});

  Future<List<dynamic>> getDoctorUpcomingAppointments() async {
    final res = await dio.get('/api/medconsult/appointments/doctor/upcoming');
    return res.data ?? [];
  }

  Future<List<dynamic>> getAppointmentsByDoctor(String doctorId, {int page = 0, int size = 10}) async {
    final res = await dio.get(
      '/api/medconsult/appointments/doctor/$doctorId',
      queryParameters: {'page': page, 'size': size},
    );
    return res.data ?? [];
  }

  Future<dynamic> updateStatus(String appointmentId, Map<String, dynamic> statusRequest) async {
    final res = await dio.patch(
      '/api/medconsult/appointments/$appointmentId/status',
      data: statusRequest,
    );
    return res.data;
  }

  Future<dynamic> cancelAppointment(String appointmentId, Map<String, dynamic> cancelRequest) async {
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

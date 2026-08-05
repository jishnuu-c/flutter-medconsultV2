import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../doctor_dashboard/data/appointment_service.dart';

/// Mirrors Angular's doctor-dashboard/appointments-history.
class DoctorAppointmentsHistoryScreen extends ConsumerStatefulWidget {
  const DoctorAppointmentsHistoryScreen({super.key});

  @override
  ConsumerState<DoctorAppointmentsHistoryScreen> createState() =>
      _DoctorAppointmentsHistoryScreenState();
}

class _DoctorAppointmentsHistoryScreenState
    extends ConsumerState<DoctorAppointmentsHistoryScreen> {
  bool _isLoading = false;
  String? _doctorId;
  List<dynamic> _appointments = [];

  @override
  void initState() {
    super.initState();
    _resolveDoctorIdAndLoad();
  }

  Future<void> _resolveDoctorIdAndLoad() async {
    setState(() => _isLoading = true);
    try {
      final userId = ref.read(authNotifierProvider).currentUser?.id;
      if (userId == null) throw Exception('No logged-in user found.');
      final doctors = await ref.read(doctorServiceProvider).getAllDoctors();
      final match = doctors.where((d) => d.userId == userId);
      if (match.isEmpty)
        throw Exception('Doctor profile not found for this user.');
      _doctorId = match.first.doctorId;
      final res = await ref
          .read(appointmentServiceProvider)
          .getAppointmentsByDoctor(_doctorId!, page: 0, size: 50);
      if (mounted) setState(() => _appointments = res);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load appointments: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return AppTheme.successGreen;
      case 'CONFIRMED':
        return AppTheme.infoBlue;
      case 'SCHEDULED':
        return AppTheme.warningAmber;
      case 'CANCELLED':
      case 'NO_SHOW':
        return AppTheme.dangerRed;
      default:
        return AppTheme.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 700;
    return RefreshIndicator(
      onRefresh: _resolveDoctorIdAndLoad,
      child: ListView(
        padding: EdgeInsets.all(isNarrow ? 16 : 24),
        children: [
          Text('Appointments History',
              style: TextStyle(
                  fontSize: isNarrow ? 19 : 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain)),
          const SizedBox(height: 4),
          const Text('All appointments booked with you, past and upcoming.',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
          const SizedBox(height: 16),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_appointments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('No appointments found.',
                    style: TextStyle(color: AppTheme.textMuted)),
              ),
            )
          else
            ..._appointments.map((a) {
              final status = (a['status'] ?? '').toString();
              final sessionType = (a['sessionType'] ?? '').toString();
              final patientName = (a['patientName'] ?? 'Patient').toString();
              final scheduledDate = (a['scheduledDate'] ?? '').toString();
              final startTime = (a['startTime'] ?? '').toString();
              final clinicName = (a['clinicNameEn'] ?? '').toString();
              final initials = patientName.isNotEmpty
                  ? patientName
                      .trim()
                      .split(' ')
                      .take(2)
                      .map((s) => s.isNotEmpty ? s[0] : '')
                      .join()
                      .toUpperCase()
                  : 'P';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppTheme.borderGray),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLightTeal,
                        borderRadius: BorderRadius.circular(19),
                      ),
                      alignment: Alignment.center,
                      child: Text(initials,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryTeal)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(patientName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _statusColor(status)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(status,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: _statusColor(status))),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '🗓️ $scheduledDate  ⏰ ${startTime.length >= 5 ? startTime.substring(0, 5) : startTime}',
                            style: const TextStyle(
                                fontSize: 12.5, color: AppTheme.textMuted),
                          ),
                          if (clinicName.isNotEmpty || sessionType.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${sessionType == 'IN_CLINIC' ? '🏢 In-Clinic' : '💻 Video Call'}'
                                '${clinicName.isNotEmpty ? ' · $clinicName' : ''}',
                                style: const TextStyle(
                                    fontSize: 12.5, color: AppTheme.textMuted),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../doctor_dashboard/data/appointment_service.dart';
import '../data/patient_service.dart';

/// Mirrors Angular's patient-dashboard/appointments ("My Appointments").
class PatientAppointmentsScreen extends ConsumerStatefulWidget {
  const PatientAppointmentsScreen({super.key});

  @override
  ConsumerState<PatientAppointmentsScreen> createState() =>
      _PatientAppointmentsScreenState();
}

class _PatientAppointmentsScreenState
    extends ConsumerState<PatientAppointmentsScreen> {
  bool _isLoading = false;
  bool _needProfileInit = false;
  List<dynamic> _appointments = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _needProfileInit = false;
    });
    try {
      final profile = await ref.read(patientServiceProvider).getMyProfile();
      // profile only used to detect "needs profile init" (404 below);
      // /appointments/my is token-derived and needs no patientId.
      final res = await ref
          .read(appointmentServiceProvider)
          .getMyAppointments(page: 0, size: 50);
      final content = (res is Map ? res['content'] : null) ?? res ?? [];
      if (mounted) setState(() => _appointments = content);
    } catch (e) {
      final status = e is DioException ? e.response?.statusCode : null;
      if (status == 404) {
        setState(() => _needProfileInit = true);
      } else if (mounted) {
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

    if (_needProfileInit) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Complete your patient profile first.',
                  style: TextStyle(color: AppTheme.textMuted)),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white),
                onPressed: () => context.go('/patient/profile'),
                child: const Text('Go to Profile'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(isNarrow ? 16 : 24),
        children: [
          Text('My Appointments',
              style: TextStyle(
                  fontSize: isNarrow ? 19 : 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain)),
          const SizedBox(height: 4),
          const Text('Track upcoming and past visits with your doctors.',
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
              final doctorName = (a['doctorName'] ?? 'Doctor').toString();
              final scheduledDate = (a['scheduledDate'] ?? '').toString();
              final startTime = (a['startTime'] ?? '').toString();
              final clinicName = (a['clinicNameEn'] ?? '').toString();
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppTheme.borderGray),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              '${doctorName.startsWith('Dr') ? '' : 'Dr. '}$doctorName',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _statusColor(status).withValues(alpha: 0.12),
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
              );
            }),
        ],
      ),
    );
  }
}
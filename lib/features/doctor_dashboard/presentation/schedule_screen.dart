import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/appointment_service.dart';

class DoctorScheduleScreen extends ConsumerStatefulWidget {
  const DoctorScheduleScreen({super.key});

  @override
  ConsumerState<DoctorScheduleScreen> createState() =>
      _DoctorScheduleScreenState();
}

class _DoctorScheduleScreenState extends ConsumerState<DoctorScheduleScreen> {
  bool _isLoading = false;
  List<dynamic> _appointments = [];

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref
          .read(appointmentServiceProvider)
          .getDoctorUpcomingAppointments();
      setState(() => _appointments = res);
    } catch (e) {
      setState(() => _appointments = []);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load schedule: ${_errorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _errorMessage(Object e) {
    if (e is DioException) {
      return e.response?.statusMessage ?? e.message ?? 'Network error';
    }
    return e.toString();
  }

  Future<void> _changeStatus(String appointmentId, String newStatus) async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(appointmentServiceProvider)
          .updateStatus(appointmentId, {'status': newStatus});
      await _loadSchedule();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to update status: ${_errorMessage(e)}')),
        );
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Doctor Consultation Schedule',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMain),
                ),
                const SizedBox(height: 4),
                const Text(
                  "View and manage today's incoming patient bookings.",
                  style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const Key('refresh_schedule_btn'),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh Schedule'),
                    onPressed: _loadSchedule,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Card(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _appointments.isEmpty
                        ? const Center(
                            child: Text(
                                'No consultations registered in your schedule today.'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _appointments.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final apt = _appointments[index];
                              final status = apt['status'] ?? 'SCHEDULED';
                              final startTime =
                                  (apt['startTime'] as String?) ?? '';
                              final timeLabel = startTime.length >= 5
                                  ? startTime.substring(0, 5)
                                  : startTime;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.primaryLightTeal,
                                  child: const Icon(Icons.calendar_today,
                                      color: AppTheme.primaryTeal, size: 20),
                                ),
                                title: Text(
                                  apt['patientName'] ?? 'Patient',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                    '${apt['scheduledDate'] ?? ''} • $timeLabel • ${apt['sessionType'] ?? ''}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Chip(
                                      label: Text(status),
                                      backgroundColor:
                                          AppTheme.primaryLightTeal,
                                    ),
                                    if (status == 'SCHEDULED')
                                      TextButton(
                                        onPressed: () => _changeStatus(
                                            apt['appointmentId'], 'CONFIRMED'),
                                        child: const Text('Confirm'),
                                      ),
                                    if (status == 'CONFIRMED')
                                      TextButton(
                                        onPressed: () => _changeStatus(
                                            apt['appointmentId'], 'COMPLETED'),
                                        child: const Text('Complete'),
                                      ),
                                    if (status == 'SCHEDULED' ||
                                        status == 'CONFIRMED')
                                      TextButton(
                                        onPressed: () => _changeStatus(
                                            apt['appointmentId'], 'NO_SHOW'),
                                        child: const Text('No Show',
                                            style: TextStyle(
                                                color: AppTheme.dangerRed)),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/appointment_service.dart';

class DoctorScheduleScreen extends ConsumerStatefulWidget {
  const DoctorScheduleScreen({super.key});

  @override
  ConsumerState<DoctorScheduleScreen> createState() => _DoctorScheduleScreenState();
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
      final res = await ref.read(appointmentServiceProvider).getDoctorUpcomingAppointments();
      setState(() => _appointments = res);
    } catch (_) {
      _populateMockAppointments();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateMockAppointments() {
    _appointments = [
      {
        'appointmentId': 'apt-1',
        'patientName': 'Sarah Ahmed',
        'timeSlot': '10:00 AM - 10:30 AM',
        'type': 'In-Clinic Consultation',
        'status': 'CONFIRMED',
        'reason': 'Follow-up on Blood Pressure Readings',
      },
      {
        'appointmentId': 'apt-2',
        'patientName': 'Mohammed Al-Harbi',
        'timeSlot': '11:15 AM - 11:45 AM',
        'type': 'Tele-Consultation (Virtual)',
        'status': 'CONFIRMED',
        'reason': 'Routine Health Checkup',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Consultation Schedule',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'View and manage your upcoming patient appointments for today and this week.',
                        style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  key: const Key('refresh_schedule_btn'),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh Schedule'),
                  onPressed: _loadSchedule,
                ),
              ],
            ),
            const SizedBox(height: 24),

            Expanded(
              child: Card(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _appointments.isEmpty
                        ? const Center(child: Text('No upcoming appointments found.'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _appointments.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final apt = _appointments[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.primaryLightTeal,
                                  child: const Icon(Icons.calendar_today, color: AppTheme.primaryTeal, size: 20),
                                ),
                                title: Text(
                                  apt['patientName'] ?? 'Patient',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text('${apt['timeSlot']} • ${apt['type']}\nReason: ${apt['reason']}'),
                                trailing: Chip(
                                  label: Text(apt['status'] ?? 'SCHEDULED'),
                                  backgroundColor: AppTheme.primaryLightTeal,
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../doctor_dashboard/data/appointment_service.dart';

class PatientHomeScreen extends ConsumerStatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  ConsumerState<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends ConsumerState<PatientHomeScreen> {
  bool _isLoading = false;
  List<dynamic> _upcomingAppointments = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref.read(appointmentServiceProvider).getDoctorUpcomingAppointments();
      setState(() => _upcomingAppointments = res);
    } catch (_) {
      _populateMockData();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateMockData() {
    _upcomingAppointments = [
      {
        'id': 'apt-101',
        'doctorName': 'Dr. Tariq Al-Mansoor',
        'specialty': 'Cardiology Specialist',
        'timeSlot': 'Today 3:00 PM',
        'type': 'In-Clinic Appointment',
        'status': 'CONFIRMED',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).currentUser;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.darkSidebar,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppTheme.primaryTeal,
                    child: Text(
                      user?.initials ?? 'P',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back, ${user?.fullName ?? "Patient"}!',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Manage your appointments, health metrics, and medical records in one portal.',
                          style: TextStyle(fontSize: 14, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Quick Action Grid
            const Text(
              'Quick Patient Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textMain),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildActionCard(
                  key: 'quick_book_appt',
                  icon: Icons.calendar_month,
                  title: 'Book Appointment',
                  subtitle: 'Schedule a visit with top specialists',
                  onTap: () => context.go('/patient/book-appointment'),
                ),
                _buildActionCard(
                  key: 'quick_emr_records',
                  icon: Icons.folder_special_outlined,
                  title: 'Medical EMR',
                  subtitle: 'View prescriptions & clinical records',
                  onTap: () => context.go('/patient/emr'),
                ),
                _buildActionCard(
                  key: 'quick_consultations',
                  icon: Icons.video_camera_front_outlined,
                  title: 'Tele-Consultations',
                  subtitle: 'Access virtual sessions & messaging',
                  onTap: () => context.go('/patient/consultations'),
                ),
                _buildActionCard(
                  key: 'quick_health_profile',
                  icon: Icons.monitor_heart_outlined,
                  title: 'Health Metrics',
                  subtitle: 'Log allergies & chronic conditions',
                  onTap: () => context.go('/patient/health-profile'),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Upcoming Appointments Section
            const Text(
              'Your Upcoming Appointments',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textMain),
            ),
            const SizedBox(height: 12),

            Card(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _upcomingAppointments.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('No upcoming appointments scheduled.')),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _upcomingAppointments.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final apt = _upcomingAppointments[index];
                            return ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: AppTheme.primaryLightTeal,
                                child: Icon(Icons.event, color: AppTheme.primaryTeal, size: 20),
                              ),
                              title: Text(apt['doctorName'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${apt['specialty']} • ${apt['timeSlot']}'),
                              trailing: Chip(
                                label: Text(apt['status']),
                                backgroundColor: AppTheme.primaryLightTeal,
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 180,
      child: Card(
        child: InkWell(
          key: Key(key),
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppTheme.primaryTeal, size: 28),
                const SizedBox(height: 12),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

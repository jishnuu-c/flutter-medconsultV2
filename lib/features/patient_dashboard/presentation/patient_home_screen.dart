import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../doctor_dashboard/data/appointment_service.dart';
import '../../doctor_dashboard/data/clinical_record_service.dart';
import '../data/patient_service.dart';

class PatientHomeScreen extends ConsumerStatefulWidget {
  const PatientHomeScreen({super.key});

  @override
  ConsumerState<PatientHomeScreen> createState() => _PatientHomeScreenState();
}

class _PatientHomeScreenState extends ConsumerState<PatientHomeScreen> {
  bool _isLoading = false;
  bool _needProfileInit = false;
  Map<String, dynamic>? _patientProfile;
  List<dynamic> _upcomingAppointments = [];
  Map<String, dynamic>? _latestVitals;
  dynamic _cancelTarget;
  final _cancelReasonController = TextEditingController();
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _loadPatientDashboard();
  }

  @override
  void dispose() {
    _cancelReasonController.dispose();
    super.dispose();
  }

  Future<void> _loadPatientDashboard() async {
    setState(() => _isLoading = true);
    try {
      final profile = await ref.read(patientServiceProvider).getMyProfile();
      if (profile != null && profile is Map && profile['patientId'] != null) {
        if (mounted) {
          setState(() {
            _patientProfile = Map<String, dynamic>.from(profile);
            _needProfileInit = false;
          });
        }
        await Future.wait([
          _loadUpcomingAppointments(),
          _loadLatestVitals(profile['patientId']),
        ]);
      } else {
        if (mounted) {
          setState(() {
            _patientProfile = null;
            _needProfileInit = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _needProfileInit = true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadUpcomingAppointments() async {
    try {
      final data = await ref.read(appointmentServiceProvider).getMyUpcomingAppointments();
      if (mounted) setState(() => _upcomingAppointments = data);
    } catch (_) {}
  }

  Future<void> _loadLatestVitals(String? patientId) async {
    if (patientId == null) return;
    try {
      final data = await ref.read(clinicalRecordServiceProvider).searchVitals(
            patientId: patientId,
            page: 0,
            size: 1,
            sortBy: 'recordedAt',
            sortDir: 'desc',
          );
      if (mounted && data.isNotEmpty) {
        setState(() => _latestVitals = Map<String, dynamic>.from(data[0]));
      }
    } catch (_) {}
  }

  void _openCancelModal(dynamic app) {
    _cancelReasonController.clear();
    setState(() => _cancelTarget = app);
  }

  Future<void> _submitCancel() async {
    if (_cancelTarget == null || _cancelReasonController.text.trim().isEmpty) return;
    setState(() => _isCancelling = true);
    try {
      await ref.read(appointmentServiceProvider).cancelAppointment(
        _cancelTarget['appointmentId'],
        {'cancelReason': _cancelReasonController.text.trim()},
      );
      if (mounted) {
        setState(() => _cancelTarget = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appointment cancelled successfully.')),
        );
        _loadPatientDashboard();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to cancel appointment.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).currentUser;

    if (_isLoading && _patientProfile == null && !_needProfileInit) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
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
                              'Hello, ${user?.fullName ?? "Welcome!"}',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            if (!_needProfileInit)
                              Text(
                                'National ID: ${_patientProfile?['nationalId'] ?? 'N/A'} | Nationality: ${_patientProfile?['nationality'] ?? 'N/A'}',
                                style: const TextStyle(fontSize: 13, color: Colors.white70),
                              )
                            else
                              const Text(
                                'You are logged in, but your patient medical profile has not been initialized yet.',
                                style: TextStyle(fontSize: 13, color: Colors.white70),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                if (_needProfileInit) ...[
                  Card(
                    color: const Color(0xFFFFFBEB),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Text('Profile Setup Required',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFB45309))),
                          const SizedBox(height: 8),
                          const Text(
                            'You haven\'t initialized your medical consultation profile yet. Please set up your birth date, blood type, and emergency contacts to unlock appointment booking.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF78350F)),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => context.go('/patient/profile'),
                            child: const Text('Initialize Profile Now'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  // Vitals summary
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Latest Recorded Vitals', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          if (_latestVitals != null) ...[
                            _vitalRow('BP (Syst/Diast)', '${_latestVitals!['bloodPressureSystolic']}/${_latestVitals!['bloodPressureDiastolic']} mmHg'),
                            _vitalRow('Heart Rate', '${_latestVitals!['heartRateBpm']} BPM'),
                            _vitalRow('Weight', '${_latestVitals!['weightKg']} kg'),
                          ] else
                            const Text('No vitals recorded yet.', style: TextStyle(color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Quick Actions
                  const Text('Quick Patient Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
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

                  Text('Upcoming Consultations (${_upcomingAppointments.length})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                  const SizedBox(height: 12),

                  Card(
                    child: _upcomingAppointments.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: Text('No upcoming appointments booked. Book a slot above.')),
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
                                title: Text(apt['doctorName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                    '${apt['scheduledDate'] ?? ''} • ${(apt['startTime'] ?? '').toString().length >= 5 ? apt['startTime'].toString().substring(0, 5) : apt['startTime']} • ${apt['appointmentType'] ?? ''}'),
                                trailing: Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Chip(label: Text(apt['status'] ?? ''), backgroundColor: AppTheme.primaryLightTeal),
                                    OutlinedButton(
                                      onPressed: () => _openCancelModal(apt),
                                      child: const Text('Cancel'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ],
            ),
          ),
          if (_cancelTarget != null)
            Container(
              color: Colors.black45,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Cancel Appointment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.dangerRed)),
                        const SizedBox(height: 12),
                        Text('Are you sure you want to cancel your consultation with ${_cancelTarget['doctorName']}?'),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _cancelReasonController,
                          maxLines: 3,
                          decoration: const InputDecoration(hintText: 'Reason for cancellation...'),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => setState(() => _cancelTarget = null),
                              child: const Text('Go Back'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _isCancelling ? null : _submitCancel,
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
                              child: _isCancelling
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('Confirm Cancellation'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _vitalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
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

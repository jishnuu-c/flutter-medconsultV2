import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_notification.dart';
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
          _loadLatestVitals(profile['patientId']?.toString()),
        ]);
      } else {
        if (mounted) {
          setState(() {
            _patientProfile = null;
            _needProfileInit = true;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _needProfileInit = true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadUpcomingAppointments() async {
    try {
      final data = await ref
          .read(appointmentServiceProvider)
          .getMyUpcomingAppointments();
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
    if (_cancelTarget == null || _cancelReasonController.text.trim().isEmpty) {
      return;
    }
    setState(() => _isCancelling = true);
    try {
      await ref.read(appointmentServiceProvider).cancelAppointment(
        _cancelTarget['appointmentId'],
        {'cancelReason': _cancelReasonController.text.trim()},
      );
      if (mounted) {
        setState(() => _cancelTarget = null);
        AppNotification.showSuccess(
          context,
          'Appointment cancelled successfully.',
        );
        _loadPatientDashboard();
      }
    } catch (_) {
      if (mounted) {
        AppNotification.showError(
          context,
          'Failed to cancel appointment.',
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).currentUser;
    final isMobile = MediaQuery.of(context).size.width <= 600;

    if (_isLoading && _patientProfile == null && !_needProfileInit) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundApp,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryTeal),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundApp,
      body: Stack(
        children: [
          RefreshIndicator(
            color: AppTheme.primaryTeal,
            onRefresh: _loadPatientDashboard,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 16 : 24,
                vertical: isMobile ? 16 : 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Hero Greeting Banner
                  _buildHeroGreeting(user, isMobile),
                  const SizedBox(height: 20),

                  // 2. Profile Setup Alert (if uninitialized)
                  if (_needProfileInit) ...[
                    _buildProfileInitAlert(isMobile),
                    const SizedBox(height: 20),
                  ],

                  // 3. Quick Action Cards (2x2 Grid)
                  _buildQuickActionsHeader(),
                  const SizedBox(height: 12),
                  _buildQuickActionsGrid(isMobile),
                  const SizedBox(height: 24),

                  // 4. Latest Vitals Snapshot
                  if (!_needProfileInit) ...[
                    _buildVitalsSection(isMobile),
                    const SizedBox(height: 24),
                  ],

                  // 5. Onboarding / Network Join Cards
                  _buildHealthcareNetworkOnboarding(isMobile),
                  const SizedBox(height: 24),

                  // 6. Upcoming Consultations
                  _buildUpcomingConsultationsSection(isMobile),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Cancel Appointment Modal Dialog
          if (_cancelTarget != null) _buildCancelAppointmentDialog(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 1. HERO GREETING BANNER
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHeroGreeting(dynamic user, bool isMobile) {
    final bloodType =
        _patientProfile?['bloodType']?.toString().replaceAll('_', ' ') ??
            'Unknown';
    final nationalId = _patientProfile?['nationalId']?.toString();
    final nationality = _patientProfile?['nationality']?.toString();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF134E4A), Color(0xFF0F2E2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF134E4A).withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: isMobile ? 50 : 58,
                height: isMobile ? 50 : 58,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withOpacity(0.3), width: 1.5),
                ),
                child: Center(
                  child: Text(
                    user?.initials ?? 'P',
                    style: TextStyle(
                      fontSize: isMobile ? 20 : 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, ${user?.fullName ?? "Welcome!"}',
                      style: TextStyle(
                        fontSize: isMobile ? 19 : 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _needProfileInit
                          ? 'Complete your profile to unlock all health features'
                          : 'Here is your personal health overview and care schedule',
                      style: TextStyle(
                        fontSize: isMobile ? 12 : 13,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => context.go('/patient/profile'),
                icon: const Icon(Icons.settings_outlined,
                    color: Colors.white70, size: 22),
                tooltip: 'Profile Settings',
              ),
            ],
          ),
          if (!_needProfileInit &&
              (nationalId != null || nationality != null)) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (nationalId != null && nationalId.isNotEmpty)
                  _buildHeaderPill(
                    icon: Icons.badge_outlined,
                    label: 'ID: $nationalId',
                  ),
                if (bloodType != 'Unknown')
                  _buildHeaderPill(
                    icon: Icons.water_drop_outlined,
                    label: 'Blood: $bloodType',
                  ),
                if (nationality != null && nationality.isNotEmpty)
                  _buildHeaderPill(
                    icon: Icons.public_outlined,
                    label: nationality,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. PROFILE INITIALIZATION REQUIRED ALERT
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildProfileInitAlert(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD97706).withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFD97706), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Patient Profile Required',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Please complete your medical details (Date of Birth, National ID, Emergency Contacts) to unlock booking appointments and EMR access.',
            style: TextStyle(
                fontSize: 12.5, color: Color(0xFF78350F), height: 1.4),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.go('/patient/profile'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Complete Patient Details Now',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. QUICK ACTIONS GRID (2x2 Mobile-First)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildQuickActionsHeader() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Quick Health Services',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textMain,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionsGrid(bool isMobile) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildActionTile(
              width: cardWidth,
              keyName: 'quick_book_appt',
              title: 'Book Appointment',
              subtitle: 'Specialists & Clinics',
              icon: Icons.calendar_month_rounded,
              iconColor: const Color(0xFF0F766E),
              bgColor: const Color(0xFFCCFBF1),
              onTap: () => context.go('/patient/book-appointment'),
            ),
            _buildActionTile(
              width: cardWidth,
              keyName: 'quick_emr_records',
              title: 'Medical EMR',
              subtitle: 'Records & Prescriptions',
              icon: Icons.folder_special_rounded,
              iconColor: const Color(0xFF4338CA),
              bgColor: const Color(0xFFE0E7FF),
              onTap: () => context.go('/patient/emr'),
            ),
            _buildActionTile(
              width: cardWidth,
              keyName: 'quick_consultations',
              title: 'Tele-Consultations',
              subtitle: 'Video & Messaging',
              icon: Icons.video_camera_front_rounded,
              iconColor: const Color(0xFF059669),
              bgColor: const Color(0xFFD1FAE5),
              onTap: () => context.go('/patient/consultations'),
            ),
            _buildActionTile(
              width: cardWidth,
              keyName: 'quick_health_profile',
              title: 'Health Metrics',
              subtitle: 'Allergies & Conditions',
              icon: Icons.monitor_heart_rounded,
              iconColor: const Color(0xFFBE123C),
              bgColor: const Color(0xFFFFE4E6),
              onTap: () => context.go('/patient/health-profile'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionTile({
    required double width,
    required String keyName,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: Material(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: Key(keyName),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderGray.withOpacity(0.7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: AppTheme.textMain,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 4. LATEST VITALS SUMMARY
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildVitalsSection(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.favorite_rounded,
                      color: AppTheme.primaryTeal, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Latest Health Vitals',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMain,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => context.go('/patient/emr'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('View All EMR',
                    style:
                        TextStyle(fontSize: 12, color: AppTheme.primaryTeal)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_latestVitals != null) ...[
            Row(
              children: [
                Expanded(
                  child: _buildVitalChip(
                    label: 'BP',
                    value:
                        '${_latestVitals!['bloodPressureSystolic'] ?? '--'}/${_latestVitals!['bloodPressureDiastolic'] ?? '--'}',
                    unit: 'mmHg',
                    icon: Icons.speed_rounded,
                    color: const Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildVitalChip(
                    label: 'Heart Rate',
                    value: '${_latestVitals!['heartRateBpm'] ?? '--'}',
                    unit: 'BPM',
                    icon: Icons.monitor_heart_outlined,
                    color: const Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildVitalChip(
                    label: 'Weight',
                    value: '${_latestVitals!['weightKg'] ?? '--'}',
                    unit: 'kg',
                    icon: Icons.scale_rounded,
                    color: const Color(0xFF2563EB),
                  ),
                ),
              ],
            ),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No recent vitals logged on your record yet.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVitalChip({
    required String label,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 5. HEALTHCARE NETWORK ONBOARDING
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHealthcareNetworkOnboarding(bool isMobile) {
    return Column(
      children: [
        _buildPromoCard(
          badge: 'For Medical Practitioners',
          title: 'Become a Doctor',
          subtitle: 'Join certified network & provide tele-consultations',
          icon: Icons.medical_services_outlined,
          color: const Color(0xFF0F766E),
          onTap: () => context.go('/patient/become-doctor'),
        ),
        const SizedBox(height: 10),
        _buildPromoCard(
          badge: 'For Healthcare Facilities',
          title: 'Register a Clinic',
          subtitle: 'List your medical facility & manage doctor branches',
          icon: Icons.local_hospital_outlined,
          color: const Color(0xFF1E40AF),
          onTap: () => context.go('/patient/become-clinic'),
        ),
      ],
    );
  }

  Widget _buildPromoCard({
    required String badge,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.7)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMain,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 6. UPCOMING CONSULTATIONS LIST
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildUpcomingConsultationsSection(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Your Upcoming Appointments',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textMain,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryLightTeal,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_upcomingAppointments.length}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryTeal,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => context.go('/patient/book-appointment'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.add, size: 15, color: AppTheme.primaryTeal),
            label: const Text('Book New',
                style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.primaryTeal,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 10),
        if (_upcomingAppointments.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            decoration: BoxDecoration(
              color: AppTheme.surfaceWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderGray.withOpacity(0.7)),
            ),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLightTeal.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.event_available_outlined,
                      color: AppTheme.primaryTeal, size: 28),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No upcoming appointments booked',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppTheme.textMain),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Need to see a doctor? Find top specialists & schedule your visit.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => context.go('/patient/book-appointment'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.calendar_month, size: 16),
                  label: const Text('Book Appointment Now',
                      style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _upcomingAppointments.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final apt = _upcomingAppointments[index];
              return _buildAppointmentCard(apt, isMobile);
            },
          ),
      ],
    );
  }

  Widget _buildAppointmentCard(dynamic apt, bool isMobile) {
    final doctorName = apt['doctorName'] ?? 'Consulting Doctor';
    final scheduledDate = apt['scheduledDate'] ?? '';
    final rawTime = (apt['startTime'] ?? '').toString();
    final startTime = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
    final status = apt['status'] ?? 'CONFIRMED';
    final type =
        (apt['appointmentType'] ?? 'GENERAL').toString().replaceAll('_', ' ');
    final sessionType = (apt['sessionType'] ?? 'IN_CLINIC').toString();
    final isClinic = sessionType == 'IN_CLINIC';
    final isConfirmed = status == 'CONFIRMED';
    final statusColor =
        isConfirmed ? const Color(0xFF0F766E) : const Color(0xFFD97706);

    return InkWell(
      onTap: () => context.push('/patient/appointments'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderGray.withOpacity(0.8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: statusColor, width: 4.5),
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.primaryLightTeal,
                      child: Text(
                        doctorName.isNotEmpty
                            ? doctorName[0].toUpperCase()
                            : 'D',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryTeal,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doctorName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: AppTheme.textMain,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined,
                                  size: 12, color: AppTheme.primaryTeal),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '$scheduledDate • $startTime',
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textMain),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundApp,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            type,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: isClinic
                                ? const Color(0xFFEFF6FF)
                                : const Color(0xFFFAF5FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isClinic ? 'In-Clinic' : 'Video Call',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: isClinic
                                  ? const Color(0xFF1D4ED8)
                                  : const Color(0xFF6D28D9),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () => _openCancelModal(apt),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.dangerRed,
                            side: const BorderSide(color: Color(0xFFFECACA)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: const Size(50, 28),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Cancel',
                              style: TextStyle(fontSize: 11)),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.chevron_right,
                            size: 18,
                            color: AppTheme.textMuted.withOpacity(0.6)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CANCEL APPOINTMENT MODAL DIALOG
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildCancelAppointmentDialog() {
    final doctorName = _cancelTarget?['doctorName'] ?? 'the doctor';

    return Container(
      color: Colors.black54,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFEE2E2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cancel_outlined,
                            color: AppTheme.dangerRed, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Cancel Appointment',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.dangerRed,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Are you sure you want to cancel your consultation with $doctorName?',
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textMain, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _cancelReasonController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Please state the reason for cancellation...',
                      hintStyle: const TextStyle(
                          fontSize: 12, color: AppTheme.textMuted),
                      filled: true,
                      fillColor: AppTheme.backgroundApp,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: AppTheme.borderGray.withOpacity(0.8)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _cancelTarget = null),
                        child: const Text('Go Back',
                            style: TextStyle(color: AppTheme.textMuted)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isCancelling ? null : _submitCancel,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.dangerRed,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isCancelling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
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
    );
  }
}

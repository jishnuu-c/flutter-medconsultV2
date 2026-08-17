import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/clinic_models.dart';
import '../data/clinic_service.dart';
import '../data/doctor_models.dart';
import '../data/doctor_service.dart';
import '../../doctor_dashboard/data/appointment_service.dart';
import '../../patient_dashboard/data/review_service.dart';

class ClinicDashboardScreen extends ConsumerStatefulWidget {
  const ClinicDashboardScreen({super.key});

  @override
  ConsumerState<ClinicDashboardScreen> createState() =>
      _ClinicDashboardScreenState();
}

class _ClinicDashboardScreenState extends ConsumerState<ClinicDashboardScreen> {
  bool _isLoading = true;
  bool _isLoadingAppointments = false;

  // Managed Clinics State
  List<ClinicModel> _clinics = [];
  ClinicModel? _selectedClinic;
  List<ClinicBranchModel> _branches = [];
  List<DoctorModel> _allDoctors = [];
  List<DoctorClinicModel> _doctorClinics = [];

  // Appointments & Queue
  List<dynamic> _appointments = [];
  String _appointmentFilter = 'TODAY'; // TODAY, SCHEDULED, COMPLETED, CANCELLED, ALL

  // Reviews & Feedback
  List<ClinicReviewModel> _reviews = [];
  double _averageRating = 0.0;
  int _totalReviews = 0;
  double _ratingCleanliness = 0.0;
  double _ratingStaff = 0.0;
  double _ratingWait = 0.0;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  String _getLogoUrl(String? path) {
    if (path == null || path.trim().isEmpty) return '';
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('data:') ||
        path.startsWith('blob:')) {
      return path;
    }
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$kBaseUrl$cleanPath';
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final clinicService = ref.read(clinicServiceProvider);
      final doctorService = ref.read(doctorServiceProvider);

      final results = await Future.wait([
        clinicService.getAllClinics().catchError((_) => <ClinicModel>[]),
        doctorService.getAllDoctors().catchError((_) => <DoctorModel>[]),
      ]);

      final clinics = results[0] as List<ClinicModel>;
      final doctors = results[1] as List<DoctorModel>;

      if (mounted) {
        setState(() {
          _clinics = clinics;
          _allDoctors = doctors;
          _isLoading = false;
        });

        if (clinics.isNotEmpty) {
          _onClinicSelected(clinics.first);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onClinicSelected(ClinicModel clinic) {
    setState(() {
      _selectedClinic = clinic;
    });

    final clinicId = clinic.clinicId;
    _loadClinicBranches(clinicId);
    _loadDoctorPlacements();
    _loadAppointments(clinicId);
    _loadClinicReviews(clinicId);
  }

  Future<void> _loadClinicBranches(String clinicId) async {
    try {
      final branches = await ref
          .read(clinicServiceProvider)
          .getClinicBranches(clinicId)
          .catchError((_) => <ClinicBranchModel>[]);
      if (mounted) {
        setState(() => _branches = branches);
      }
    } catch (_) {
      if (mounted) setState(() => _branches = []);
    }
  }

  Future<void> _loadDoctorPlacements() async {
    if (_allDoctors.isEmpty) {
      if (mounted) setState(() => _doctorClinics = []);
      return;
    }

    try {
      final requests = _allDoctors.map((doc) => ref
          .read(doctorServiceProvider)
          .getDoctorClinics(doc.doctorId)
          .catchError((_) => <DoctorClinicModel>[]));

      final results = await Future.wait(requests);
      final flattened = results.expand((list) => list).toList();

      if (mounted) {
        setState(() {
          if (_selectedClinic != null) {
            _doctorClinics = flattened
                .where((dc) => dc.clinicId == _selectedClinic!.clinicId)
                .toList();
          } else {
            _doctorClinics = flattened;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _doctorClinics = []);
    }
  }

  Future<void> _loadAppointments(String clinicId) async {
    setState(() => _isLoadingAppointments = true);
    try {
      final searchRequest = {
        'page': 0,
        'size': 50,
        'sortBy': 'scheduledDate',
        'sortDir': 'DESC',
      };
      final data = await ref
          .read(appointmentServiceProvider)
          .searchAppointments(searchRequest);

      List<dynamic> list = [];
      if (data is Map && data['content'] is List) {
        list = data['content'] as List;
      } else if (data is List) {
        list = data;
      }

      if (mounted) {
        setState(() {
          _appointments = list;
          _isLoadingAppointments = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _appointments = [];
          _isLoadingAppointments = false;
        });
      }
    }
  }

  Future<void> _loadClinicReviews(String clinicId) async {
    try {
      final reviews = await ref
          .read(reviewServiceProvider)
          .getClinicReviews(clinicId, page: 0, size: 10);

      if (mounted) {
        setState(() {
          _reviews = reviews;
          _totalReviews = reviews.length;
          if (reviews.isNotEmpty) {
            final sumRating =
                reviews.fold<int>(0, (acc, r) => acc + r.rating);
            _averageRating = double.parse(
                (sumRating / reviews.length).toStringAsFixed(1));

            final sumClean = reviews.fold<int>(
                0, (acc, r) => acc + (r.ratingCleanliness ?? r.rating));
            _ratingCleanliness = double.parse(
                (sumClean / reviews.length).toStringAsFixed(1));

            final sumStaff = reviews.fold<int>(
                0, (acc, r) => acc + (r.ratingStaff ?? r.rating));
            _ratingStaff = double.parse(
                (sumStaff / reviews.length).toStringAsFixed(1));

            final sumWait = reviews.fold<int>(
                0, (acc, r) => acc + (r.ratingWait ?? r.rating));
            _ratingWait = double.parse(
                (sumWait / reviews.length).toStringAsFixed(1));
          } else {
            _averageRating = 0.0;
            _ratingCleanliness = 0.0;
            _ratingStaff = 0.0;
            _ratingWait = 0.0;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _reviews = [];
          _totalReviews = 0;
          _averageRating = 0.0;
        });
      }
    }
  }

  // ── Metrics Computations ───────────────────────────────────────────
  String get _todayDateString {
    final d = DateTime.now();
    final year = d.year.toString();
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  List<dynamic> get _todayAppointments {
    final today = _todayDateString;
    return _appointments.where((a) {
      if (a is! Map) return false;
      return a['scheduledDate']?.toString() == today;
    }).toList();
  }

  int get _todayBookedCount {
    return _todayAppointments.where((a) {
      final s = a['status']?.toString();
      return s == 'SCHEDULED' || s == 'CONFIRMED';
    }).length;
  }

  int get _todayCompletedCount {
    return _todayAppointments.where((a) {
      return a['status']?.toString() == 'COMPLETED';
    }).length;
  }

  int get _activeDoctorsCount {
    final uniqueDocIds = _doctorClinics.map((dc) => dc.doctorId).toSet();
    return uniqueDocIds.length;
  }

  List<dynamic> get _filteredAppointments {
    final today = _todayDateString;
    switch (_appointmentFilter) {
      case 'TODAY':
        return _appointments.where((a) {
          if (a is! Map) return false;
          return a['scheduledDate']?.toString() == today;
        }).toList();
      case 'SCHEDULED':
        return _appointments.where((a) {
          if (a is! Map) return false;
          final s = a['status']?.toString();
          return s == 'SCHEDULED' || s == 'CONFIRMED';
        }).toList();
      case 'COMPLETED':
        return _appointments.where((a) {
          if (a is! Map) return false;
          return a['status']?.toString() == 'COMPLETED';
        }).toList();
      case 'CANCELLED':
        return _appointments.where((a) {
          if (a is! Map) return false;
          final s = a['status']?.toString();
          return s == 'CANCELLED' || s == 'NO_SHOW';
        }).toList();
      case 'ALL':
      default:
        return _appointments;
    }
  }

  DoctorModel? _getDoctor(String doctorId) {
    try {
      return _allDoctors.firstWhere((d) => d.doctorId == doctorId);
    } catch (_) {
      return null;
    }
  }

  String _getDoctorName(String doctorId) {
    final doc = _getDoctor(doctorId);
    if (doc == null) return 'Dr. Specialist';
    return '${doc.title.value.isNotEmpty ? doc.title.value : 'Dr.'} ${doc.fullName}';
  }

  String _getBranchName(String branchId) {
    try {
      final b = _branches.firstWhere((br) => br.branchId == branchId);
      return b.branchNameEn.isNotEmpty ? b.branchNameEn : 'Main Branch';
    } catch (_) {
      return 'Main Branch';
    }
  }

  // ── Status Updates ────────────────────────────────────────────────
  Future<void> _updateAppointmentStatus(
      String appointmentId, String status, {String? reason}) async {
    try {
      if (status == 'CANCELLED') {
        final payload = {
          'cancelReason': reason ?? 'Cancelled by Clinic Administration'
        };
        await ref
            .read(appointmentServiceProvider)
            .cancelAppointment(appointmentId, payload);
      } else {
        final payload = {'status': status};
        await ref
            .read(appointmentServiceProvider)
            .updateStatus(appointmentId, payload);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'CANCELLED'
                ? 'Appointment cancelled successfully.'
                : 'Appointment status updated.'),
            backgroundColor: AppTheme.primaryTeal,
          ),
        );
        if (_selectedClinic != null) {
          _loadAppointments(_selectedClinic!.clinicId);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
    }
  }

  void _openCancellationDialog(dynamic appointment) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Cancel Appointment',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppTheme.textMain),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppTheme.textMuted),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to cancel this appointment for ${appointment['patientName'] ?? 'this patient'}?',
                style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 14),
              const Text(
                'Reason for Cancellation',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMain),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'E.g., Doctor emergency leave, clinic maintenance...',
                  hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppTheme.borderGray),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textMain,
              side: const BorderSide(color: AppTheme.borderGray),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Keep Appointment'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _updateAppointmentStatus(
                appointment['appointmentId'].toString(),
                'CANCELLED',
                reason: reasonController.text.trim(),
              );
            },
            child: const Text('Confirm Cancellation'),
          ),
        ],
      ),
    );
  }

  void _openDoctorProfileModal(DoctorClinicModel dc) {
    final doc = _getDoctor(dc.doctorId);
    if (doc == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.person, color: AppTheme.primaryTeal, size: 20),
                      SizedBox(width: 8),
                      Text('Doctor Professional Profile',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMain)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: AppTheme.textMuted),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const Divider(color: AppTheme.borderGray),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundApp,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.borderGray),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: AppTheme.primaryTeal, width: 2),
                      ),
                      child: ClipOval(
                        child: doc.avatarUrl != null && doc.avatarUrl!.isNotEmpty
                            ? Image.network(
                                _getLogoUrl(doc.avatarUrl),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.person,
                                    size: 26,
                                    color: AppTheme.primaryTeal),
                              )
                            : const Icon(Icons.person,
                                size: 26, color: AppTheme.primaryTeal),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${doc.title.value.isNotEmpty ? doc.title.value : 'Dr.'} ${doc.fullName}',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textMain),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (doc.mohVerified) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('✓ MOH Verified',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              if (doc.email.isNotEmpty)
                                Text('✉️ ${doc.email}',
                                    style: const TextStyle(
                                        fontSize: 11, color: AppTheme.textMuted)),
                              if (doc.mohRegistrationNumber.isNotEmpty)
                                Text('MOH: ${doc.mohRegistrationNumber}',
                                    style: const TextStyle(
                                        fontSize: 11, color: AppTheme.textMuted)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _metricBox(
                        'Experience', '${doc.experienceYears} Years'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metricBox(
                        'Rating', '${doc.overallRating.toStringAsFixed(1)} ★'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metricBox('Consultation Fee',
                        'SAR ${dc.consultationFeeSar}'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Professional Biography',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundApp,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderGray),
                ),
                child: Text(
                  doc.bioEn != null && doc.bioEn!.isNotEmpty
                      ? doc.bioEn!
                      : 'No professional biography provided.',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMain),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderGray),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Active Placement Details',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Assigned Branch:',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        Text(_getBranchName(dc.branchId),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Department:',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        Text(
                            dc.department.isNotEmpty ? dc.department : 'General',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Primary Placement:',
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: dc.isPrimary
                                ? Colors.green.shade50
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            dc.isPrimary ? 'Primary' : 'Secondary',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: dc.isPrimary
                                  ? Colors.green.shade700
                                  : AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryTeal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.calendar_month, size: 15),
                      label: const Text('Manage Doctor Schedules',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        context.go('/clinic-admin/doctors');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textMain,
                      side: const BorderSide(color: AppTheme.borderGray),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: AppTheme.backgroundApp,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryTeal),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryTeal),
        ),
      );
    }

    final isDesktop = MediaQuery.of(context).size.width >= 1024;

    return Scaffold(
      backgroundColor: AppTheme.backgroundApp,
      body: RefreshIndicator(
        onRefresh: _loadInitialData,
        color: AppTheme.primaryTeal,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeaderBanner(),
              const SizedBox(height: 18),
              _buildKpiGrid(),
              const SizedBox(height: 20),
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 7,
                      child: Column(
                        children: [
                          _buildAppointmentsQueueCard(),
                          const SizedBox(height: 18),
                          _buildQuickActionsCard(),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          _buildDoctorRosterCard(),
                          const SizedBox(height: 18),
                          _buildPatientSatisfactionCard(),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    _buildAppointmentsQueueCard(),
                    const SizedBox(height: 18),
                    _buildQuickActionsCard(),
                    const SizedBox(height: 18),
                    _buildDoctorRosterCard(),
                    const SizedBox(height: 18),
                    _buildPatientSatisfactionCard(),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top Header Banner ───────────────────────────────────────────────
  Widget _buildHeaderBanner() {
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.borderGray)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Clinic Logo 56x56
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.borderGray),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x08000000),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: _selectedClinic?.logoUrl != null &&
                        _selectedClinic!.logoUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          _getLogoUrl(_selectedClinic!.logoUrl),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.local_hospital,
                            color: AppTheme.primaryTeal,
                            size: 28,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.local_hospital,
                        color: AppTheme.primaryTeal,
                        size: 28,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          (_selectedClinic?.nameEn ?? '').isNotEmpty
                              ? _selectedClinic!.nameEn
                              : 'Clinic Operations Dashboard',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal,
                          ),
                        ),
                        if ((_selectedClinic?.mohLicenseNumber ?? '').isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLightTeal,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'MOH: ${_selectedClinic!.mohLicenseNumber}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryDarkTeal,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Real-time daily operations, appointment queues, doctor roster, and patient satisfaction',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Right Side Actions / Dropdown
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_clinics.length > 1)
                Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.primaryTeal),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ClinicModel>(
                      value: _selectedClinic,
                      isDense: true,
                      icon: const Icon(Icons.arrow_drop_down,
                          color: AppTheme.primaryTeal, size: 20),
                      items: _clinics.map((c) {
                        return DropdownMenuItem<ClinicModel>(
                          value: c,
                          child: Text(c.nameEn,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textMain)),
                        );
                      }).toList(),
                      onChanged: (c) {
                        if (c != null) _onClinicSelected(c);
                      },
                    ),
                  ),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textMain,
                  side: const BorderSide(color: AppTheme.borderGray),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.apartment, size: 14, color: AppTheme.textMuted),
                label: const Text('Manage Facility',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                onPressed: () => context.go('/clinic-admin/clinics'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.person_add_alt_1, size: 14),
                label: const Text('Doctor Placements',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                onPressed: () => context.go('/clinic-admin/doctors'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── KPI Metrics Row ────────────────────────────────────────────────
  List<Widget> _buildKpiCardsList() {
    return [
      _kpiCard(
        title: "Today's Consultations",
        value: _todayAppointments.length.toString(),
        customSubtext: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            children: [
              TextSpan(
                text: '$_todayBookedCount Active',
                style: const TextStyle(
                    color: Colors.green, fontWeight: FontWeight.bold),
              ),
              const TextSpan(text: ' • '),
              TextSpan(text: '$_todayCompletedCount Completed'),
            ],
          ),
        ),
        icon: Icons.calendar_today_outlined,
        accentColor: const Color(0xFF0284C7),
        bgColor: const Color(0x1F0284C7),
      ),
      _kpiCard(
        title: 'Assigned Doctors',
        value: _activeDoctorsCount.toString(),
        subtext: '${_doctorClinics.length} Branch Placements',
        icon: Icons.people_outline,
        accentColor: const Color(0xFF0D9488),
        bgColor: const Color(0x1F0D9488),
      ),
      _kpiCard(
        title: 'Operational Branches',
        value: _branches.length.toString(),
        subtext: (_selectedClinic?.phonePrimary ?? '').isNotEmpty
            ? _selectedClinic!.phonePrimary
            : 'Fully Configured',
        icon: Icons.apartment_outlined,
        accentColor: const Color(0xFF8B5CF6),
        bgColor: const Color(0x1F8B5CF6),
      ),
      _kpiCard(
        title: 'Patient Satisfaction',
        value: _averageRating > 0
            ? _averageRating.toStringAsFixed(1)
            : '5.0',
        valueSuffix: ' / 5.0',
        subtext: '$_totalReviews Verified Patient Reviews',
        icon: Icons.star_border,
        accentColor: const Color(0xFFF59E0B),
        bgColor: const Color(0x1FF59E0B),
      ),
    ];
  }

  Widget _buildKpiGrid() {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final cards = _buildKpiCardsList();

      if (width >= 960) {
        return GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          childAspectRatio: 1.85,
          children: cards,
        );
      } else if (width >= 580) {
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.2,
          children: cards,
        );
      } else {
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) => cards[i],
        );
      }
    });
  }

  Widget _kpiCard({
    required String title,
    required String value,
    String? valueSuffix,
    String? subtext,
    Widget? customSubtext,
    required IconData icon,
    required Color accentColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderGray),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left Stripe / Accent indicator + Icon Box
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accentColor.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 14),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.4,
                  ),
                  softWrap: true,
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMain,
                        height: 1.1,
                      ),
                    ),
                    if (valueSuffix != null)
                      Text(
                        valueSuffix,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.normal,
                          color: AppTheme.textMuted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                if (customSubtext != null)
                  customSubtext
                else
                  Text(
                    subtext ?? '',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                    softWrap: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Appointments Queue Card ────────────────────────────────────────
  Widget _buildAppointmentsQueueCard() {
    final filtered = _filteredAppointments;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.assignment_outlined,
                  color: AppTheme.primaryTeal, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Live Consultations & Appointments Queue',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryTeal,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Monitor check-ins, scheduled consultations, and doctor appointments',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppTheme.backgroundApp,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.borderGray),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _filterPill('Today (${_todayAppointments.length})', 'TODAY'),
                  _filterPill('Active / Scheduled', 'SCHEDULED'),
                  _filterPill('Completed', 'COMPLETED'),
                  _filterPill('Cancelled', 'CANCELLED'),
                  _filterPill('All (${_appointments.length})', 'ALL'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoadingAppointments)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(color: AppTheme.primaryTeal),
              ),
            )
          else if (filtered.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 36),
              alignment: Alignment.center,
              child: const Column(
                children: [
                  Icon(Icons.event_busy, color: AppTheme.textMuted, size: 36),
                  SizedBox(height: 8),
                  Text('No appointment records found for this filter.',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMain)),
                  SizedBox(height: 4),
                  Text(
                    'New patient bookings will automatically stream into this operational feed.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final apt = filtered[i] as Map;
                final status = apt['status']?.toString() ?? 'SCHEDULED';
                final isVirtual = apt['sessionType'] == 'VIRTUAL';
                final patientId = apt['patientId']?.toString() ?? '';
                final patientAvatar = apt['patientAvatarUrl']?.toString() ?? '';

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderGray),
                  ),
                  child: LayoutBuilder(builder: (context, cardConstraints) {
                    final isMobileCard = cardConstraints.maxWidth < 650;

                    if (isMobileCard) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: AppTheme.backgroundApp,
                                backgroundImage: patientAvatar.isNotEmpty
                                    ? NetworkImage(_getLogoUrl(patientAvatar))
                                    : null,
                                child: patientAvatar.isEmpty
                                    ? const Icon(Icons.person,
                                        size: 18, color: AppTheme.textMuted)
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      apt['patientName']?.toString() ?? 'Patient',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textMain),
                                    ),
                                    Text(
                                      'ID: ${patientId.isNotEmpty ? (patientId.length > 8 ? patientId.substring(0, 8) : patientId) : "N/A"}',
                                      style: const TextStyle(
                                          fontSize: 10, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              _statusBadge(status),
                            ],
                          ),
                          const Divider(height: 16, color: AppTheme.borderGray),
                          Row(
                            children: [
                              const Icon(Icons.medical_services_outlined,
                                  size: 13, color: AppTheme.primaryTeal),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  apt['doctorName']?.toString() ?? 'Doctor',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primaryTeal),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isVirtual
                                      ? Colors.blue.shade50
                                      : AppTheme.primaryLightTeal,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isVirtual
                                          ? Icons.videocam_outlined
                                          : Icons.local_hospital_outlined,
                                      size: 11,
                                      color: isVirtual
                                          ? Colors.blue.shade700
                                          : AppTheme.primaryDarkTeal,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      isVirtual ? 'Virtual' : 'In-Clinic',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isVirtual
                                            ? Colors.blue.shade700
                                            : AppTheme.primaryDarkTeal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.access_time,
                                      size: 12, color: AppTheme.primaryTeal),
                                  const SizedBox(width: 4),
                                  Text(
                                    apt['startTime']?.toString() ?? 'Scheduled',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textMain),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.calendar_today,
                                      size: 11, color: AppTheme.textMuted),
                                  const SizedBox(width: 4),
                                  Text(
                                    apt['scheduledDate']?.toString() ?? '',
                                    style: const TextStyle(
                                        fontSize: 10, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                              _buildActionButtons(apt, status),
                            ],
                          ),
                        ],
                      );
                    }

                    // Desktop Grid Card Layout
                    return Row(
                      children: [
                        // 1. Patient Cell
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: AppTheme.backgroundApp,
                                backgroundImage: patientAvatar.isNotEmpty
                                    ? NetworkImage(_getLogoUrl(patientAvatar))
                                    : null,
                                child: patientAvatar.isEmpty
                                    ? const Icon(Icons.person,
                                        size: 18, color: AppTheme.textMuted)
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      apt['patientName']?.toString() ?? 'Patient',
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textMain),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'ID: ${patientId.isNotEmpty ? (patientId.length > 8 ? patientId.substring(0, 8) : patientId) : "N/A"}',
                                      style: const TextStyle(
                                          fontSize: 10, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 2. Doctor & Session Cell
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.medical_services_outlined,
                                      size: 12, color: AppTheme.primaryTeal),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      apt['doctorName']?.toString() ?? 'Doctor',
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primaryTeal),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: isVirtual
                                          ? Colors.blue.shade50
                                          : AppTheme.primaryLightTeal,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isVirtual ? 'Virtual' : 'In-Clinic',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: isVirtual
                                            ? Colors.blue.shade700
                                            : AppTheme.primaryDarkTeal,
                                      ),
                                    ),
                                  ),
                                  if (apt['appointmentType'] != null &&
                                      apt['appointmentType'].toString().isNotEmpty) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      '(${apt['appointmentType']})',
                                      style: const TextStyle(
                                          fontSize: 9.5, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        // 3. Time & Date Cell
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.access_time,
                                      size: 11, color: AppTheme.primaryTeal),
                                  const SizedBox(width: 4),
                                  Text(
                                    apt['startTime']?.toString() ?? 'Scheduled',
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textMain),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(Icons.calendar_today,
                                      size: 10, color: AppTheme.textMuted),
                                  const SizedBox(width: 4),
                                  Text(
                                    apt['scheduledDate']?.toString() ?? '',
                                    style: const TextStyle(
                                        fontSize: 10, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // 4. Status Badge Cell
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          child: _statusBadge(status),
                        ),
                        // 5. Actions Cell
                        _buildActionButtons(apt, status),
                      ],
                    );
                  }),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(dynamic apt, String status) {
    if (status == 'SCHEDULED' || status == 'CONFIRMED') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green,
              side: const BorderSide(color: Colors.green),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            icon: const Icon(Icons.check, size: 12),
            label: const Text('Complete', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
            onPressed: () => _updateAppointmentStatus(
              apt['appointmentId'].toString(),
              'COMPLETED',
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.dangerRed,
              side: const BorderSide(color: AppTheme.dangerRed),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            icon: const Icon(Icons.close, size: 12),
            label: const Text('Cancel', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
            onPressed: () => _openCancellationDialog(apt),
          ),
        ],
      );
    }
    return const Text(
      'Processed',
      style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
    );
  }

  Widget _filterPill(String title, String key) {
    final isActive = _appointmentFilter == key;
    return InkWell(
      onTap: () => setState(() => _appointmentFilter = key),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          boxShadow: isActive
              ? const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive ? AppTheme.primaryTeal : AppTheme.textMain,
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color bg = Colors.blue.shade50;
    Color fg = Colors.blue.shade700;
    if (status == 'COMPLETED') {
      bg = Colors.green.shade50;
      fg = Colors.green.shade700;
    } else if (status == 'CANCELLED' || status == 'NO_SHOW') {
      bg = Colors.red.shade50;
      fg = Colors.red.shade700;
    } else if (status == 'CONFIRMED') {
      bg = AppTheme.primaryLightTeal;
      fg = AppTheme.primaryDarkTeal;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  // ── Facility Operations Shortcuts ──────────────────────────────────
  Widget _buildQuickActionsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text(
                'Facility Operations Shortcuts',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryTeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final isSmall = constraints.maxWidth < 600;

            if (isSmall) {
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _shortcutBox(
                          icon: Icons.apartment,
                          title: 'Branch Locations',
                          desc: 'Add branches & configure GPS locations',
                          onTap: () => context.go('/clinic-admin/clinics'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _shortcutBox(
                          icon: Icons.person_add_alt_1,
                          title: 'Doctor Placements',
                          desc: 'Assign doctors to branch departments',
                          onTap: () => context.go('/clinic-admin/doctors'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _shortcutBox(
                          icon: Icons.verified_user_outlined,
                          title: 'Insurance Networks',
                          desc: 'Link accepted insurance policies',
                          onTap: () => context.go('/clinic-admin/clinics'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _shortcutBox(
                          icon: Icons.schedule,
                          title: 'Operating Hours',
                          desc: 'Configure weekly shift schedules',
                          onTap: () => context.go('/clinic-admin/clinics'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(
                  child: _shortcutBox(
                    icon: Icons.apartment,
                    title: 'Branch Locations',
                    desc: 'Add branches & configure GPS locations',
                    onTap: () => context.go('/clinic-admin/clinics'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _shortcutBox(
                    icon: Icons.person_add_alt_1,
                    title: 'Doctor Placements',
                    desc: 'Assign doctors to branch departments',
                    onTap: () => context.go('/clinic-admin/doctors'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _shortcutBox(
                    icon: Icons.verified_user_outlined,
                    title: 'Insurance Networks',
                    desc: 'Link accepted insurance policies',
                    onTap: () => context.go('/clinic-admin/clinics'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _shortcutBox(
                    icon: Icons.schedule,
                    title: 'Operating Hours',
                    desc: 'Configure weekly shift schedules',
                    onTap: () => context.go('/clinic-admin/clinics'),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _shortcutBox({
    required IconData icon,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.backgroundApp,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.borderGray),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppTheme.primaryTeal, size: 20),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryTeal),
              maxLines: 2,
              softWrap: true,
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
              maxLines: 2,
              softWrap: true,
            ),
          ],
        ),
      ),
    );
  }

  // ── Doctor Roster Card ─────────────────────────────────────────────
  Widget _buildDoctorRosterCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.people_outline, color: AppTheme.primaryTeal, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Doctor Roster',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryTeal,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => context.go('/clinic-admin/doctors'),
                child: const Text('View All →',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryTeal)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_doctorClinics.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              alignment: Alignment.center,
              child: Column(
                children: [
                  const Text('No doctors placed in this clinic yet.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryTeal,
                      side: const BorderSide(color: AppTheme.primaryTeal),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: () => context.go('/clinic-admin/doctors'),
                    child: const Text('+ Assign Doctors', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _doctorClinics.take(6).length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final dc = _doctorClinics[i];
                final doc = _getDoctor(dc.doctorId);

                return InkWell(
                  onTap: () => _openDoctorProfileModal(dc),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundApp,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.borderGray),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: Colors.white,
                          backgroundImage: doc?.avatarUrl != null &&
                                  doc!.avatarUrl!.isNotEmpty
                              ? NetworkImage(_getLogoUrl(doc.avatarUrl))
                              : null,
                          child: doc?.avatarUrl == null ||
                                  doc!.avatarUrl!.isEmpty
                              ? Text(
                                  doc != null && doc.fullName.isNotEmpty
                                      ? doc.fullName[0]
                                      : 'D',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryTeal),
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      _getDoctorName(dc.doctorId),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textMain),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (doc?.mohVerified == true) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      width: 14,
                                      height: 14,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.green,
                                      ),
                                      alignment: Alignment.center,
                                      child: const Text('✓',
                                          style: TextStyle(
                                              fontSize: 8.5,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(Icons.location_on_outlined,
                                      size: 11, color: AppTheme.textMuted),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      '${_getBranchName(dc.branchId)}${dc.department.isNotEmpty ? " • ${dc.department}" : ""}',
                                      style: const TextStyle(
                                          fontSize: 10, color: AppTheme.textMuted),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLightTeal,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                dc.department.isNotEmpty ? dc.department : 'Specialist',
                                style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryDarkTeal),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'SAR ${dc.consultationFeeSar}',
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ── Patient Satisfaction Card ──────────────────────────────────────
  Widget _buildPatientSatisfactionCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.star, color: Colors.amber, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Patient Feedback',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryTeal,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Text(
                      _averageRating > 0
                          ? _averageRating.toStringAsFixed(1)
                          : '5.0',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.star, size: 12, color: Colors.amber.shade800),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Rating Breakdown Bars
          _buildRatingBar(
            'Cleanliness',
            _ratingCleanliness > 0 ? _ratingCleanliness : 5.0,
            AppTheme.primaryTeal,
          ),
          const SizedBox(height: 8),
          _buildRatingBar(
            'Staff Courtesy',
            _ratingStaff > 0 ? _ratingStaff : 5.0,
            const Color(0xFF0284C7),
          ),
          const SizedBox(height: 8),
          _buildRatingBar(
            'Wait Time',
            _ratingWait > 0 ? _ratingWait : 4.8,
            Colors.amber.shade700,
          ),

          const SizedBox(height: 16),
          const Divider(color: AppTheme.borderGray),
          const SizedBox(height: 10),

          // Recent Reviews Feed
          if (_reviews.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              child: const Column(
                children: [
                  Text('No reviews received yet.',
                      style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  SizedBox(height: 2),
                  Text(
                    'Patient feedback after consultations will appear here.',
                    style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _reviews.take(3).length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final r = _reviews[i];
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundApp,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderGray),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            r.isAnonymous
                                ? 'Anonymous Patient'
                                : ((r.patientName != null &&
                                        r.patientName!.isNotEmpty)
                                    ? r.patientName!
                                    : 'Verified Patient'),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMain,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                '${r.rating}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.star,
                                  size: 11, color: Colors.amber),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '"${(r.reviewText != null && r.reviewText!.isNotEmpty) ? r.reviewText! : "Great medical care and helpful staff."}"',
                        style: const TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRatingBar(String label, double rating, Color color) {
    final clamped = rating.clamp(0.0, 5.0);
    final ratio = clamped / 5.0;

    return Row(
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: AppTheme.borderGray,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 26,
          child: Text(
            clamped.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMain,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

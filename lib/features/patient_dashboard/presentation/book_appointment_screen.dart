import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/references_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_notification.dart';
import '../../clinic_admin/data/clinic_service.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../clinic_admin/data/doctor_models.dart';
import '../../doctor_dashboard/data/appointment_service.dart';
import '../data/patient_service.dart';

class _C {
  static const avatarBg = [
    Color(0xFFE0F2FE),
    Color(0xFFF0FDFA),
    Color(0xFFEDE9FE),
    Color(0xFFFEF3C7),
    Color(0xFFECFDF5),
  ];
  static const avatarFg = [
    Color(0xFF0369A1),
    Color(0xFF0F766E),
    Color(0xFF6D28D9),
    Color(0xFFB45309),
    Color(0xFF047857),
  ];
}

String? _resolveUrl(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final value = raw.trim();
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) return value;
  final base = kBaseUrl.endsWith('/')
      ? kBaseUrl.substring(0, kBaseUrl.length - 1)
      : kBaseUrl;
  final path = value.startsWith('/') ? value : '/$value';
  return '$base$path';
}

class _NextDay {
  final String date;
  final String dayNum;
  final String dayName;
  final String monthName;
  bool hasSlots;
  _NextDay({
    required this.date,
    required this.dayNum,
    required this.dayName,
    required this.monthName,
  }) : hasSlots = true;
}

/// 4-step wizard: Doctor → Clinic → Date & Time → Confirm.
/// Mirrors Angular's book-appointment.component 1:1.
class BookAppointmentScreen extends ConsumerStatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  ConsumerState<BookAppointmentScreen> createState() =>
      _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends ConsumerState<BookAppointmentScreen> {
  final _reasonController = TextEditingController();
  final _searchController = TextEditingController();

  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _needProfileInit = false;

  String? _patientId;
  int _currentStep = 1;

  // Step 1 data + filters
  List<DoctorModel> _doctors = [];
  List<SpecialtyModel> _specialties = [];
  final Map<String, List<String>> _doctorSpecialtiesMap = {};
  final Map<String, String> _doctorPrimarySpecialtyName = {};
  List<String> _activeBookedDoctorIds = [];

  String _searchQuery = '';
  String _selectedSpecialtyId = '';
  int _selectedMinExperience = 0;
  String _selectedSortOption = 'rating';

  // Step 2 data
  List<DoctorClinicModel> _doctorClinics = [];

  // Step 3 data
  List<_NextDay> _nextDays = [];
  List<dynamic> _slots = [];

  // Wizard selections
  String? _selectedDoctorId;
  String? _selectedDcId;
  String? _selectedDate; // yyyy-MM-dd
  String? _selectedSlotId;
  String _selectedApptType = 'NEW_PATIENT';
  String _selectedSessionType = 'IN_CLINIC';

  @override
  void initState() {
    super.initState();
    _initNextDays();
    _checkProfileAndLoad();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _initNextDays() {
    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final days = <_NextDay>[];
    final now = DateTime.now();
    for (var i = 0; i < 7; i++) {
      final d = now.add(Duration(days: i));
      final dateStr =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      days.add(_NextDay(
        date: dateStr,
        dayNum: d.day.toString(),
        dayName: dayNames[d.weekday % 7],
        monthName: monthNames[d.month - 1],
      ));
    }
    setState(() => _nextDays = days);
  }

  Future<void> _checkProfileAndLoad() async {
    setState(() => _isLoading = true);
    try {
      final profile = await ref.read(patientServiceProvider).getMyProfile();
      final id = profile is Map ? profile['patientId']?.toString() : null;
      if (id == null || id.isEmpty) {
        setState(() => _needProfileInit = true);
        return;
      }
      _patientId = id;
      await _loadExistingAppointments();
    } catch (e) {
      final status = e is DioException ? e.response?.statusCode : null;
      if (status == 404) {
        setState(() => _needProfileInit = true);
      } else {
        await _loadDoctors();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadExistingAppointments() async {
    try {
      final res = await ref
          .read(appointmentServiceProvider)
          .getMyAppointments(size: 100);
      final list = (res is Map ? res['content'] : null) as List? ?? [];
      final now = DateTime.now();
      final todayStr =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      _activeBookedDoctorIds = list
          .where((a) =>
              (a['status'] == 'SCHEDULED' || a['status'] == 'CONFIRMED') &&
              (a['scheduledDate'] ?? '').toString().compareTo(todayStr) >= 0)
          .map((a) => a['doctorId']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (_) {
      _activeBookedDoctorIds = [];
    }
    await _loadDoctors();
  }

  Future<void> _loadDoctors() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ref.read(doctorServiceProvider).getAllDoctors(),
        ref.read(referenceServiceProvider).getAllSpecialties(),
      ]);
      final doctors = results[0] as List<DoctorModel>;
      final specialties = results[1] as List<SpecialtyModel>;

      if (doctors.isNotEmpty) {
        final specResults = await Future.wait(doctors.map((doc) async {
          try {
            final specs = await ref
                .read(doctorServiceProvider)
                .getDoctorSpecialties(doc.doctorId);
            return MapEntry(doc.doctorId, specs);
          } catch (_) {
            return MapEntry(doc.doctorId, <DoctorSpecialtyModel>[]);
          }
        }));
        for (final entry in specResults) {
          _doctorSpecialtiesMap[entry.key] =
              entry.value.map((s) => s.specialtyId).toList();
          if (entry.value.isNotEmpty) {
            final primary = entry.value.where((s) => s.isPrimary).toList();
            final chosen =
                primary.isNotEmpty ? primary.first : entry.value.first;
            final details = specialties
                .where((s) => s.specialtyId == chosen.specialtyId)
                .toList();
            if (details.isNotEmpty) {
              _doctorPrimarySpecialtyName[entry.key] = details.first.nameEn;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _doctors = doctors;
          _specialties = specialties;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<DoctorModel> get _filteredDoctors {
    var result = [..._doctors];

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      result = result
          .where((d) =>
              d.fullName.toLowerCase().contains(q) ||
              (d.bioEn ?? '').toLowerCase().contains(q) ||
              (d.bioAr ?? '').toLowerCase().contains(q))
          .toList();
    }

    if (_selectedSpecialtyId.isNotEmpty) {
      result = result
          .where((d) => (_doctorSpecialtiesMap[d.doctorId] ?? [])
              .contains(_selectedSpecialtyId))
          .toList();
    }

    if (_selectedMinExperience > 0) {
      result = result
          .where((d) => d.experienceYears >= _selectedMinExperience)
          .toList();
    }

    result.sort((a, b) {
      switch (_selectedSortOption) {
        case 'experience':
          return b.experienceYears.compareTo(a.experienceYears);
        case 'fee_asc':
          return a.consultationFeeSar.compareTo(b.consultationFeeSar);
        case 'fee_desc':
          return b.consultationFeeSar.compareTo(a.consultationFeeSar);
        case 'name':
          return a.fullName.compareTo(b.fullName);
        case 'rating':
        default:
          return b.overallRating.compareTo(a.overallRating);
      }
    });

    return result;
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedSpecialtyId = '';
      _selectedMinExperience = 0;
      _selectedSortOption = 'rating';
    });
  }

  Future<void> _selectDoctor(String doctorId) async {
    setState(() {
      _selectedDoctorId = doctorId;
      _doctorClinics = [];
      _slots = [];
      _selectedDcId = null;
      _selectedDate = null;
      _selectedSlotId = null;
      _currentStep = 2;
    });
    await _onDoctorChange(doctorId);
  }

  Future<void> _onDoctorChange(String docId) async {
    setState(() => _isLoading = true);
    try {
      final clinics =
          await ref.read(doctorServiceProvider).getDoctorClinics(docId);
      final activeClinics = clinics.where((c) => c.isActive).toList();
      if (activeClinics.isEmpty) {
        if (mounted) setState(() => _doctorClinics = []);
        return;
      }
      final clinicService = ref.read(clinicServiceProvider);
      final enriched = await Future.wait(activeClinics.map((dc) async {
        try {
          final detail = await clinicService.getClinicDetail(dc.clinicId);
          final branch =
              detail.branches.where((b) => b.branchId == dc.branchId).toList();
          return DoctorClinicModel(
            dcId: dc.dcId,
            doctorId: dc.doctorId,
            clinicId: dc.clinicId,
            branchId: dc.branchId,
            department: dc.department,
            consultationFeeSar: dc.consultationFeeSar,
            isPrimary: dc.isPrimary,
            startDate: dc.startDate,
            endDate: dc.endDate,
            isActive: dc.isActive,
            clinicNameEn: detail.nameEn,
            branchNameEn: branch.isNotEmpty
                ? branch.first.branchNameEn
                : 'Main Branch',
          );
        } catch (_) {
          return dc;
        }
      }));
      if (mounted) setState(() => _doctorClinics = enriched);
    } catch (_) {
      if (mounted) setState(() => _doctorClinics = []);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectClinic(String dcId) async {
    setState(() {
      _selectedDcId = dcId;
      _currentStep = 3;
    });
    await _checkSlotsForNextDays(dcId);
    await _onClinicOrDateChange();
  }

  Future<void> _checkSlotsForNextDays(String dcId) async {
    try {
      final results = await Future.wait(_nextDays.map((d) async {
        try {
          return await ref
              .read(doctorServiceProvider)
              .getAvailableSlots(dcId, date: d.date);
        } catch (_) {
          return <dynamic>[];
        }
      }));
      for (var i = 0; i < _nextDays.length; i++) {
        _nextDays[i].hasSlots =
            results[i].where((s) => s['status'] == 'AVAILABLE').isNotEmpty;
      }
      if (mounted) setState(() {});

      final selected = _nextDays.where((d) => d.date == _selectedDate).toList();
      if (selected.isNotEmpty && selected.first.hasSlots == false) {
        final firstAvailable = _nextDays.where((d) => d.hasSlots).toList();
        if (firstAvailable.isNotEmpty) {
          setState(() => _selectedDate = firstAvailable.first.date);
          await _onClinicOrDateChange();
        }
      }
    } catch (_) {}
  }

  Future<void> _onClinicOrDateChange() async {
    setState(() {
      _slots = [];
      _selectedSlotId = null;
    });
    if (_selectedDcId == null || _selectedDate == null) return;
    setState(() => _isLoading = true);
    try {
      final slots = await ref
          .read(doctorServiceProvider)
          .getAvailableSlots(_selectedDcId!, date: _selectedDate!);
      if (mounted) setState(() => _slots = slots);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate(String dateStr) async {
    setState(() => _selectedDate = dateStr);
    await _onClinicOrDateChange();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate != null
          ? (DateTime.tryParse(_selectedDate!) ?? DateTime.now())
          : DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (picked != null) {
      final dateStr =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      await _selectDate(dateStr);
    }
  }

  void _selectSlot(String slotId) {
    setState(() {
      _selectedSlotId = slotId;
      _currentStep = 4;
    });
  }

  void _goToStep(int step) {
    if (step > 1 && _selectedDoctorId == null) return;
    if (step > 2 && _selectedDcId == null) return;
    if (step > 3 && (_selectedDate == null || _selectedSlotId == null)) return;
    setState(() => _currentStep = step);
  }

  DoctorModel? get _selectedDoctor => _selectedDoctorId == null
      ? null
      : _doctors.where((d) => d.doctorId == _selectedDoctorId).firstOrNull;

  DoctorClinicModel? get _selectedClinic => _selectedDcId == null
      ? null
      : _doctorClinics.where((c) => c.dcId == _selectedDcId).firstOrNull;

  dynamic get _selectedSlot => _selectedSlotId == null
      ? null
      : _slots.where((s) => s['slotId'] == _selectedSlotId).firstOrNull;

  String _doctorDisplayName(String fullName) {
    final trimmed = fullName.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('dr') ||
        lower.startsWith('doctor') ||
        lower.startsWith('prof') ||
        lower.startsWith('consultant') ||
        lower.startsWith('specialist') ||
        trimmed.startsWith('د.')) {
      return trimmed;
    }
    return 'Dr. $trimmed';
  }

  String _initialsOf(String name) {
    if (name.trim().isEmpty) return 'DR';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts.first[0] + parts.last[0]).toUpperCase();
    }
    return name
        .trim()
        .substring(0, name.trim().length.clamp(0, 2))
        .toUpperCase();
  }

  int _colorIndex(String name) {
    var sum = 0;
    for (final code in name.codeUnits) {
      sum += code;
    }
    return sum % _C.avatarBg.length;
  }

  String _fmtFee(double fee) => fee == fee.roundToDouble()
      ? fee.toInt().toString()
      : fee.toStringAsFixed(2);

  bool get _canSubmit =>
      _patientId != null &&
      _selectedDcId != null &&
      _selectedDate != null &&
      _selectedSlotId != null;

  Future<void> _confirmBooking() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);
    try {
      await ref.read(appointmentServiceProvider).bookAppointment({
        'patientId': _patientId,
        'dcId': _selectedDcId,
        'slotId': _selectedSlotId,
        'appointmentType': _selectedApptType,
        'scheduledDate': _selectedDate,
        'sessionType': _selectedSessionType,
        'reason': _reasonController.text.trim(),
      });
      if (mounted) {
        AppNotification.showSuccess(
          context,
          'Appointment booked successfully!',
        );
        context.go('/patient/home');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showError(
          context,
          _extractErrorMessage(e),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _extractErrorMessage(Object e) {
    if (e is! DioException) return 'Failed to book appointment.';
    final data = e.response?.data;
    if (data == null) return 'Failed to book appointment.';
    if (data is String) return data;
    if (data is Map) {
      if (data['message'] != null) return data['message'].toString();
      if (data['error'] != null) return data['error'].toString();
      if (data['errors'] is List) {
        final errors = data['errors'] as List;
        return errors
            .map((er) =>
                er is Map ? (er['defaultMessage'] ?? er['message'] ?? er) : er)
            .join(', ');
      }
    }
    return 'Failed to book appointment.';
  }

  @override
  Widget build(BuildContext context) {
    if (_needProfileInit) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundApp,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceWhite,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.8)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(Icons.warning_amber_rounded,
                        color: AppTheme.warningAmber, size: 30),
                  ),
                  const SizedBox(height: 16),
                  const Text('Registration Required',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text(
                    'Please initialize your General Patient Profile before booking a new appointment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => context.go('/patient/profile'),
                    child: const Text('Setup Profile'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final isMobile = MediaQuery.of(context).size.width <= 768;

    return Scaffold(
      backgroundColor: AppTheme.backgroundApp,
      body: SafeArea(
        child: (_isLoading && _doctors.isEmpty)
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
            : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 16 : 24,
                        vertical: isMobile ? 16 : 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(isMobile),
                          const SizedBox(height: 16),
                          _buildStepNav(),
                          const SizedBox(height: 20),
                          if (_currentStep == 1) _buildStep1(isMobile),
                          if (_currentStep == 2) _buildStep2(),
                          if (_currentStep == 3) _buildStep3(),
                          if (_currentStep == 4) _buildStep4(isMobile),
                        ],
                      ),
                    ),
                  ),
                  _buildBottomBar(),
                ],
              ),
      ),
    );
  }

  // ── Header Banner ────────────────────────────────────────────────────────
  Widget _buildHeader(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F766E), Color(0xFF115E59)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: 0.2),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_month_outlined, size: 13, color: Colors.white),
                    SizedBox(width: 5),
                    Text(
                      'APPOINTMENT BOOKING',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF14B8A6).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'SA MOH Verified',
                  style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Schedule Consultation',
            style: TextStyle(
              color: Colors.white,
              fontSize: isMobile ? 22 : 26,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Select your preferred doctor, clinic branch, and appointment slot',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: isMobile ? 12 : 13.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Step Navigation ──────────────────────────────────────────────────────
  Widget _buildStepNav() {
    const labels = ['Doctor', 'Clinic', 'Date & Time', 'Confirm'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          for (var i = 1; i <= 4; i++) ...[
            Expanded(
              child: GestureDetector(
                onTap: () => _goToStep(i),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: i == _currentStep
                          ? AppTheme.primaryTeal
                          : (i < _currentStep
                              ? AppTheme.primaryLightTeal
                              : AppTheme.borderGray.withValues(alpha: 0.5)),
                      child: i < _currentStep
                          ? const Icon(Icons.check, size: 14, color: AppTheme.primaryTeal)
                          : Text(
                              '$i',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: i == _currentStep ? Colors.white : AppTheme.textMuted,
                              ),
                            ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labels[i - 1],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: i == _currentStep ? FontWeight.bold : FontWeight.w500,
                        color: i == _currentStep ? AppTheme.primaryTeal : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i != 4)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Icon(Icons.chevron_right_rounded,
                    color: AppTheme.borderGray.withValues(alpha: 0.8), size: 16),
              ),
          ],
        ],
      ),
    );
  }

  // ── STEP 1: Choose Doctor ────────────────────────────────────────────────
  Widget _buildStep1(bool isMobile) {
    final filtered = _filteredDoctors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepTitle(
          Icons.person_search_rounded,
          'Step 1: Choose Specialist Doctor',
          'Browse our verified doctors panel and select a specialist to check clinic locations',
        ),
        const SizedBox(height: 14),
        _filtersCard(isMobile),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          _emptyState(Icons.person_search_rounded, 'No Doctors Found',
              'No medical experts match your search query.')
        else
          Column(children: filtered.map((doc) => _doctorCard(doc)).toList()),
      ],
    );
  }

  Widget _filtersCard(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Search Doctor Name',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
          const SizedBox(height: 6),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Type to search...',
              hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textMuted),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 16, color: AppTheme.textMuted),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Medical Specialty',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _selectedSpecialtyId,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('All Specialties')),
              ..._specialties.map((s) => DropdownMenuItem(
                  value: s.specialtyId,
                  child: Text(s.nameEn, overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (v) => setState(() => _selectedSpecialtyId = v ?? ''),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Experience',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedMinExperience,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Any')),
                        DropdownMenuItem(value: 3, child: Text('3+ Yrs')),
                        DropdownMenuItem(value: 5, child: Text('5+ Yrs')),
                        DropdownMenuItem(value: 10, child: Text('10+ Yrs')),
                      ],
                      onChanged: (v) =>
                          setState(() => _selectedMinExperience = v ?? 0),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sort By',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedSortOption,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'rating', child: Text('Rating')),
                        DropdownMenuItem(value: 'experience', child: Text('Experience')),
                        DropdownMenuItem(value: 'fee_asc', child: Text('Fee: Low')),
                        DropdownMenuItem(value: 'fee_desc', child: Text('Fee: High')),
                        DropdownMenuItem(value: 'name', child: Text('Name')),
                      ],
                      onChanged: (v) =>
                          setState(() => _selectedSortOption = v ?? 'rating'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '${_filteredDoctors.length} doctors found matching criteria',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                ),
              ),
              if (_searchQuery.isNotEmpty ||
                  _selectedSpecialtyId.isNotEmpty ||
                  _selectedMinExperience > 0 ||
                  _selectedSortOption != 'rating')
                TextButton.icon(
                  onPressed: _resetFilters,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                  icon: const Icon(Icons.refresh, size: 13),
                  label: const Text('Reset Filters', style: TextStyle(fontSize: 11.5)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _doctorCard(DoctorModel doc) {
    final alreadyBooked = _activeBookedDoctorIds.contains(doc.doctorId);
    final selected = _selectedDoctorId == doc.doctorId;
    final avatarUrl = _resolveUrl(doc.avatarUrl);
    final colorIdx = _colorIndex(doc.fullName);
    final specialtyName =
        _doctorPrimarySpecialtyName[doc.doctorId] ?? 'General Practitioner';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: alreadyBooked
            ? const Color(0xFFF9FAFB)
            : (selected ? AppTheme.primaryLightTeal : AppTheme.surfaceWhite),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? AppTheme.primaryTeal
              : (alreadyBooked ? AppTheme.borderGray : AppTheme.borderGray.withValues(alpha: 0.7)),
          width: selected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: alreadyBooked ? null : () => _selectDoctor(doc.doctorId),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: alreadyBooked
                          ? const Color(0xFFF3F4F6)
                          : _C.avatarBg[colorIdx],
                      backgroundImage: (!alreadyBooked && avatarUrl != null)
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: (alreadyBooked || avatarUrl == null)
                          ? Text(_initialsOf(doc.fullName),
                              style: TextStyle(
                                  color: alreadyBooked
                                      ? const Color(0xFF9CA3AF)
                                      : _C.avatarFg[colorIdx],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_doctorDisplayName(doc.fullName),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14.5)),
                          const SizedBox(height: 3),
                          Text(specialtyName,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.primaryTeal,
                                  fontWeight: FontWeight.w600)),
                          if (!alreadyBooked) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text('${doc.experienceYears} Yrs Exp',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                const Text(' • ', style: TextStyle(color: AppTheme.textMuted)),
                                const Icon(Icons.star, size: 12, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 2),
                                Text('${doc.overallRating} (${doc.reviewCount})',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                              ],
                            ),
                          ] else ...[
                            const SizedBox(height: 4),
                            const Row(
                              children: [
                                Icon(Icons.info_outline, size: 12, color: AppTheme.warningAmber),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text('Active booking exists with this doctor',
                                      style: TextStyle(fontSize: 10.5, color: AppTheme.warningAmber)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle, color: AppTheme.primaryTeal, size: 20),
                  ],
                ),
                if (!alreadyBooked) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('Fee: SAR ${_fmtFee(doc.consultationFeeSar)}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF059669),
                                fontWeight: FontWeight.bold)),
                      ),
                      TextButton.icon(
                        onPressed: () => context.push('/doctors/${doc.doctorId}'),
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 0)),
                        icon: const Icon(Icons.remove_red_eye_outlined, size: 13),
                        label: const Text('View Profile', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── STEP 2: Choose Clinic ────────────────────────────────────────────────
  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepTitle(
          Icons.local_hospital_outlined,
          'Step 2: Choose Clinic Location',
          'Select from the branch locations where this doctor is currently practicing',
        ),
        const SizedBox(height: 14),
        if (_isLoading)
          const Center(
              child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppTheme.primaryTeal)))
        else if (_doctorClinics.isEmpty)
          _emptyState(Icons.local_hospital_outlined, 'No Branches Registered',
              'This doctor is not assigned to any active clinic branch locations.')
        else
          Column(children: _doctorClinics.map((dc) => _clinicCard(dc)).toList()),
      ],
    );
  }

  Widget _clinicCard(DoctorClinicModel dc) {
    final selected = _selectedDcId == dc.dcId;
    return GestureDetector(
      onTap: () => _selectClinic(dc.dcId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryLightTeal : AppTheme.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.primaryTeal : AppTheme.borderGray.withValues(alpha: 0.7),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryLightTeal,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.location_on_outlined, color: AppTheme.primaryTeal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(dc.clinicNameEn ?? dc.department,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (dc.isPrimary)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLightTeal,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('Primary',
                              style: TextStyle(
                                  fontSize: 9.5,
                                  color: AppTheme.primaryDarkTeal,
                                  fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(dc.branchNameEn ?? '',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(dc.department,
                            style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${_fmtFee(dc.consultationFeeSar)} SAR',
                            style: const TextStyle(fontSize: 10.5, color: Color(0xFF059669), fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.check_circle, color: AppTheme.primaryTeal, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  // ── STEP 3: Date & Slot ──────────────────────────────────────────────────
  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepTitle(
          Icons.calendar_month_outlined,
          'Step 3: Appointment Date & Time',
          'Select a booking date to see available consultation time slots',
        ),
        const SizedBox(height: 14),
        const Text('Select Date',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _nextDays.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final day = _nextDays[i];
              final selected = _selectedDate == day.date;
              final noSlots = day.hasSlots == false;
              return GestureDetector(
                onTap: () => _selectDate(day.date),
                child: Container(
                  width: 62,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.primaryTeal : AppTheme.surfaceWhite,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? AppTheme.primaryTeal : AppTheme.borderGray.withValues(alpha: 0.8),
                    ),
                  ),
                  child: Opacity(
                    opacity: noSlots ? 0.45 : 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(day.dayName,
                            style: TextStyle(
                                fontSize: 10.5,
                                color: selected ? Colors.white70 : AppTheme.textMuted)),
                        const SizedBox(height: 2),
                        Text(day.dayNum,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: selected ? Colors.white : AppTheme.textMain)),
                        Text(day.monthName,
                            style: TextStyle(
                                fontSize: 10,
                                color: selected ? Colors.white70 : AppTheme.textMuted)),
                        if (noSlots) ...[
                          const SizedBox(height: 2),
                          Text('No Slots',
                              style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: selected ? Colors.white : const Color(0xFF94A3B8))),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_today, size: 14),
          label: Text(_selectedDate == null ? 'Or choose another date' : _selectedDate!),
        ),
        if (_selectedDate != null) ...[
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          const Row(
            children: [
              Icon(Icons.access_time, size: 15, color: AppTheme.textMain),
              SizedBox(width: 6),
              Text('Available Slots', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          if (_isLoading)
            const Center(
                child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppTheme.primaryTeal)))
          else if (_slots.isEmpty)
            _emptyState(Icons.access_time, 'No Time Slots Available',
                'There are no open slots on the selected date. Try choosing another day.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _slots.map((slot) {
                final id = slot['slotId'];
                final status = slot['status'];
                final isSelected = _selectedSlotId == id;
                final isAvailable = status == 'AVAILABLE';
                final startTime = (slot['startTime'] ?? '').toString();
                final label = startTime.length >= 5 ? startTime.substring(0, 5) : startTime;
                return GestureDetector(
                  onTap: isAvailable ? () => _selectSlot(id) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: !isAvailable
                          ? const Color(0xFFF3F4F6)
                          : (isSelected ? AppTheme.primaryTeal : Colors.white),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryTeal : AppTheme.borderGray.withValues(alpha: 0.8),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(label,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: !isAvailable
                                    ? AppTheme.textMuted
                                    : (isSelected ? Colors.white : AppTheme.textMain))),
                        if (!isAvailable)
                          Text(status == 'BOOKED' ? 'Booked' : 'Blocked',
                              style: const TextStyle(fontSize: 9, color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ],
    );
  }

  // ── STEP 4: Confirm & Book ───────────────────────────────────────────────
  Widget _buildStep4(bool isMobile) {
    final doctor = _selectedDoctor;
    final clinic = _selectedClinic;
    final slot = _selectedSlot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepTitle(
          Icons.fact_check_outlined,
          'Step 4: Confirm & Book',
          'Provide appointment reason and choose session mode to book consultation',
        ),
        const SizedBox(height: 14),
        if (doctor != null && clinic != null)
          _receiptCard(doctor, clinic, slot),
        const SizedBox(height: 16),
        const Text('Session Mode *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _modeCard(
                icon: Icons.local_hospital_outlined,
                title: 'In Clinic',
                desc: 'Visit doctor physically at selected branch.',
                selected: _selectedSessionType == 'IN_CLINIC',
                onTap: () => setState(() => _selectedSessionType = 'IN_CLINIC'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _modeCard(
                icon: Icons.videocam_outlined,
                title: 'Virtual',
                desc: 'Consult online via text chat and files.',
                selected: _selectedSessionType == 'VIRTUAL',
                onTap: () => setState(() => _selectedSessionType = 'VIRTUAL'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Appointment Type *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _typeCard(
                title: 'New Patient',
                desc: 'First checkup for this issue.',
                selected: _selectedApptType == 'NEW_PATIENT',
                onTap: () => setState(() => _selectedApptType = 'NEW_PATIENT'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _typeCard(
                title: 'Follow Up',
                desc: 'Routine test review.',
                selected: _selectedApptType == 'FOLLOW_UP',
                onTap: () => setState(() => _selectedApptType = 'FOLLOW_UP'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Reason for Visit / Symptoms', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
        const SizedBox(height: 8),
        TextField(
          controller: _reasonController,
          maxLines: 3,
          maxLength: 255,
          decoration: const InputDecoration(
            hintText: 'Type short reasons or symptoms...',
            hintStyle: TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _receiptCard(DoctorModel doctor, DoctorClinicModel clinic, dynamic slot) {
    final avatarUrl = _resolveUrl(doctor.avatarUrl);
    final colorIdx = _colorIndex(doctor.fullName);
    final startTime = slot != null ? (slot['startTime'] ?? '').toString() : '';
    final timeLabel = startTime.length >= 5 ? startTime.substring(0, 5) : startTime;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF115E59)],
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.receipt_long_outlined, size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text('Consultation Summary',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _receiptRow(
                  Icons.person_search_rounded,
                  'Doctor',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: _C.avatarBg[colorIdx],
                        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl == null
                            ? Text(_initialsOf(doctor.fullName),
                                style: TextStyle(
                                    fontSize: 9, color: _C.avatarFg[colorIdx], fontWeight: FontWeight.bold))
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(_doctorDisplayName(doctor.fullName),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 18),
                _receiptRow(
                  Icons.local_hospital_outlined,
                  'Clinic Branch',
                  value: '${clinic.clinicNameEn ?? clinic.department} - ${clinic.branchNameEn ?? ''}',
                ),
                const Divider(height: 18),
                _receiptRow(
                  Icons.calendar_month_outlined,
                  'Date & Time',
                  value: '${_selectedDate ?? ''} @ $timeLabel',
                ),
                const Divider(height: 18),
                _receiptRow(
                  Icons.attach_money_rounded,
                  'Consultation Fee',
                  value: 'SAR ${_fmtFee(clinic.consultationFeeSar)}',
                  valueColor: const Color(0xFF059669),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptRow(IconData icon, String label,
      {String? value, Widget? trailing, Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.textMuted),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(width: 12),
        if (trailing != null)
          Expanded(child: Align(alignment: Alignment.centerRight, child: trailing))
        else
          Expanded(
            child: Text(value ?? '',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: valueColor ?? AppTheme.textMain),
                overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }

  Widget _modeCard({
    required IconData icon,
    required String title,
    required String desc,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryLightTeal : AppTheme.surfaceWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppTheme.primaryTeal : AppTheme.borderGray.withValues(alpha: 0.8),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppTheme.primaryTeal, size: 18),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            Text(desc, style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _typeCard({
    required String title,
    required String desc,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryLightTeal : AppTheme.surfaceWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppTheme.primaryTeal : AppTheme.borderGray.withValues(alpha: 0.8),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 2),
            Text(desc, style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _stepTitle(IconData icon, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.primaryTeal),
            const SizedBox(width: 6),
            Expanded(
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
      ],
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.8)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppTheme.textMuted),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  // ── Bottom Navigation Bar ────────────────────────────────────────────────
  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        border: Border(top: BorderSide(color: AppTheme.borderGray.withValues(alpha: 0.8))),
      ),
      child: Row(
        children: [
          if (_currentStep > 1) ...[
            OutlinedButton(
              onPressed: () => _goToStep(_currentStep - 1),
              child: const Text('Back'),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: _currentStep == 4
                ? ElevatedButton(
                    onPressed: (_canSubmit && !_isSubmitting) ? _confirmBooking : null,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Confirm & Book Appointment'),
                  )
                : ElevatedButton(
                    onPressed: _canAdvance() ? () => _goToStep(_currentStep + 1) : null,
                    child: const Text('Next'),
                  ),
          ),
        ],
      ),
    );
  }

  bool _canAdvance() {
    if (_currentStep == 1) return _selectedDoctorId != null;
    if (_currentStep == 2) return _selectedDcId != null;
    if (_currentStep == 3) return _selectedDate != null && _selectedSlotId != null;
    return true;
  }
}

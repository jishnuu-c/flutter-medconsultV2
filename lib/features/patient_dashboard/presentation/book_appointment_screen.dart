import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/references_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/clinic_service.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../clinic_admin/data/doctor_models.dart';
import '../../doctor_dashboard/data/appointment_service.dart';
import '../data/patient_service.dart';

// Extra brand tokens from styles.css not yet in AppTheme. Mirrors the
// palette used by patient_doctors_screen.dart so both screens read as one
// coherent design system.
class _C {
  static const tealDark = Color(0xFF085041);
  static const tealLight = Color(0xFFE1F5EE);
  static const off = Color(0xFFF8FAF9);
  static const t3 = Color(0xFF6B7280);
  static const feeBg = Color(0xFFECFDF5);
  static const feeText = Color(0xFF065F46);

  static const avatarBg = [
    Color(0xFFE1F5EE),
    Color(0xFFDBEAFE),
    Color(0xFFEDE9FE),
    Color(0xFFFEF3C7),
    Color(0xFFDCFCE7),
  ];
  static const avatarFg = [
    Color(0xFF085041),
    Color(0xFF1E40AF),
    Color(0xFF5B21B6),
    Color(0xFF92400E),
    Color(0xFF166534),
  ];
}

/// Turns a relative avatar/logo path into an absolute URL, same rule used
/// across the app (patient_doctors_screen._resolveAvatarUrl / app_layout).
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
    this.hasSlots = true,
  });
}

/// Mirrors Angular's book-appointment.component 1:1 — a 4-step wizard
/// (Doctor → Clinic → Date & Time → Confirm), laid out for a phone screen:
/// single column, stacked selection cards, and a sticky bottom nav bar
/// instead of the desktop side-by-side footer.
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

  // ── Data loading (mirrors ngOnInit → checkProfileAndLoad → loadDoctors) ──

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

  // ── Filtering & sorting (mirrors get filteredDoctors()) ─────────────────

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

  // ── Step transitions (mirrors selectDoctor / selectClinic / selectDate…) ─

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
                : 'Unknown Branch',
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

  // ── Selected-item lookups (mirrors getSelectedDoctor/Clinic/Slot) ───────

  DoctorModel? get _selectedDoctor => _selectedDoctorId == null
      ? null
      : _doctors.where((d) => d.doctorId == _selectedDoctorId).firstOrNull;

  DoctorClinicModel? get _selectedClinic => _selectedDcId == null
      ? null
      : _doctorClinics.where((c) => c.dcId == _selectedDcId).firstOrNull;

  dynamic get _selectedSlot => _selectedSlotId == null
      ? null
      : _slots.where((s) => s['slotId'] == _selectedSlotId).firstOrNull;

  // ── Display helpers (mirror getDoctorDisplayName/getInitials/getAvatarBg) ─

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
    if (parts.length >= 2)
      return (parts.first[0] + parts.last[0]).toUpperCase();
    return name
        .trim()
        .substring(0, name.trim().length.clamp(0, 2))
        .toUpperCase();
  }

  int _colorIndex(String name) {
    var sum = 0;
    for (final code in name.codeUnits) sum += code;
    return sum % _C.avatarBg.length;
  }

  String _fmtFee(double fee) => fee == fee.roundToDouble()
      ? fee.toInt().toString()
      : fee.toStringAsFixed(2);

  // ── Submit (mirrors onSubmit) ────────────────────────────────────────────

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appointment booked successfully!')),
        );
        context.go('/patient/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_extractErrorMessage(e))));
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

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_needProfileInit) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
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
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
      );
    }

    return Scaffold(
      backgroundColor: _C.off,
      body: SafeArea(
        child: (_isLoading && _doctors.isEmpty)
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 16),
                          _buildStepNav(),
                          const SizedBox(height: 20),
                          if (_currentStep == 1) _buildStep1(),
                          if (_currentStep == 2) _buildStep2(),
                          if (_currentStep == 3) _buildStep3(),
                          if (_currentStep == 4) _buildStep4(),
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

  // ── Header ────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _C.tealLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child:
              const Icon(Icons.event_note_rounded, color: AppTheme.primaryTeal),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Schedule Your Consultation',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMain)),
              const SizedBox(height: 2),
              const Text(
                'Select your preferred doctor, clinic branch, and appointment slot',
                style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step nav (mirrors booking-wizard-steps) ──────────────────────────────

  Widget _buildStepNav() {
    const labels = ['Doctor', 'Clinic', 'Date & Time', 'Confirm'];
    return Row(
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
                            ? _C.tealLight
                            : AppTheme.borderGray),
                    child: i < _currentStep
                        ? const Icon(Icons.check,
                            size: 14, color: AppTheme.primaryTeal)
                        : Text('$i',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: i == _currentStep
                                    ? Colors.white
                                    : AppTheme.textMuted)),
                  ),
                  const SizedBox(height: 4),
                  Text(labels[i - 1],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: i == _currentStep
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: i == _currentStep
                              ? AppTheme.primaryTeal
                              : AppTheme.textMuted)),
                ],
              ),
            ),
          ),
          if (i != 4)
            const Padding(
              padding: EdgeInsets.only(bottom: 18),
              child: Text('›',
                  style: TextStyle(color: AppTheme.borderGray, fontSize: 16)),
            ),
        ],
      ],
    );
  }

  // ── STEP 1: choose doctor ────────────────────────────────────────────────

  Widget _buildStep1() {
    final filtered = _filteredDoctors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepTitle(
            Icons.person_search_rounded,
            'Step 1: Choose Specialist Doctor',
            'Browse our verified doctors panel and select a specialist to check clinic locations'),
        const SizedBox(height: 14),
        _filtersCard(),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          _emptyState(Icons.person_search_rounded, 'No Doctors Found',
              'No medical experts match your search query.')
        else
          Column(children: filtered.map((doc) => _doctorCard(doc)).toList()),
      ],
    );
  }

  Widget _filtersCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Search Doctor Name',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _C.t3)),
          const SizedBox(height: 6),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: const InputDecoration(
              hintText: 'Type to search...',
              isDense: true,
              suffixIcon: Icon(Icons.search, size: 18),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Medical Specialty',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _C.t3)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _selectedSpecialtyId,
            isExpanded: true,
            decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
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
                    const Text('Years of Experience',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _C.t3)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedMinExperience,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10)),
                      items: const [
                        DropdownMenuItem(
                            value: 0, child: Text('Any Experience')),
                        DropdownMenuItem(value: 3, child: Text('3+ Years')),
                        DropdownMenuItem(value: 5, child: Text('5+ Years')),
                        DropdownMenuItem(value: 10, child: Text('10+ Years')),
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
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _C.t3)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedSortOption,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10)),
                      items: const [
                        DropdownMenuItem(
                            value: 'rating', child: Text('Highest Rating')),
                        DropdownMenuItem(
                            value: 'experience',
                            child: Text('Most Experienced')),
                        DropdownMenuItem(
                            value: 'fee_asc', child: Text('Fee: Low to High')),
                        DropdownMenuItem(
                            value: 'fee_desc', child: Text('Fee: High to Low')),
                        DropdownMenuItem(
                            value: 'name', child: Text('Name (A-Z)')),
                      ],
                      onChanged: (v) =>
                          setState(() => _selectedSortOption = v ?? 'rating'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                    '${_filteredDoctors.length} doctors found matching criteria',
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: _C.t3,
                        fontWeight: FontWeight.w500)),
              ),
              if (_searchQuery.isNotEmpty ||
                  _selectedSpecialtyId.isNotEmpty ||
                  _selectedMinExperience > 0 ||
                  _selectedSortOption != 'rating')
                TextButton.icon(
                  onPressed: _resetFilters,
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                  icon: const Icon(Icons.refresh, size: 13),
                  label: const Text('Reset Filters',
                      style: TextStyle(fontSize: 11.5)),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: alreadyBooked ? null : () => _selectDoctor(doc.doctorId),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: alreadyBooked
                  ? const Color(0xFFF9FAFB)
                  : (selected ? _C.tealLight : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: selected ? AppTheme.primaryTeal : AppTheme.borderGray),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
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
                                  fontSize: 13))
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_doctorDisplayName(doc.fullName),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14.5)),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _C.tealLight,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(specialtyName,
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    color: _C.tealDark,
                                    fontWeight: FontWeight.w600)),
                          ),
                          if (!alreadyBooked) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text('${doc.experienceYears} Yrs Exp',
                                    style: const TextStyle(
                                        fontSize: 11.5, color: _C.t3)),
                                const SizedBox(width: 6),
                                const Text('•',
                                    style:
                                        TextStyle(color: _C.t3, fontSize: 11)),
                                const SizedBox(width: 6),
                                const Icon(Icons.star,
                                    size: 13, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 2),
                                Text(
                                    '${doc.overallRating} (${doc.reviewCount})',
                                    style: const TextStyle(
                                        fontSize: 11.5, color: _C.t3)),
                              ],
                            ),
                          ] else ...[
                            const SizedBox(height: 6),
                            Row(
                              children: const [
                                Icon(Icons.info_outline,
                                    size: 13, color: AppTheme.warningAmber),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                      'Active booking exists with this doctor',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.warningAmber)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_circle,
                          color: AppTheme.primaryTeal, size: 20),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _C.feeBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                            'Fee: SAR ${_fmtFee(doc.consultationFeeSar)}',
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: _C.feeText,
                                fontWeight: FontWeight.w700)),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            context.push('/doctors/${doc.doctorId}'),
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 0)),
                        icon:
                            const Icon(Icons.remove_red_eye_outlined, size: 14),
                        label: const Text('View Profile',
                            style: TextStyle(fontSize: 11.5)),
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

  // ── STEP 2: choose clinic ────────────────────────────────────────────────

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepTitle(
            Icons.local_hospital_outlined,
            'Step 2: Choose Clinic Location',
            'Select from the branch locations where this doctor is currently practicing'),
        const SizedBox(height: 14),
        if (_isLoading)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator()))
        else if (_doctorClinics.isEmpty)
          _emptyState(Icons.local_hospital_outlined, 'No Branches Registered',
              'This doctor is not assigned to any active clinic branch locations.')
        else
          Column(
              children: _doctorClinics.map((dc) => _clinicCard(dc)).toList()),
      ],
    );
  }

  Widget _clinicCard(DoctorClinicModel dc) {
    final selected = _selectedDcId == dc.dcId;
    return GestureDetector(
      onTap: () => _selectClinic(dc.dcId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? _C.tealLight : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppTheme.primaryTeal : AppTheme.borderGray),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _C.tealLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.location_on_outlined,
                  color: AppTheme.primaryTeal),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(dc.clinicNameEn ?? dc.department,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14.5),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (dc.isPrimary)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _C.tealLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Primary',
                              style: TextStyle(
                                  fontSize: 9.5,
                                  color: _C.tealDark,
                                  fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 13, color: _C.t3),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(dc.branchNameEn ?? '',
                            style: const TextStyle(fontSize: 12, color: _C.t3),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(dc.department,
                            style: const TextStyle(
                                fontSize: 10.5,
                                color: _C.t3,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _C.feeBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${_fmtFee(dc.consultationFeeSar)} SAR',
                            style: const TextStyle(
                                fontSize: 10.5,
                                color: _C.feeText,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.check_circle,
                    color: AppTheme.primaryTeal, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  // ── STEP 3: date & slot ──────────────────────────────────────────────────

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepTitle(
            Icons.calendar_month_outlined,
            'Step 3: Appointment Date & Time',
            'Select a booking date to see available consultation time slots'),
        const SizedBox(height: 14),
        const Text('Select Date',
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: _C.t3)),
        const SizedBox(height: 8),
        SizedBox(
          height: 74,
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
                  width: 60,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.primaryTeal : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: selected
                            ? AppTheme.primaryTeal
                            : AppTheme.borderGray),
                  ),
                  child: Opacity(
                    opacity: noSlots ? 0.45 : 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(day.dayName,
                            style: TextStyle(
                                fontSize: 10.5,
                                color: selected ? Colors.white70 : _C.t3)),
                        const SizedBox(height: 2),
                        Text(day.dayNum,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: selected
                                    ? Colors.white
                                    : AppTheme.textMain)),
                        Text(day.monthName,
                            style: TextStyle(
                                fontSize: 10,
                                color: selected ? Colors.white70 : _C.t3)),
                        if (noSlots) ...[
                          const SizedBox(height: 2),
                          Text('No Slots',
                              style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF94A3B8))),
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
          icon: const Icon(Icons.calendar_today, size: 15),
          label: Text(
              _selectedDate == null ? 'Or choose any date' : _selectedDate!),
        ),
        if (_selectedDate != null) ...[
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 10),
          Row(
            children: const [
              Icon(Icons.access_time, size: 15, color: AppTheme.textMain),
              SizedBox(width: 5),
              Text('Available Slots',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          if (_isLoading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator()))
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
                final label = startTime.length >= 5
                    ? startTime.substring(0, 5)
                    : startTime;
                return GestureDetector(
                  onTap: isAvailable ? () => _selectSlot(id) : null,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: !isAvailable
                          ? const Color(0xFFF3F4F6)
                          : (isSelected ? AppTheme.primaryTeal : Colors.white),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: isSelected
                              ? AppTheme.primaryTeal
                              : AppTheme.borderGray),
                    ),
                    child: Column(
                      children: [
                        Text(label,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: !isAvailable
                                    ? AppTheme.textMuted
                                    : (isSelected
                                        ? Colors.white
                                        : AppTheme.textMain))),
                        if (!isAvailable)
                          Text(status == 'BOOKED' ? 'Booked' : 'Blocked',
                              style: const TextStyle(
                                  fontSize: 9, color: AppTheme.textMuted)),
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

  // ── STEP 4: confirm & book ───────────────────────────────────────────────

  Widget _buildStep4() {
    final doctor = _selectedDoctor;
    final clinic = _selectedClinic;
    final slot = _selectedSlot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepTitle(Icons.fact_check_outlined, 'Step 4: Confirm & Book',
            'Provide appointment reason and choose session mode to book consultation'),
        const SizedBox(height: 14),
        if (doctor != null && clinic != null)
          _receiptCard(doctor, clinic, slot),
        const SizedBox(height: 16),
        const Text('Session Mode *',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _modeCard(
                icon: Icons.local_hospital_outlined,
                title: 'In Clinic',
                desc:
                    'Visit the doctor physically at the selected branch location.',
                selected: _selectedSessionType == 'IN_CLINIC',
                onTap: () => setState(() => _selectedSessionType = 'IN_CLINIC'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _modeCard(
                icon: Icons.videocam_outlined,
                title: 'Virtual',
                desc: 'Consult online via text chat and attachments upload.',
                selected: _selectedSessionType == 'VIRTUAL',
                onTap: () => setState(() => _selectedSessionType = 'VIRTUAL'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text('Appointment Type *',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _typeCard(
                title: 'New Patient',
                desc:
                    'First consultation for this specific illness or checkup.',
                selected: _selectedApptType == 'NEW_PATIENT',
                onTap: () => setState(() => _selectedApptType = 'NEW_PATIENT'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _typeCard(
                title: 'Follow Up',
                desc: 'Routine diagnostic checkup or continuous test reviews.',
                selected: _selectedApptType == 'FOLLOW_UP',
                onTap: () => setState(() => _selectedApptType = 'FOLLOW_UP'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text('Reason for Visit / Symptoms',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        const SizedBox(height: 8),
        TextField(
          controller: _reasonController,
          maxLines: 3,
          maxLength: 255,
          decoration: const InputDecoration(
              hintText: 'Type short reasons or symptoms...'),
        ),
      ],
    );
  }

  Widget _receiptCard(
      DoctorModel doctor, DoctorClinicModel clinic, dynamic slot) {
    final avatarUrl = _resolveUrl(doctor.avatarUrl);
    final colorIdx = _colorIndex(doctor.fullName);
    final startTime = slot != null ? (slot['startTime'] ?? '').toString() : '';
    final timeLabel =
        startTime.length >= 5 ? startTime.substring(0, 5) : startTime;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: AppTheme.primaryTeal,
            child: Row(
              children: const [
                Icon(Icons.receipt_long_outlined,
                    size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text('Consultation Details Summary',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5)),
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
                        backgroundImage:
                            avatarUrl != null ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl == null
                            ? Text(_initialsOf(doctor.fullName),
                                style: TextStyle(
                                    fontSize: 9,
                                    color: _C.avatarFg[colorIdx],
                                    fontWeight: FontWeight.bold))
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(_doctorDisplayName(doctor.fullName),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12.5),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 20),
                _receiptRow(Icons.local_hospital_outlined, 'Clinic Branch',
                    value:
                        '${clinic.clinicNameEn ?? clinic.department} - ${clinic.branchNameEn ?? ''}'),
                const Divider(height: 20),
                _receiptRow(Icons.calendar_month_outlined, 'Date & Time',
                    value: '${_selectedDate ?? ''} @ $timeLabel'),
                const Divider(height: 20),
                _receiptRow(Icons.attach_money_rounded, 'Consultation Fee',
                    value: 'SAR ${_fmtFee(clinic.consultationFeeSar)}',
                    valueColor: AppTheme.successGreen),
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
          children: [
            Icon(icon, size: 14, color: _C.t3),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: _C.t3, fontWeight: FontWeight.w500)),
          ],
        ),
        const Spacer(),
        if (trailing != null)
          trailing
        else
          Flexible(
            child: Text(value ?? '',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
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
          color: selected ? _C.tealLight : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppTheme.primaryTeal : AppTheme.borderGray),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppTheme.primaryTeal, size: 20),
            const SizedBox(height: 8),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 3),
            Text(desc, style: const TextStyle(fontSize: 10.5, color: _C.t3)),
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
          color: selected ? _C.tealLight : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppTheme.primaryTeal : AppTheme.borderGray),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 3),
            Text(desc, style: const TextStyle(fontSize: 10.5, color: _C.t3)),
          ],
        ),
      ),
    );
  }

  // ── Shared small pieces ──────────────────────────────────────────────────

  Widget _stepTitle(IconData icon, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.primaryTeal),
            const SizedBox(width: 6),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15.5)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: _C.t3)),
      ],
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: AppTheme.borderGray),
          const SizedBox(height: 10),
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: _C.t3)),
        ],
      ),
    );
  }

  // ── Bottom sticky navigation bar ─────────────────────────────────────────

  Widget _buildBottomBar() {
    Widget? primary;
    switch (_currentStep) {
      case 2:
        primary = _doctorClinics.isEmpty
            ? null
            : ElevatedButton.icon(
                onPressed: _selectedDcId != null ? () => _goToStep(3) : null,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('Next'),
              );
        break;
      case 3:
        primary = ElevatedButton.icon(
          onPressed: _selectedSlotId != null ? () => _goToStep(4) : null,
          icon: const Icon(Icons.arrow_forward, size: 16),
          label: const Text('Next'),
        );
        break;
      case 4:
        primary = ElevatedButton.icon(
          onPressed: (_isSubmitting || !_canSubmit) ? null : _confirmBooking,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_outline, size: 16),
          label: const Text('Confirm & Book Appointment'),
        );
        break;
      default:
        primary = null;
    }

    if (_currentStep == 1 && primary == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.borderGray)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentStep > 1)
              OutlinedButton.icon(
                onPressed: () => _goToStep(_currentStep - 1),
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Back'),
              ),
            const Spacer(),
            if (primary != null) primary,
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

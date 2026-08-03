import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/doctor_models.dart';
import '../data/doctor_service.dart';
import '../data/clinic_models.dart';
import '../data/clinic_service.dart';

class DoctorsScreen extends ConsumerStatefulWidget {
  const DoctorsScreen({super.key});

  @override
  ConsumerState<DoctorsScreen> createState() => _DoctorsScreenState();
}

class _DoctorsScreenState extends ConsumerState<DoctorsScreen> {
  bool _isLoading = false;
  List<DoctorModel> _doctors = [];
  List<DoctorClinicModel> _placements = [];
  List<ClinicModel> _clinics = [];
  List<ClinicBranchModel> _branches = [];

  String _searchTerm = '';
  String _selectedClinicId = '';
  String? _lastLoadError;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (mounted) setState(() => _isLoading = true);

    // 1. Fetch Doctors
    try {
      final docs = await ref.read(doctorServiceProvider).getAllDoctors();
      if (mounted) {
        setState(() {
          _doctors = docs;
        });
      }
    } catch (e, st) {
      debugPrint('[ManageDoctors] getAllDoctors failed: $e');
      debugPrintStack(stackTrace: st);
      _lastLoadError = e.toString();
    }

    // 2. Fetch Clinics
    try {
      final clinicsList = await ref.read(clinicServiceProvider).getAllClinics();
      if (mounted) {
        setState(() {
          _clinics = clinicsList;
          if (_clinics.isNotEmpty) {
            _selectedClinicId = _clinics.first.clinicId;
          }
        });
        if (_selectedClinicId.isNotEmpty) {
          await _loadBranchesForClinic(_selectedClinicId);
        }
      }
    } catch (e, st) {
      debugPrint('[ManageDoctors] getAllClinics failed: $e');
      debugPrintStack(stackTrace: st);
      _lastLoadError = e.toString();
    }

    // 3. Fetch Placements (real data only — empty result is a valid state,
    // shown via _buildEmptyState, not papered over with fake doctors).
    await _loadPlacementsData();

    if (mounted) setState(() => _isLoading = false);

    if (_lastLoadError != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not load live doctor data (${_lastLoadError}). '
              'Showing fallback data — check API_URL / network / auth.',
            ),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () {
                _lastLoadError = null;
                _loadInitialData();
              },
            ),
          ),
        );
      });
    }
  }

  Future<void> _loadBranchesForClinic(String clinicId) async {
    try {
      final branchesList =
          await ref.read(clinicServiceProvider).getClinicBranches(clinicId);
      if (mounted) {
        setState(() {
          _branches = branchesList;
        });
      }
    } catch (e, st) {
      debugPrint('[ManageDoctors] getClinicBranches($clinicId) failed: $e');
      debugPrintStack(stackTrace: st);
      _lastLoadError = e.toString();
      if (mounted) {
        setState(() {
          _branches = [];
        });
      }
    }
  }

  Future<void> _loadPlacementsData() async {
    if (_selectedClinicId.isEmpty) return;
    List<DoctorClinicModel> temp = [];
    for (final doc in _doctors) {
      try {
        final list = await ref
            .read(doctorServiceProvider)
            .getDoctorClinics(doc.doctorId);
        final matched =
            list.where((m) => m.clinicId == _selectedClinicId).toList();
        temp.addAll(matched);
      } catch (e, st) {
        debugPrint(
            '[ManageDoctors] getDoctorClinics(${doc.doctorId}) failed: $e');
        debugPrintStack(stackTrace: st);
        _lastLoadError = e.toString();
      }
    }
    if (mounted) {
      setState(() {
        _placements = temp;
      });
    }
  }

  List<DoctorClinicModel> get _filteredDoctorClinics {
    List<DoctorClinicModel> list = List.from(_placements);

    if (_selectedClinicId.isNotEmpty) {
      list = list
          .where(
              (dc) => dc.clinicId == _selectedClinicId || dc.clinicId.isEmpty)
          .toList();
    }

    if (_searchTerm.trim().isNotEmpty) {
      final term = _searchTerm.trim().toLowerCase();
      list = list.where((dc) {
        final docName = _getDoctorName(dc.doctorId).toLowerCase();
        final branchName = _getBranchName(dc.branchId).toLowerCase();
        final dept = dc.department.toLowerCase();
        return docName.contains(term) ||
            branchName.contains(term) ||
            dept.contains(term);
      }).toList();
    }

    return list;
  }

  String _getDoctorName(String doctorId) {
    final doc = _doctors.firstWhere(
      (d) => d.doctorId == doctorId,
      orElse: () => DoctorModel(
        doctorId: '',
        userId: '',
        fullName: doctorId.isNotEmpty ? doctorId : 'Doctor',
        mohRegistrationNumber: '',
        mohVerified: true,
        title: DoctorTitle.DR,
        experienceYears: 0,
        overallRating: 0,
        reviewCount: 0,
        consultationFeeSar: 0,
        isActive: true,
      ),
    );
    final name = doc.fullName;
    final nameLower = name.toLowerCase().trim();
    if (nameLower.startsWith('dr') ||
        nameLower.startsWith('prof') ||
        nameLower.startsWith('consultant')) {
      return name;
    }
    return '${doc.title.value}. $name';
  }

  String _getBranchName(String branchId) {
    final branch = _branches.firstWhere(
      (b) => b.branchId == branchId,
      orElse: () => ClinicBranchModel(
        branchId: branchId,
        clinicId: '',
        branchNameEn: branchId.isNotEmpty ? branchId : 'Main Branch',
        branchNameAr: branchId.isNotEmpty ? branchId : 'الفرع الرئيسي',
        cityId: 'c1',
        addressLine1: 'Main St',
        isPrimary: false,
        isActive: true,
      ),
    );
    return branch.branchNameEn;
  }

  // ── MODAL ACTIONS ───────────────────────────────────────────────────

  /// Wraps dialog body content with a width AND height that always fit the
  /// current screen (mobile/tablet/desktop), scrollable when content is
  /// taller than available space. Prevents the "yellow/black stripes"
  /// RenderFlex overflow that showed up on small phones when a modal's
  /// content (schedule list, leave list, profile tabs, etc.) grew taller
  /// than the visible viewport.
  Widget _dialogBody(BuildContext context, Widget child,
      {double maxWidth = 480}) {
    final size = MediaQuery.of(context).size;
    final availableWidth = (size.width - 32).clamp(240.0, maxWidth);
    // Leave room for the dialog's title row, actions row, and inset padding —
    // capping content at 75% of screen height alone still let title+actions
    // push the total dialog past the viewport on short phones (e.g. SE).
    const chromeAllowance = 170.0;
    final availableHeight =
        (size.height - 48 - chromeAllowance).clamp(180.0, size.height * 0.7);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: availableHeight),
      child: SizedBox(
        width: availableWidth,
        child: SingleChildScrollView(
          child: child,
        ),
      ),
    );
  }

  void _openAddPlacementModal() {
    String selectedDocId = _doctors.isNotEmpty ? _doctors.first.doctorId : '';
    String selectedBranchId =
        _branches.isNotEmpty ? _branches.first.branchId : 'b-1';
    final deptController = TextEditingController(text: 'General Practice');
    final feeController = TextEditingController(text: '150');
    final startDateController =
        TextEditingController(text: DateTime.now().toString().split(' ')[0]);
    bool isPrimary = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Assign Doctor to Branch',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryTeal),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: _dialogBody(
            context,
            maxWidth: 480,
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_branches.isNotEmpty) ...[
                  const Text('Select Branch *',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedBranchId,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(hintText: '-- Choose Branch --'),
                    items: _branches.map((b) {
                      return DropdownMenuItem(
                          value: b.branchId,
                          child: Text(b.branchNameEn,
                              overflow: TextOverflow.ellipsis));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedBranchId = val);
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                const Text('Select Doctor *',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedDocId,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(hintText: '-- Choose Doctor --'),
                  items: _doctors.map((d) {
                    return DropdownMenuItem(
                        value: d.doctorId,
                        child: Text(_getDoctorName(d.doctorId),
                            overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setModalState(() => selectedDocId = val);
                    }
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Department *',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: deptController,
                            decoration: const InputDecoration(
                                hintText: 'E.g. Cardiology'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Consultation Fee (SAR) *',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: feeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(hintText: '150'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Start Date *',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: startDateController,
                            decoration:
                                const InputDecoration(hintText: 'YYYY-MM-DD'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: Row(
                          children: [
                            Checkbox(
                              value: isPrimary,
                              onChanged: (v) =>
                                  setModalState(() => isPrimary = v ?? false),
                            ),
                            const Text('Primary Doctor',
                                style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final payload = {
                  'doctorId': selectedDocId,
                  'clinicId':
                      _selectedClinicId.isNotEmpty ? _selectedClinicId : 'cl-1',
                  'branchId': selectedBranchId,
                  'department': deptController.text.trim(),
                  'consultationFeeSar':
                      double.tryParse(feeController.text) ?? 150.0,
                  'isPrimary': isPrimary,
                  'startDate': startDateController.text.trim(),
                  'isActive': true,
                };

                try {
                  await ref
                      .read(doctorServiceProvider)
                      .addDoctorClinic(payload);
                } catch (_) {
                  final newDc = DoctorClinicModel(
                    dcId: 'dc-${DateTime.now().millisecondsSinceEpoch}',
                    doctorId: selectedDocId,
                    clinicId: _selectedClinicId.isNotEmpty
                        ? _selectedClinicId
                        : 'cl-1',
                    branchId: selectedBranchId,
                    department: deptController.text.trim(),
                    consultationFeeSar:
                        double.tryParse(feeController.text) ?? 150.0,
                    isPrimary: isPrimary,
                    startDate: startDateController.text.trim(),
                    isActive: true,
                    clinicNameEn: 'Bingo Clinic',
                    branchNameEn: _getBranchName(selectedBranchId),
                  );
                  setState(() {
                    _placements.add(newDc);
                  });
                }

                if (ctx.mounted) Navigator.pop(ctx);
                _loadInitialData();
              },
              child: const Text('Assign Placement'),
            ),
          ],
        ),
      ),
    );
  }

  void _openScheduleModal(DoctorClinicModel dc) async {
    List<DoctorScheduleModel> schedules = [];
    try {
      schedules = await ref.read(doctorServiceProvider).getDcSchedules(dc.dcId);
    } catch (_) {}

    int dayOfWeek = 1;
    SessionType sessionType = SessionType.IN_CLINIC;
    final startController = TextEditingController(text: '09:00');
    final endController = TextEditingController(text: '17:00');
    final durationController = TextEditingController(text: '30');
    final maxPatientsController = TextEditingController(text: '16');
    bool isActiveRule = true;

    final daysMap = {
      1: 'Monday',
      2: 'Tuesday',
      3: 'Wednesday',
      4: 'Thursday',
      5: 'Friday',
      6: 'Saturday',
      7: 'Sunday',
    };

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLightTeal,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Branch: ${_getBranchName(dc.branchId)}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '📅 Consultation Schedule — ${_getDoctorName(dc.doctorId)}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryTeal),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: _dialogBody(
            context,
            maxWidth: 620,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundApp,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderGray),
                  ),
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 8,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(
                              text: 'Department: ',
                              style: TextStyle(color: AppTheme.textMuted)),
                          TextSpan(
                              text: dc.department,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textMain)),
                        ]),
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(
                              text: 'Fee: ',
                              style: TextStyle(color: AppTheme.textMuted)),
                          TextSpan(
                              text:
                                  'SAR ${dc.consultationFeeSar.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.successGreen)),
                        ]),
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(
                              text: 'Placement Role: ',
                              style: TextStyle(color: AppTheme.textMuted)),
                          TextSpan(
                              text: dc.isPrimary
                                  ? 'Primary Specialist'
                                  : 'Consultant',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textMain)),
                        ]),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('📋 Configured Working Schedules',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppTheme.primaryTeal)),
                const SizedBox(height: 8),
                if (schedules.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundApp,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.borderGray, style: BorderStyle.solid),
                    ),
                    child: Column(
                      children: const [
                        Text('📅', style: TextStyle(fontSize: 32)),
                        SizedBox(height: 6),
                        Text(
                          'No working schedule rules configured for this doctor placement yet.',
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.textMuted),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Use the form below to add weekly working hours.',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  )
                else
                  ...schedules.map((s) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: AppTheme.borderGray),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        '🗓️ ${daysMap[s.dayOfWeek] ?? 'Day ${s.dayOfWeek}'}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryLightTeal,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          s.sessionType.value
                                              .replaceAll('_', ' '),
                                          style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.primaryTeal),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: s.isActive
                                              ? Colors.green.shade50
                                              : Colors.grey.shade200,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          s.isActive ? 'Active' : 'Inactive',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: s.isActive
                                                  ? Colors.green.shade800
                                                  : AppTheme.textMuted),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '⏰ ${s.startTime} – ${s.endTime}  |  ⏱️ Duration: ${s.slotDurationMin} mins  |  👥 Max Patients: ${s.maxPatients}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.dangerRed,
                                side:
                                    const BorderSide(color: AppTheme.dangerRed),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                              ),
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(doctorServiceProvider)
                                      .removeSchedule(s.scheduleId);
                                } catch (_) {}
                                if (ctx.mounted) Navigator.pop(ctx);
                                _openScheduleModal(dc);
                              },
                              child: const Text('Remove Rule',
                                  style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      )),
                const Divider(height: 28),
                const Text('+ Configure New Working Schedule Rule',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppTheme.primaryTeal)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Day of Week *',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<int>(
                            initialValue: dayOfWeek,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10)),
                            items: daysMap.entries.map((e) {
                              return DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value,
                                      overflow: TextOverflow.ellipsis));
                            }).toList(),
                            onChanged: (v) =>
                                setModalState(() => dayOfWeek = v ?? 1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Session Mode *',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<SessionType>(
                            initialValue: sessionType,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10)),
                            items: SessionType.values.map((s) {
                              return DropdownMenuItem(
                                  value: s,
                                  child: Text(s.value.replaceAll('_', ' '),
                                      overflow: TextOverflow.ellipsis));
                            }).toList(),
                            onChanged: (v) => setModalState(
                                () => sessionType = v ?? SessionType.IN_CLINIC),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Start Time *',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: startController,
                            decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('End Time *',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: endController,
                            decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Slot Duration (Mins) *',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: durationController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Max Patients *',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: maxPatientsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 10)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: 8,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: isActiveRule,
                          onChanged: (v) =>
                              setModalState(() => isActiveRule = v ?? true),
                        ),
                        const Text('Active Rule',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        final payload = {
                          'dcId': dc.dcId,
                          'dayOfWeek': dayOfWeek,
                          'sessionType': sessionType.value,
                          'startTime': startController.text.trim(),
                          'endTime': endController.text.trim(),
                          'slotDurationMin':
                              int.tryParse(durationController.text) ?? 30,
                          'maxPatients':
                              int.tryParse(maxPatientsController.text) ?? 16,
                          'isActive': isActiveRule,
                          'validFrom': DateTime.now().toString().split(' ')[0],
                        };
                        try {
                          await ref
                              .read(doctorServiceProvider)
                              .addSchedule(payload);
                        } catch (_) {}
                        if (ctx.mounted) Navigator.pop(ctx);
                        _openScheduleModal(dc);
                      },
                      child: const Text('Add Schedule Rule',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _openLeaveModal(DoctorClinicModel dc) async {
    List<DoctorLeaveModel> leaves = [];
    try {
      leaves = await ref.read(doctorServiceProvider).getDcLeave(dc.dcId);
    } catch (_) {}

    final pendingCount = leaves.where((l) => !l.isApproved).length;
    final approvedCount = leaves.where((l) => l.isApproved).length;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLightTeal,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Branch: ${_getBranchName(dc.branchId)}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryTeal),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '🏖️ Leave Requests — ${_getDoctorName(dc.doctorId)}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryTeal),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: _dialogBody(
          context,
          maxWidth: 620,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF0F9FF), Color(0xFFE0F2FE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${leaves.length}',
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0EA5E9)),
                          ),
                          const SizedBox(height: 2),
                          const Text('TOTAL REQUESTS',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '$pendingCount',
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFF59E0B)),
                          ),
                          const SizedBox(height: 2),
                          const Text('PENDING',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '$approvedCount',
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF22C55E)),
                          ),
                          const SizedBox(height: 2),
                          const Text('APPROVED',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (leaves.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundApp,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderGray),
                  ),
                  child: Column(
                    children: const [
                      Text('🏖️', style: TextStyle(fontSize: 36)),
                      SizedBox(height: 6),
                      Text(
                        'No leave requests found for this doctor.',
                        style:
                            TextStyle(fontSize: 13, color: AppTheme.textMuted),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Leave requests submitted by the doctor will appear here.',
                        style:
                            TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                )
              else
                ...leaves.map((l) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: l.isApproved
                            ? const Color(0xFFF0FDF4)
                            : const Color(0xFFFFFDF7),
                        border: Border(
                          left: BorderSide(
                            color: l.isApproved
                                ? AppTheme.successGreen
                                : const Color(0xFFF59E0B),
                            width: 4,
                          ),
                          top: const BorderSide(color: AppTheme.borderGray),
                          right: const BorderSide(color: AppTheme.borderGray),
                          bottom: const BorderSide(color: AppTheme.borderGray),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE0F2FE),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        l.leaveType.value.replaceAll('_', ' '),
                                        style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0369A1)),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: l.isApproved
                                            ? const Color(0xFFDCFCE7)
                                            : const Color(0xFFFEF9C3),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        l.isApproved
                                            ? '✅ Approved'
                                            : '⏳ Pending',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: l.isApproved
                                              ? const Color(0xFF166534)
                                              : const Color(0xFF854D0E),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text('📅 ${l.startDate}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 6),
                                      child: Text('→',
                                          style: TextStyle(
                                              color: AppTheme.textMuted)),
                                    ),
                                    Text(l.endDate,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                  ],
                                ),
                                if (l.notes != null && l.notes!.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border(
                                          left: BorderSide(
                                              color: AppTheme.borderGray,
                                              width: 3)),
                                    ),
                                    child: Text('📝 ${l.notes}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textMuted)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            children: [
                              if (!l.isApproved)
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.successGreen,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    minimumSize: Size.zero,
                                  ),
                                  onPressed: () async {
                                    try {
                                      await ref
                                          .read(doctorServiceProvider)
                                          .updateLeave(
                                              l.leaveId, {'isApproved': true});
                                    } catch (_) {}
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    _openLeaveModal(dc);
                                  },
                                  child: const Text('✅ Approve',
                                      style: TextStyle(fontSize: 11)),
                                ),
                              if (l.isApproved)
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    minimumSize: Size.zero,
                                  ),
                                  onPressed: () async {
                                    try {
                                      await ref
                                          .read(doctorServiceProvider)
                                          .updateLeave(
                                              l.leaveId, {'isApproved': false});
                                    } catch (_) {}
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    _openLeaveModal(dc);
                                  },
                                  child: const Text('↩️ Revoke',
                                      style: TextStyle(fontSize: 11)),
                                ),
                              if (!l.isApproved) const SizedBox(height: 6),
                              if (!l.isApproved)
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.dangerRed,
                                    side: const BorderSide(
                                        color: AppTheme.dangerRed),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    minimumSize: Size.zero,
                                  ),
                                  onPressed: () async {
                                    try {
                                      await ref
                                          .read(doctorServiceProvider)
                                          .removeLeave(l.leaveId);
                                    } catch (_) {}
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    _openLeaveModal(dc);
                                  },
                                  child: const Text('❌ Reject',
                                      style: TextStyle(fontSize: 11)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    )),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _unassignDoctor(DoctorClinicModel dc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unassign Doctor'),
        content: Text(
            'Are you sure you want to remove ${_getDoctorName(dc.doctorId)} from branch ${_getBranchName(dc.branchId)}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(doctorServiceProvider)
                    .removeDoctorClinic(dc.dcId);
              } catch (_) {}
              setState(() {
                _placements.removeWhere((p) => p.dcId == dc.dcId);
              });
              _loadInitialData();
            },
            child: const Text('Unassign'),
          ),
        ],
      ),
    );
  }

  void _openDoctorProfileModal(String doctorId) async {
    DoctorDetailResponse? profile;
    try {
      profile =
          await ref.read(doctorServiceProvider).getDoctorProfile(doctorId);
    } catch (_) {}

    final doc = _doctors.firstWhere(
      (d) => d.doctorId == doctorId,
      orElse: () => DoctorModel(
        doctorId: doctorId,
        userId: '',
        fullName: doctorId.isNotEmpty ? doctorId : 'Doctor',
        mohRegistrationNumber: 'N/A',
        mohVerified: true,
        title: DoctorTitle.DR,
        experienceYears: 5,
        overallRating: 5.0,
        reviewCount: 0,
        consultationFeeSar: 150,
        isActive: true,
      ),
    );

    int activeSubTab = 0;
    final specController = TextEditingController(text: 'General Practice');
    final langController = TextEditingController(text: 'English');
    final degreeController = TextEditingController(text: 'MBBS');
    final instController = TextEditingController(text: 'King Saud University');

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppTheme.primaryLightTeal,
                      child: Text(doc.title.value,
                          style: const TextStyle(
                              color: AppTheme.primaryTeal,
                              fontWeight: FontWeight.bold,
                              fontSize: 11)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(doc.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryTeal)),
                          Text(
                              'MOH: ${doc.mohRegistrationNumber} | ${doc.experienceYears} Yrs Exp',
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: _dialogBody(
            context,
            maxWidth: 540,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Specialties',
                            style: TextStyle(fontSize: 11)),
                        selected: activeSubTab == 0,
                        selectedColor: AppTheme.primaryLightTeal,
                        onSelected: (v) =>
                            setModalState(() => activeSubTab = 0),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Languages',
                            style: TextStyle(fontSize: 11)),
                        selected: activeSubTab == 1,
                        selectedColor: AppTheme.primaryLightTeal,
                        onSelected: (v) =>
                            setModalState(() => activeSubTab = 1),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Qualifications',
                            style: TextStyle(fontSize: 11)),
                        selected: activeSubTab == 2,
                        selectedColor: AppTheme.primaryLightTeal,
                        onSelected: (v) =>
                            setModalState(() => activeSubTab = 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (activeSubTab == 0) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: specController,
                          decoration: const InputDecoration(
                            hintText: 'Specialty Name',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          final payload = {
                            'doctorId': doctorId,
                            'specialtyId': specController.text.trim(),
                            'isPrimary': true,
                          };
                          try {
                            await ref
                                .read(doctorServiceProvider)
                                .addSpecialty(payload);
                          } catch (_) {}
                          try {
                            final updated = await ref
                                .read(doctorServiceProvider)
                                .getDoctorProfile(doctorId);
                            setModalState(() => profile = updated);
                          } catch (_) {}
                        },
                        child:
                            const Text('Add', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (profile != null && profile!.specialties.isNotEmpty)
                    ...profile!.specialties.map((s) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(s.specialtyId,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete,
                                size: 18, color: AppTheme.dangerRed),
                            onPressed: () async {
                              try {
                                await ref
                                    .read(doctorServiceProvider)
                                    .removeSpecialty(s.id);
                                final updated = await ref
                                    .read(doctorServiceProvider)
                                    .getDoctorProfile(doctorId);
                                setModalState(() => profile = updated);
                              } catch (_) {}
                            },
                          ),
                        ))
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No specialties linked yet.',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted)),
                    ),
                ] else if (activeSubTab == 1) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: langController,
                          decoration: const InputDecoration(
                            hintText: 'Language Name',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          final payload = {
                            'doctorId': doctorId,
                            'languageId': langController.text.trim(),
                            'proficiency': 'FLUENT',
                          };
                          try {
                            await ref
                                .read(doctorServiceProvider)
                                .addLanguage(payload);
                          } catch (_) {}
                          try {
                            final updated = await ref
                                .read(doctorServiceProvider)
                                .getDoctorProfile(doctorId);
                            setModalState(() => profile = updated);
                          } catch (_) {}
                        },
                        child:
                            const Text('Add', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (profile != null && profile!.languages.isNotEmpty)
                    ...profile!.languages.map((l) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(l.languageId,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text('Proficiency: ${l.proficiency.value}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.textMuted)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete,
                                size: 18, color: AppTheme.dangerRed),
                            onPressed: () async {
                              try {
                                await ref
                                    .read(doctorServiceProvider)
                                    .removeLanguage(l.id);
                                final updated = await ref
                                    .read(doctorServiceProvider)
                                    .getDoctorProfile(doctorId);
                                setModalState(() => profile = updated);
                              } catch (_) {}
                            },
                          ),
                        ))
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No languages linked yet.',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted)),
                    ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: degreeController,
                          decoration: const InputDecoration(
                            hintText: 'Degree (e.g. MBBS)',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: instController,
                          decoration: const InputDecoration(
                            hintText: 'Institution',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        onPressed: () async {
                          final payload = {
                            'doctorId': doctorId,
                            'degree': degreeController.text.trim(),
                            'institution': instController.text.trim(),
                            'country': 'Saudi Arabia',
                            'yearObtained': 2020,
                            'sortOrder': 1,
                          };
                          try {
                            await ref
                                .read(doctorServiceProvider)
                                .addQualification(payload);
                          } catch (_) {}
                          try {
                            final updated = await ref
                                .read(doctorServiceProvider)
                                .getDoctorProfile(doctorId);
                            setModalState(() => profile = updated);
                          } catch (_) {}
                        },
                        child:
                            const Text('Add', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (profile != null && profile!.qualifications.isNotEmpty)
                    ...profile!.qualifications.map((q) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${q.degree} — ${q.institution}',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text('${q.country} (${q.yearObtained})',
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.textMuted)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete,
                                size: 18, color: AppTheme.dangerRed),
                            onPressed: () async {
                              try {
                                await ref
                                    .read(doctorServiceProvider)
                                    .removeQualification(q.qualId);
                                final updated = await ref
                                    .read(doctorServiceProvider)
                                    .getDoctorProfile(doctorId);
                                setModalState(() => profile = updated);
                              } catch (_) {}
                            },
                          ),
                        ))
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No qualifications linked yet.',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted)),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────────

  Widget _buildHeaderBanner(bool isVertical) {
    if (isVertical) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Expanded(
            child: Text(
              '👤 Doctor Roster',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryTeal,
              ),
            ),
          ),
          IconButton.filled(
            key: const Key('add_placement_btn'),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.primaryTeal,
              minimumSize: const Size(44, 44),
            ),
            icon: const Icon(Icons.add, size: 22),
            tooltip: 'Assign Doctor',
            onPressed: _openAddPlacementModal,
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                '👤 Doctor Roster Placement',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryTeal,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Manage doctor roster placements across facility branches, departments, and fee structures',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
        ElevatedButton.icon(
          key: const Key('add_placement_btn'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryTeal,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Assign Doctor',
              style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: _openAddPlacementModal,
        ),
      ],
    );
  }

  Widget _buildFilterBar(bool isVertical, int count) {
    if (isVertical) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderGray),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_clinics.isNotEmpty)
                  Expanded(
                    flex: 4,
                    child: DropdownButtonFormField<String>(
                      initialValue:
                          _clinics.any((c) => c.clinicId == _selectedClinicId)
                              ? _selectedClinicId
                              : (_clinics.isNotEmpty
                                  ? _clinics.first.clinicId
                                  : null),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                      items: _clinics.map((c) {
                        return DropdownMenuItem(
                            value: c.clinicId,
                            child: Text(c.nameEn,
                                overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedClinicId = val;
                          });
                          _loadBranchesForClinic(val);
                          _loadPlacementsData();
                        }
                      },
                    ),
                  ),
                if (_clinics.isNotEmpty) const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0369A1),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: '🔍 Search doctor / branch / specialty',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (v) => setState(() => _searchTerm = v),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (_clinics.isNotEmpty) ...[
                  const Text(
                    'Facility:',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMain),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue:
                          _clinics.any((c) => c.clinicId == _selectedClinicId)
                              ? _selectedClinicId
                              : (_clinics.isNotEmpty
                                  ? _clinics.first.clinicId
                                  : null),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: _clinics.map((c) {
                        return DropdownMenuItem(
                            value: c.clinicId,
                            child: Text(c.nameEn,
                                overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedClinicId = val;
                          });
                          _loadBranchesForClinic(val);
                          _loadPlacementsData();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText:
                          '🔍 Search doctor by name, specialty, or branch...',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    ),
                    onChanged: (v) => setState(() => _searchTerm = v),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count Active Doctor(s)',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0369A1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundApp,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isVertical = constraints.maxWidth < 700;
            return Padding(
              padding: EdgeInsets.all(isVertical ? 12 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderBanner(isVertical),
                  SizedBox(height: isVertical ? 10 : 16),
                  Expanded(
                    child: _buildRosterTab(isVertical),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRosterTab(bool isVertical) {
    final filtered = _filteredDoctorClinics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFilterBar(isVertical, filtered.length),
        const SizedBox(height: 16),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _loadInitialData,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [_buildEmptyState()],
                      ),
                    )
                  : isVertical
                      ? RefreshIndicator(
                          onRefresh: _loadInitialData,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(4),
                            itemCount: filtered.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 14),
                            itemBuilder: (context, index) {
                              return _buildDoctorCard(filtered[index]);
                            },
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final cols = constraints.maxWidth >= 1000 ? 3 : 2;
                            return RefreshIndicator(
                              onRefresh: _loadInitialData,
                              child: GridView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: filtered.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: cols,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                  mainAxisExtent: 360,
                                ),
                                itemBuilder: (context, index) {
                                  return _buildDoctorCard(filtered[index]);
                                },
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildDoctorCard(DoctorClinicModel dc) {
    final docName = _getDoctorName(dc.doctorId);
    final branchName = _getBranchName(dc.branchId);

    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppTheme.borderGray),
      ),
      margin: EdgeInsets.zero,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: AppTheme.primaryTeal, width: 5),
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top Header Row: Avatar, Info, Status Dot ──────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLightTeal,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primaryTeal, width: 1.2),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.person,
                      color: AppTheme.primaryTeal, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLightTeal,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          dc.department.isNotEmpty
                              ? dc.department
                              : 'General Practice',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        docName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryTeal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                // Status dot
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dc.isActive
                            ? AppTheme.successGreen
                            : AppTheme.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      dc.isActive ? 'Available' : 'Inactive',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: dc.isActive
                            ? Colors.green.shade700
                            : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Middle Details ──────────────────────────────────────────
            _cardRow('Branch Location:', branchName,
                valueColor: AppTheme.primaryTeal),
            const SizedBox(height: 8),
            _cardRow('Consultation Fee:',
                'SAR ${dc.consultationFeeSar.toStringAsFixed(0)}',
                valueColor: AppTheme.successGreen),
            const SizedBox(height: 8),
            _cardRow('Role Designation:',
                dc.isPrimary ? '⭐ Primary Specialist' : 'Consultant',
                small: true),
            const SizedBox(height: 6),
            _cardRow('Roster Since:', dc.startDate, small: true),

            // Gap before action buttons (fixed, not Spacer — this card is
            // reused inside an unbounded-height ListView on phones, where
            // Spacer() would throw at layout time)
            const SizedBox(height: 12),

            // ── Action Buttons 2×2 ─────────────────────────────────────
            const Divider(height: 14, thickness: 0.5),
            Row(
              children: [
                Expanded(
                  child: _cardActionButton(
                    label: '👤 Profile',
                    onPressed: () => _openDoctorProfileModal(dc.doctorId),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _cardActionButton(
                    label: '🗓️ Schedule',
                    onPressed: () => _openScheduleModal(dc),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _cardActionButton(
                    label: '🏖️ Leaves',
                    onPressed: () => _openLeaveModal(dc),
                    borderColor: const Color(0xFFF59E0B),
                    textColor: const Color(0xFFF59E0B),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _cardActionButton(
                    label: '❌ Unassign',
                    onPressed: () => _unassignDoctor(dc),
                    borderColor: AppTheme.dangerRed,
                    textColor: AppTheme.dangerRed,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardRow(String label, String value,
      {Color valueColor = AppTheme.textSecondary, bool small = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: small ? 10 : 11, color: AppTheme.textMuted)),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: small ? 10 : 11,
                fontWeight: FontWeight.bold,
                color: valueColor),
          ),
        ),
      ],
    );
  }

  Widget _cardActionButton({
    required String label,
    required VoidCallback onPressed,
    Color borderColor = AppTheme.borderGray,
    Color textColor = AppTheme.textMain,
  }) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 10),
        side: BorderSide(color: borderColor),
        foregroundColor: textColor,
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: onPressed,
      child: Text(label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: AppTheme.borderGray, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text('👨‍⚕️', style: TextStyle(fontSize: 48)),
            SizedBox(height: 10),
            Text(
              'No doctors currently assigned to this roster.',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textMuted),
            ),
            SizedBox(height: 4),
            Text(
              'Try selecting another clinic branch or click "+ Assign Doctor to Branch".',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  // ── PROFILES TAB ───────────────────────────────────────────────────

  Widget _buildProfilesTab() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.borderGray),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _doctors.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final doc = _doctors[index];
          return ListTile(
            onTap: () => _openDoctorProfileModal(doc.doctorId),
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryLightTeal,
              child: Text(
                doc.title.value,
                style: const TextStyle(
                    color: AppTheme.primaryTeal,
                    fontWeight: FontWeight.bold,
                    fontSize: 11),
              ),
            ),
            title: Text(
              doc.fullName,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
            ),
            subtitle: Text(
                'MOH Reg: ${doc.mohRegistrationNumber} | ${doc.experienceYears} Yrs Exp'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '★ ${doc.overallRating}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.amber.shade900),
              ),
            ),
          );
        },
      ),
    );
  }
}

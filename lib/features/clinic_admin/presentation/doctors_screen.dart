import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
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

  DoctorModel? _getDoctor(String doctorId) {
    try {
      return _doctors.firstWhere((d) => d.doctorId == doctorId);
    } catch (_) {
      return null;
    }
  }

  String _getLogoUrl(String? url) {
    if (url == null || url.trim().isEmpty) return '';
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('data:') ||
        trimmed.startsWith('blob:')) {
      return trimmed;
    }
    final cleanPath = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return '$kBaseUrl$cleanPath';
  }

  String _getDoctorName(String doctorId) {
    final doc = _getDoctor(doctorId) ??
        DoctorModel(
          doctorId: '',
          userId: '',
          email: '',
          fullName: doctorId.isNotEmpty ? doctorId : 'Doctor',
          mohRegistrationNumber: '',
          mohVerified: true,
          title: DoctorTitle.DR,
          experienceYears: 0,
          overallRating: 0,
          reviewCount: 0,
          consultationFeeSar: 0,
          isActive: true,
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

    final doc = _getDoctor(dc.doctorId);
    final avatarUrl = doc?.avatarUrl != null ? _getLogoUrl(doc!.avatarUrl) : '';

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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.primaryLightTeal,
                      backgroundImage: avatarUrl.isNotEmpty
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl.isEmpty
                          ? Text(
                              doc != null && doc.fullName.isNotEmpty
                                  ? doc.fullName[0]
                                  : '👨‍⚕️',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryTeal,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLightTeal,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Branch: ${_getBranchName(dc.branchId)}',
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryDarkTeal),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '📅 Working Schedule — ${_getDoctorName(dc.doctorId)}',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryTeal),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
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

  void _openLeaveModal(DoctorClinicModel dc) {
    final doc = _getDoctor(dc.doctorId);
    final avatarUrl =
        doc?.avatarUrl != null ? _getLogoUrl(doc!.avatarUrl) : '';
    final branchName = _getBranchName(dc.branchId);

    showDialog(
      context: context,
      builder: (ctx) => _DoctorLeaveDialog(
        dc: dc,
        doc: doc,
        branchName: branchName,
        avatarUrl: avatarUrl,
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

  void _openDoctorProfileModal(String doctorId) {
    final doc = _doctors.firstWhere(
      (d) => d.doctorId == doctorId,
      orElse: () => DoctorModel(
        doctorId: doctorId,
        userId: '',
        email: '',
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

    final matchingDc =
        _placements.where((p) => p.doctorId == doctorId).toList();
    final selectedDc = matchingDc.isNotEmpty ? matchingDc.first : null;
    final branchName =
        selectedDc != null ? _getBranchName(selectedDc.branchId) : 'All Branches';
    final avatarUrl =
        doc.avatarUrl != null ? _getLogoUrl(doc.avatarUrl) : '';

    showDialog(
      context: context,
      builder: (ctx) => _DoctorProfileDialog(
        doctorId: doctorId,
        doc: doc,
        dc: selectedDc,
        branchName: branchName,
        avatarUrl: avatarUrl,
        onManageSchedule: selectedDc != null
            ? () {
                Navigator.pop(ctx);
                _openScheduleModal(selectedDc);
              }
            : null,
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────────

  Widget _buildHeaderBanner(bool isVertical) {
    if (isVertical) {
      return Container(
        padding: const EdgeInsets.only(bottom: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.borderGray)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Text(
                    '👨‍⚕️ Doctor Roster Placement',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryTeal,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  key: const Key('add_placement_btn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Assign Doctor',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: _openAddPlacementModal,
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Manage doctor roster placements across facility branches, departments, and fee structures',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.borderGray)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '👨‍⚕️ Doctor Roster Placement',
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
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Assign Doctor',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            onPressed: _openAddPlacementModal,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(bool isVertical, int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
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
      child: isVertical
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_clinics.isNotEmpty) ...[
                      const Text(
                        'Facility:',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMain),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _clinics.any((c) => c.clinicId == _selectedClinicId)
                              ? _selectedClinicId
                              : (_clinics.isNotEmpty
                                  ? _clinics.first.clinicId
                                  : null),
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                          ),
                          items: _clinics.map((c) {
                            return DropdownMenuItem(
                                value: c.clinicId,
                                child: Text(c.nameEn,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12)));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedClinicId = val);
                              _loadBranchesForClinic(val);
                              _loadPlacementsData();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLightTeal,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$count Active',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryDarkTeal,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search by name, specialty, or branch...',
                    prefixIcon:
                        Icon(Icons.search, size: 18, color: AppTheme.textMuted),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _searchTerm = v),
                ),
              ],
            )
          : Row(
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
                    width: 200,
                    child: DropdownButtonFormField<String>(
                      value: _clinics.any((c) => c.clinicId == _selectedClinicId)
                          ? _selectedClinicId
                          : (_clinics.isNotEmpty
                              ? _clinics.first.clinicId
                              : null),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      items: _clinics.map((c) {
                        return DropdownMenuItem(
                            value: c.clinicId,
                            child: Text(c.nameEn,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5)));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedClinicId = val);
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
                      hintText: 'Search by name, specialty, or branch...',
                      prefixIcon: Icon(Icons.search,
                          size: 18, color: AppTheme.textMuted),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    ),
                    onChanged: (v) => setState(() => _searchTerm = v),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLightTeal,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$count Active Doctor(s)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryDarkTeal,
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
    final doc = _getDoctor(dc.doctorId);
    final docName = _getDoctorName(dc.doctorId);
    final branchName = _getBranchName(dc.branchId);
    final avatarUrl = doc?.avatarUrl != null ? _getLogoUrl(doc!.avatarUrl) : '';

    return Card(
      elevation: 1.5,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppTheme.borderGray),
      ),
      margin: EdgeInsets.zero,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: AppTheme.primaryTeal, width: 4),
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
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.primaryLightTeal,
                  backgroundImage: avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? Text(
                          doc != null && doc.fullName.isNotEmpty
                              ? doc.fullName[0]
                              : '👨‍⚕️',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLightTeal,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          dc.department.isNotEmpty
                              ? dc.department
                              : 'General Practice',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDarkTeal,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        children: [
                          Text(
                            docName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMain,
                            ),
                          ),
                          if (doc?.mohVerified == true)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: Colors.green.shade300, width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle,
                                      size: 10, color: Colors.green.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    'MOH',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
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

            // ── Middle Details Box ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.backgroundApp,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderGray),
              ),
              child: Column(
                children: [
                  _cardRow('Branch Location:', branchName,
                      valueColor: AppTheme.primaryTeal),
                  const SizedBox(height: 6),
                  _cardRow('Consultation Fee:',
                      'SAR ${dc.consultationFeeSar.toStringAsFixed(0)}',
                      valueColor: AppTheme.successGreen),
                  const Divider(height: 12, color: AppTheme.borderGray),
                  _cardRow('Role Designation:',
                      dc.isPrimary ? '⭐ Primary Specialist' : 'Consultant',
                      small: true),
                  const SizedBox(height: 4),
                  _cardRow('Roster Since:', dc.startDate, small: true),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ── Action Buttons 2×2 ─────────────────────────────────────
            const Divider(height: 12, thickness: 0.5),
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

class _DoctorLeaveDialog extends ConsumerStatefulWidget {
  final DoctorClinicModel dc;
  final DoctorModel? doc;
  final String branchName;
  final String avatarUrl;

  const _DoctorLeaveDialog({
    required this.dc,
    required this.doc,
    required this.branchName,
    required this.avatarUrl,
  });

  @override
  ConsumerState<_DoctorLeaveDialog> createState() => _DoctorLeaveDialogState();
}

class _DoctorLeaveDialogState extends ConsumerState<_DoctorLeaveDialog> {
  List<DoctorLeaveModel> _leaves = [];
  bool _isLoading = true;
  String? _actionLoadingId;

  @override
  void initState() {
    super.initState();
    _loadLeaves();
  }

  Future<void> _loadLeaves() async {
    setState(() => _isLoading = true);
    try {
      final data =
          await ref.read(doctorServiceProvider).getDcLeave(widget.dc.dcId);
      if (mounted) {
        setState(() {
          _leaves = data;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _leaves = [];
          _isLoading = false;
        });
      }
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'N/A';
    try {
      final dt = DateTime.parse(raw);
      final months = [
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
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return raw.split('T').first;
    }
  }

  String _formatDateTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'N/A';
    try {
      final dt = DateTime.parse(raw);
      final months = [
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
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}, $hour:$min $ampm';
    } catch (_) {
      return raw;
    }
  }

  String _formatDoctorName(DoctorModel? doc) {
    if (doc == null || doc.fullName.isEmpty) return 'Doctor';
    final name = doc.fullName.trim();
    if (name.toLowerCase().startsWith('dr.') ||
        name.toLowerCase().startsWith('dr ')) {
      return name;
    }
    return '${doc.title.value}. $name';
  }

  Future<void> _approveLeave(DoctorLeaveModel leave) async {
    setState(() => _actionLoadingId = leave.leaveId);
    try {
      final payload = {
        'dcId': leave.dcId,
        'leaveType': leave.leaveType.value,
        'startDate': leave.startDate,
        'endDate': leave.endDate,
        'isApproved': true,
        'notes': leave.notes,
      };
      await ref.read(doctorServiceProvider).updateLeave(leave.leaveId, payload);
    } catch (_) {}
    await _loadLeaves();
    if (mounted) setState(() => _actionLoadingId = null);
  }

  Future<void> _revokeLeave(DoctorLeaveModel leave) async {
    setState(() => _actionLoadingId = leave.leaveId);
    try {
      final payload = {
        'dcId': leave.dcId,
        'leaveType': leave.leaveType.value,
        'startDate': leave.startDate,
        'endDate': leave.endDate,
        'isApproved': false,
        'notes': leave.notes,
      };
      await ref.read(doctorServiceProvider).updateLeave(leave.leaveId, payload);
    } catch (_) {}
    await _loadLeaves();
    if (mounted) setState(() => _actionLoadingId = null);
  }

  Future<void> _rejectLeave(DoctorLeaveModel leave) async {
    setState(() => _actionLoadingId = leave.leaveId);
    try {
      await ref.read(doctorServiceProvider).removeLeave(leave.leaveId);
    } catch (_) {}
    await _loadLeaves();
    if (mounted) setState(() => _actionLoadingId = null);
  }

  Widget _buildLeaveCard(DoctorLeaveModel leave) {
    final isApproved = leave.isApproved;
    final isBusy = _actionLoadingId == leave.leaveId;
    final typeStr = leave.leaveType.value.replaceAll('_', ' ');
    final startFormatted = _formatDate(leave.startDate);
    final endFormatted = _formatDate(leave.endDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isApproved ? const Color(0xFFF0FDF4) : const Color(0xFFFFFDF7),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color:
                isApproved ? AppTheme.successGreen : const Color(0xFFF59E0B),
            width: 4,
          ),
          top: const BorderSide(color: AppTheme.borderGray),
          right: const BorderSide(color: AppTheme.borderGray),
          bottom: const BorderSide(color: AppTheme.borderGray),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row: Badges & Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Badges
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      typeStr,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0369A1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isApproved
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFFEF9C3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isApproved ? 'Approved' : 'Pending',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isApproved
                            ? const Color(0xFF166534)
                            : const Color(0xFF854D0E),
                      ),
                    ),
                  ),
                ],
              ),
              // Actions
              if (isBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (!isApproved)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => _approveLeave(leave),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Approve',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => _rejectLeave(leave),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFEF4444)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Reject',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                InkWell(
                  onTap: () => _revokeLeave(leave),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF9CA3AF)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Revoke',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Date Range
          Row(
            children: [
              const Text('📅 ', style: TextStyle(fontSize: 12)),
              Text(
                startFormatted,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '→',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ),
              Text(
                endFormatted,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          // Notes if available
          if (leave.notes != null && leave.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(4)),
                border: Border(
                  left: BorderSide(color: Color(0xFFCBD5E1), width: 3),
                ),
              ),
              child: Text(
                '📝 ${leave.notes}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ],
          // Submitted Timestamp
          if (leave.createdAt != null &&
              leave.createdAt!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Submitted: ${_formatDateTime(leave.createdAt)}',
              style: const TextStyle(
                fontSize: 10.5,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _leaves.where((l) => !l.isApproved).length;
    final approvedCount = _leaves.where((l) => l.isApproved).length;
    final doctorName = _formatDoctorName(widget.doc);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.primaryLightTeal,
                  backgroundImage: widget.avatarUrl.isNotEmpty
                      ? NetworkImage(widget.avatarUrl)
                      : null,
                  child: widget.avatarUrl.isEmpty
                      ? Text(
                          widget.doc != null && widget.doc!.fullName.isNotEmpty
                              ? widget.doc!.fullName[0]
                              : '👨‍⚕️',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLightTeal,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Branch: ${widget.branchName}',
                          style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryDarkTeal),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '🏖️ Leave Requests — $doctorName',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65,
        ),
        child: SizedBox(
          width: (MediaQuery.of(context).size.width - 32).clamp(280.0, 620.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Summary Banner
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
                              '${_leaves.length}',
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
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_leaves.isEmpty)
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
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMain),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Leave requests submitted by the doctor will appear here.',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  )
                else
                  ..._leaves.map((l) => _buildLeaveCard(l)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(fontSize: 11.5)),
        ),
      ],
    );
  }
}

class _DoctorProfileDialog extends ConsumerStatefulWidget {
  final String doctorId;
  final DoctorModel doc;
  final DoctorClinicModel? dc;
  final String branchName;
  final String avatarUrl;
  final VoidCallback? onManageSchedule;

  const _DoctorProfileDialog({
    required this.doctorId,
    required this.doc,
    this.dc,
    required this.branchName,
    required this.avatarUrl,
    this.onManageSchedule,
  });

  @override
  ConsumerState<_DoctorProfileDialog> createState() =>
      _DoctorProfileDialogState();
}

class _DoctorProfileDialogState extends ConsumerState<_DoctorProfileDialog> {
  DoctorDetailResponse? _profile;
  bool _isLoading = true;
  int _activeTab = 0; // 0: Specialties, 1: Languages, 2: Qualifications

  final _specController = TextEditingController();
  final _langController = TextEditingController();
  final _degreeController = TextEditingController();
  final _instController = TextEditingController();
  final _countryController = TextEditingController(text: 'Saudi Arabia');
  final _yearController =
      TextEditingController(text: DateTime.now().year.toString());

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _specController.dispose();
    _langController.dispose();
    _degreeController.dispose();
    _instController.dispose();
    _countryController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final data = await ref
          .read(doctorServiceProvider)
          .getDoctorProfile(widget.doctorId);
      if (mounted) {
        setState(() {
          _profile = data;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDoctorName(DoctorModel doc) {
    final name = doc.fullName.trim();
    if (name.isEmpty) return 'Doctor';
    if (name.toLowerCase().startsWith('dr.') ||
        name.toLowerCase().startsWith('dr ')) {
      return name;
    }
    final prefix = doc.title.value.isNotEmpty ? '${doc.title.value}. ' : 'Dr. ';
    return '$prefix$name';
  }

  Future<void> _addSpecialty() async {
    final text = _specController.text.trim();
    if (text.isEmpty) return;
    try {
      await ref.read(doctorServiceProvider).addSpecialty({
        'doctorId': widget.doctorId,
        'specialtyId': text,
        'isPrimary': true,
      });
      _specController.clear();
      await _loadProfile();
    } catch (_) {}
  }

  Future<void> _removeSpecialty(String id) async {
    try {
      await ref.read(doctorServiceProvider).removeSpecialty(id);
      await _loadProfile();
    } catch (_) {}
  }

  Future<void> _addLanguage() async {
    final text = _langController.text.trim();
    if (text.isEmpty) return;
    try {
      await ref.read(doctorServiceProvider).addLanguage({
        'doctorId': widget.doctorId,
        'languageId': text,
        'proficiency': 'FLUENT',
      });
      _langController.clear();
      await _loadProfile();
    } catch (_) {}
  }

  Future<void> _removeLanguage(String id) async {
    try {
      await ref.read(doctorServiceProvider).removeLanguage(id);
      await _loadProfile();
    } catch (_) {}
  }

  Future<void> _addQualification() async {
    final degree = _degreeController.text.trim();
    final inst = _instController.text.trim();
    if (degree.isEmpty || inst.isEmpty) return;
    try {
      await ref.read(doctorServiceProvider).addQualification({
        'doctorId': widget.doctorId,
        'degree': degree,
        'institution': inst,
        'country': _countryController.text.trim().isNotEmpty
            ? _countryController.text.trim()
            : 'Saudi Arabia',
        'yearObtained':
            int.tryParse(_yearController.text.trim()) ?? DateTime.now().year,
        'sortOrder': 1,
      });
      _degreeController.clear();
      _instController.clear();
      await _loadProfile();
    } catch (_) {}
  }

  Future<void> _removeQualification(String qualId) async {
    try {
      await ref.read(doctorServiceProvider).removeQualification(qualId);
      await _loadProfile();
    } catch (_) {}
  }

  Widget _metricBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeDoc = _profile ?? widget.doc;
    final doctorName = _formatDoctorName(activeDoc);
    final fee = widget.dc != null
        ? widget.dc!.consultationFeeSar
        : activeDoc.consultationFeeSar;
    final specialties = _profile?.specialties ?? [];
    final languages = _profile?.languages ?? [];
    final qualifications = _profile?.qualifications ?? [];

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: Row(
              children: [
                Icon(Icons.medical_services_outlined,
                    color: AppTheme.primaryTeal, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Doctor Professional Profile',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        child: SizedBox(
          width: (MediaQuery.of(context).size.width - 32).clamp(280.0, 560.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Doctor Banner Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAF9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.primaryLightTeal,
                          border:
                              Border.all(color: AppTheme.primaryTeal, width: 2),
                        ),
                        child: ClipOval(
                          child: widget.avatarUrl.isNotEmpty
                              ? Image.network(
                                  widget.avatarUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                      Icons.person,
                                      size: 26,
                                      color: AppTheme.primaryTeal),
                                )
                              : Center(
                                  child: Text(
                                    activeDoc.fullName.isNotEmpty
                                        ? activeDoc.fullName[0]
                                        : '👨‍⚕️',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryTeal,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    doctorName,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (activeDoc.mohVerified) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '✓ MOH Verified',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF166534),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Wrap(
                              spacing: 8,
                              runSpacing: 2,
                              children: [
                                if (activeDoc.email.isNotEmpty)
                                  Text(
                                    '✉️ ${activeDoc.email}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                if (activeDoc.mohRegistrationNumber.isNotEmpty)
                                  Text(
                                    'MOH: ${activeDoc.mohRegistrationNumber}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 3 Metrics Grid
                Row(
                  children: [
                    Expanded(
                      child: _metricBox(
                        'Experience',
                        '${activeDoc.experienceYears} Years',
                        AppTheme.primaryTeal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricBox(
                        'Rating',
                        '${activeDoc.overallRating > 0 ? activeDoc.overallRating.toStringAsFixed(1) : "5.0"} ★',
                        const Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricBox(
                        'Consultation Fee',
                        'SAR ${fee.toStringAsFixed(0)}',
                        const Color(0xFF22C55E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Biography
                const Text(
                  'Professional Biography',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAF9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    (activeDoc.bioEn != null && activeDoc.bioEn!.isNotEmpty)
                        ? activeDoc.bioEn!
                        : 'No professional biography provided.',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF334155),
                      height: 1.4,
                    ),
                  ),
                ),
                // Active Placement Section
                if (widget.dc != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Active Placement Details',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Assigned Branch:',
                                style: TextStyle(
                                    fontSize: 11, color: Color(0xFF64748B))),
                            Text(
                              widget.branchName,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Department:',
                                style: TextStyle(
                                    fontSize: 11, color: Color(0xFF64748B))),
                            Text(
                              widget.dc!.department.isNotEmpty
                                  ? widget.dc!.department
                                  : 'General',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Primary Placement:',
                                style: TextStyle(
                                    fontSize: 11, color: Color(0xFF64748B))),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: widget.dc!.isPrimary
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.dc!.isPrimary ? 'Primary' : 'Secondary',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: widget.dc!.isPrimary
                                      ? const Color(0xFF166534)
                                      : const Color(0xFF475569),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                // Sub-tabs: Specialties / Languages / Qualifications (Horizontally Scrollable)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _tabPill(0, 'Specialties', specialties.length),
                      const SizedBox(width: 6),
                      _tabPill(1, 'Languages', languages.length),
                      const SizedBox(width: 6),
                      _tabPill(2, 'Qualifications', qualifications.length),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_activeTab == 0) ...[
                  // Specialties Tab
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: TextField(
                            controller: _specController,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'e.g. Cardiology, Pediatrics',
                              hintStyle: const TextStyle(
                                  fontSize: 11.5, color: Color(0xFF94A3B8)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide:
                                    const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide:
                                    const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: _addSpecialty,
                        child: const Text('Add',
                            style: TextStyle(
                                fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (specialties.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No specialties linked yet.',
                          style: TextStyle(
                              fontSize: 11.5, color: Color(0xFF94A3B8))),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: specialties.map((s) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFBAE6FD)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                s.specialtyId,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0369A1),
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => _removeSpecialty(s.id),
                                child: const Icon(Icons.close,
                                    size: 14, color: Color(0xFF0369A1)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ] else if (_activeTab == 1) ...[
                  // Languages Tab
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: TextField(
                            controller: _langController,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'e.g. Arabic, English',
                              hintStyle: const TextStyle(
                                  fontSize: 11.5, color: Color(0xFF94A3B8)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide:
                                    const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide:
                                    const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: _addLanguage,
                        child: const Text('Add',
                            style: TextStyle(
                                fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (languages.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No languages linked yet.',
                          style: TextStyle(
                              fontSize: 11.5, color: Color(0xFF94A3B8))),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: languages.map((l) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${l.languageId} (${l.proficiency.value})',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF166534),
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => _removeLanguage(l.id),
                                child: const Icon(Icons.close,
                                    size: 14, color: Color(0xFF166534)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ] else ...[
                  // Qualifications Tab (2 clean rows to avoid horizontal crunch)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 36,
                                child: TextField(
                                  controller: _degreeController,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: 'Degree (e.g. MBBS)',
                                    hintStyle: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF94A3B8)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE2E8F0)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE2E8F0)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: SizedBox(
                                height: 36,
                                child: TextField(
                                  controller: _instController,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: 'Institution',
                                    hintStyle: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF94A3B8)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE2E8F0)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE2E8F0)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 36,
                                child: TextField(
                                  controller: _countryController,
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: 'Country',
                                    hintStyle: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF94A3B8)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE2E8F0)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE2E8F0)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 70,
                              height: 36,
                              child: TextField(
                                controller: _yearController,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 12),
                                decoration: InputDecoration(
                                  hintText: 'Year',
                                  hintStyle: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF94A3B8)),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFE2E8F0)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFE2E8F0)),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryTeal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                minimumSize: const Size(0, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: _addQualification,
                              child: const Text('Add',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (qualifications.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No qualifications linked yet.',
                          style: TextStyle(
                              fontSize: 11.5, color: Color(0xFF94A3B8))),
                    )
                  else
                    ...qualifications.map((q) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${q.degree} — ${q.institution}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    '${q.country} (${q.yearObtained})',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: () => _removeQualification(q.qualId),
                              child: const Icon(Icons.delete_outline,
                                  size: 16, color: Color(0xFFEF4444)),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.onManageSchedule != null)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryTeal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
            icon: const Icon(Icons.calendar_month, size: 14),
            label: const Text(
              'Manage Doctor Schedules',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
            onPressed: widget.onManageSchedule,
          ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('Close', style: TextStyle(fontSize: 11.5)),
        ),
      ],
    );
  }

  Widget _tabPill(int index, String title, int count) {
    final isSelected = _activeTab == index;
    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryLightTeal : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppTheme.primaryTeal : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color:
                    isSelected ? AppTheme.primaryDarkTeal : const Color(0xFF64748B),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryTeal : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}




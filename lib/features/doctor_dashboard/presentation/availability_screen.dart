import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../clinic_admin/data/doctor_models.dart';
import '../../clinic_admin/data/clinic_service.dart';

enum _AvailabilityTab { schedule, leaves, slots }

const List<Map<String, dynamic>> _kDaysOfWeek = [
  {'value': 1, 'label': 'Monday'},
  {'value': 2, 'label': 'Tuesday'},
  {'value': 3, 'label': 'Wednesday'},
  {'value': 4, 'label': 'Thursday'},
  {'value': 5, 'label': 'Friday'},
  {'value': 6, 'label': 'Saturday'},
  {'value': 7, 'label': 'Sunday'},
];

class DoctorAvailabilityScreen extends ConsumerStatefulWidget {
  const DoctorAvailabilityScreen({super.key});

  @override
  ConsumerState<DoctorAvailabilityScreen> createState() =>
      _DoctorAvailabilityScreenState();
}

class _DoctorAvailabilityScreenState
    extends ConsumerState<DoctorAvailabilityScreen> {
  bool _isLoading = false;
  String? _doctorId;
  List<DoctorClinicModel> _clinics = [];
  String? _selectedDcId;
  _AvailabilityTab _activeTab = _AvailabilityTab.schedule;

  // Data
  List<DoctorScheduleModel> _schedules = [];
  List<DoctorLeaveModel> _leaves = [];
  List<dynamic> _slots = [];

  DateTime _slotFilterDate = DateTime.now();

  // Schedule form state
  int _dayOfWeek = 1;
  String _schStartTime = '09:00';
  String _schEndTime = '17:00';
  int _slotDurationMin = 30;
  SessionType _schSessionType = SessionType.IN_CLINIC;

  // Leave form state
  LeaveType _leaveType = LeaveType.ANNUAL;
  DateTime? _leaveStart;
  DateTime? _leaveEnd;
  final TextEditingController _leaveNotesCtrl = TextEditingController();

  // Manual slot form state
  String _slotStartTime = '09:00';
  String _slotEndTime = '09:30';
  SessionType _slotSessionType = SessionType.IN_CLINIC;

  @override
  void initState() {
    super.initState();
    _resolveDoctorIdAndLoad();
  }

  @override
  void dispose() {
    _leaveNotesCtrl.dispose();
    super.dispose();
  }

  String _errorMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
      return e.response?.statusMessage ?? e.message ?? 'Network error';
    }
    return e.toString();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _dayName(int day) {
    final d = _kDaysOfWeek.firstWhere((x) => x['value'] == day,
        orElse: () => {'label': day.toString()});
    return d['label'];
  }

  // ── Data loading (unchanged logic, mirrors Angular's availability.component.ts) ──

  Future<void> _resolveDoctorIdAndLoad() async {
    setState(() => _isLoading = true);
    try {
      final userId = ref.read(authNotifierProvider).currentUser?.id;
      if (userId == null) {
        throw Exception('No logged-in user found.');
      }
      final doctors = await ref.read(doctorServiceProvider).getAllDoctors();
      final match = doctors.where((d) => d.userId == userId);
      if (match.isEmpty) {
        throw Exception('Doctor profile not found for this account.');
      }
      _doctorId = match.first.doctorId;
      await _loadClinics();
    } catch (e) {
      _snack('Failed to resolve doctor profile: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadClinics() async {
    if (_doctorId == null) return;
    try {
      final data =
          await ref.read(doctorServiceProvider).getDoctorClinics(_doctorId!);
      final active = data.where((c) => c.isActive).toList();

      if (active.isEmpty) {
        setState(() {
          _clinics = [];
          _selectedDcId = null;
        });
        return;
      }

      final enriched = <DoctorClinicModel>[];
      for (final dc in active) {
        try {
          final clinicDetail = await ref
              .read(clinicServiceProvider)
              .getClinicDetail(dc.clinicId);
          final branches = await ref
              .read(clinicServiceProvider)
              .getClinicBranches(dc.clinicId);
          final branch = branches.where((b) => b.branchId == dc.branchId);
          enriched.add(DoctorClinicModel(
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
            clinicNameEn: clinicDetail.nameEn,
            branchNameEn: branch.isNotEmpty
                ? branch.first.branchNameEn
                : 'Unknown Branch',
          ));
        } catch (_) {
          enriched.add(dc);
        }
      }

      setState(() {
        _clinics = enriched;
        _selectedDcId = enriched.isNotEmpty ? enriched.first.dcId : null;
      });
      if (_selectedDcId != null) {
        await _loadTabData();
      }
    } catch (e) {
      _snack('Failed to load clinics: ${_errorMessage(e)}');
    }
  }

  DoctorClinicModel? get _selectedClinic {
    if (_selectedDcId == null) return null;
    try {
      return _clinics.firstWhere((c) => c.dcId == _selectedDcId);
    } catch (_) {
      return null;
    }
  }

  void _onClinicChange(String? dcId) {
    setState(() => _selectedDcId = dcId);
    if (dcId == null) return;
    _loadTabData();
  }

  void _switchTab(_AvailabilityTab tab) {
    setState(() => _activeTab = tab);
    _loadTabData();
  }

  Future<void> _loadTabData() async {
    if (_selectedDcId == null) return;
    setState(() => _isLoading = true);
    try {
      switch (_activeTab) {
        case _AvailabilityTab.schedule:
          final data = await ref
              .read(doctorServiceProvider)
              .getDcSchedules(_selectedDcId!);
          setState(() => _schedules = data);
          break;
        case _AvailabilityTab.leaves:
          final data =
              await ref.read(doctorServiceProvider).getDcLeave(_selectedDcId!);
          setState(() => _leaves = data);
          break;
        case _AvailabilityTab.slots:
          await _loadSlots();
          break;
      }
    } catch (e) {
      _snack('Failed to load data: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── SCHEDULE ────────────────────────────────────────────────────────
  Future<void> _submitSchedule() async {
    if (_selectedDcId == null) return;
    setState(() => _isLoading = true);
    var st = _schStartTime;
    if (st.length == 5) st += ':00';
    var et = _schEndTime;
    if (et.length == 5) et += ':00';

    try {
      await ref.read(doctorServiceProvider).addSchedule({
        'dcId': _selectedDcId,
        'dayOfWeek': _dayOfWeek,
        'startTime': st,
        'endTime': et,
        'slotDurationMin': _slotDurationMin,
        'sessionType': _schSessionType.value,
        'maxPatients': 20,
        'isActive': true,
        'validFrom': _fmtDate(DateTime.now()),
      });
      _snack('Schedule added');
      await _loadTabData();
    } catch (e) {
      setState(() => _isLoading = false);
      _snack('Error adding schedule: ${_errorMessage(e)}');
    }
  }

  Future<void> _removeSchedule(String id) async {
    final confirmed = await _confirm('Remove this schedule?');
    if (!confirmed) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(doctorServiceProvider).removeSchedule(id);
      _snack('Schedule removed');
      await _loadTabData();
    } catch (e) {
      setState(() => _isLoading = false);
      _snack('Error removing schedule');
    }
  }

  // ── LEAVES ──────────────────────────────────────────────────────────
  Future<void> _submitLeave() async {
    if (_selectedDcId == null || _leaveStart == null || _leaveEnd == null) {
      _snack('Please fill in leave type and dates.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ref.read(doctorServiceProvider).addLeave({
        'dcId': _selectedDcId,
        'leaveType': _leaveType.value,
        'startDate': _fmtDate(_leaveStart!),
        'endDate': _fmtDate(_leaveEnd!),
        'notes': _leaveNotesCtrl.text,
        'isApproved': false,
      });
      _snack('Leave request submitted');
      _leaveNotesCtrl.clear();
      await _loadTabData();
    } catch (e) {
      setState(() => _isLoading = false);
      _snack('Error submitting leave: ${_errorMessage(e)}');
    }
  }

  Future<void> _removeLeave(String id) async {
    final confirmed = await _confirm('Remove this leave request?');
    if (!confirmed) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(doctorServiceProvider).removeLeave(id);
      _snack('Leave removed');
      await _loadTabData();
    } catch (e) {
      setState(() => _isLoading = false);
      _snack('Error removing leave');
    }
  }

  // ── SLOTS ───────────────────────────────────────────────────────────
  Future<void> _loadSlots() async {
    if (_selectedDcId == null) return;
    try {
      final data = await ref
          .read(doctorServiceProvider)
          .getAvailableSlots(_selectedDcId!, date: _fmtDate(_slotFilterDate));
      setState(() => _slots = data);
    } catch (e) {
      setState(() => _slots = []);
      _snack('Failed to load slots: ${_errorMessage(e)}');
    }
  }

  Future<void> _pickSlotFilterDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _slotFilterDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _slotFilterDate = picked);
      await _loadSlots();
    }
  }

  Future<void> _submitSlot() async {
    if (_selectedDcId == null) return;
    setState(() => _isLoading = true);
    try {
      var st = _slotStartTime;
      if (st.length == 5) st += ':00';
      var et = _slotEndTime;
      if (et.length == 5) et += ':00';

      await ref.read(doctorServiceProvider).addSlot({
        'dcId': _selectedDcId,
        'slotDate': _fmtDate(_slotFilterDate),
        'startTime': st,
        'endTime': et,
        'sessionType': _slotSessionType.value,
        'status': SlotStatus.AVAILABLE.value,
      });
      _snack('Slot added');
      await _loadSlots();
    } catch (e) {
      _snack('Error adding slot: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteSlot(String slotId) async {
    final confirmed = await _confirm('Remove this slot?');
    if (!confirmed) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(doctorServiceProvider).removeSlot(slotId);
      _snack('Slot removed');
      await _loadSlots();
    } catch (e) {
      setState(() => _isLoading = false);
      _snack('Error removing slot');
    }
  }

  Future<void> _generateSlotsForDate() async {
    if (_selectedDcId == null) return;
    final javaDayOfWeek = _slotFilterDate.weekday;
    setState(() => _isLoading = true);
    try {
      final schedules =
          await ref.read(doctorServiceProvider).getDcSchedules(_selectedDcId!);
      final matches = schedules
          .where((s) => s.dayOfWeek == javaDayOfWeek && s.isActive)
          .toList();
      if (matches.isEmpty) {
        setState(() => _isLoading = false);
        _snack('No active schedule rule found for this day of the week.');
        return;
      }
      final rule = matches.first;
      final dateStr = _fmtDate(_slotFilterDate);

      DateTime parseHm(String t) {
        final parts = t.split(':');
        return DateTime(_slotFilterDate.year, _slotFilterDate.month,
            _slotFilterDate.day, int.parse(parts[0]), int.parse(parts[1]));
      }

      String toHms(DateTime d) =>
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

      var current = parseHm(rule.startTime);
      final end = parseHm(rule.endTime);
      final slotsToCreate = <Map<String, dynamic>>[];

      while (current.isBefore(end)) {
        final startTimeStr = toHms(current);
        current = current.add(Duration(minutes: rule.slotDurationMin));
        final endTimeStr = toHms(current);
        if (!current.isAfter(end)) {
          slotsToCreate.add({
            'dcId': _selectedDcId,
            'scheduleId': rule.scheduleId,
            'slotDate': dateStr,
            'startTime': startTimeStr,
            'endTime': endTimeStr,
            'sessionType': rule.sessionType.value,
            'status': SlotStatus.AVAILABLE.value,
          });
        }
      }

      if (slotsToCreate.isEmpty) {
        setState(() => _isLoading = false);
        _snack('Schedule times invalid or too short to generate slots.');
        return;
      }

      var failures = 0;
      for (final payload in slotsToCreate) {
        try {
          await ref.read(doctorServiceProvider).addSlot(payload);
        } catch (_) {
          failures++;
        }
      }

      if (failures == 0) {
        _snack('Generated ${slotsToCreate.length} slots successfully.');
      } else {
        _snack('Error generating some slots. They might already exist.');
      }
      await _loadSlots();
    } catch (e) {
      _snack('Failed to load schedules: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _confirm(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirm'),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.dangerRed)),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<String?> _pickTime(String initial) async {
    final parts = initial.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 9,
          minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0),
    );
    if (picked == null) return null;
    return '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Availability'),
      ),
      floatingActionButton: (_selectedDcId == null)
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                switch (_activeTab) {
                  case _AvailabilityTab.schedule:
                    _openScheduleSheet();
                    break;
                  case _AvailabilityTab.leaves:
                    _openLeaveSheet();
                    break;
                  case _AvailabilityTab.slots:
                    _openSlotSheet();
                    break;
                }
              },
              icon: const Icon(Icons.add),
              label: Text(_activeTab == _AvailabilityTab.schedule
                  ? 'Add Rule'
                  : _activeTab == _AvailabilityTab.leaves
                      ? 'Request Leave'
                      : 'Add Slot'),
            ),
      body: SafeArea(
        child: _isLoading && _clinics.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async {
                  if (_selectedDcId != null) await _loadTabData();
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  children: [
                    const Text(
                      'Manage clinic schedules, time off, and booking slots.',
                      style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 14),
                    _buildClinicSelector(),
                    if (_selectedClinic != null) ...[
                      const SizedBox(height: 14),
                      _buildPlacementCard(_selectedClinic!),
                    ],
                    if (_clinics.isEmpty && !_isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'No active clinic placements found for your profile.',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                        ),
                      ),
                    if (_selectedDcId != null) ...[
                      const SizedBox(height: 18),
                      _buildTabBar(),
                      const SizedBox(height: 14),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        _buildTabContent(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildClinicSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Clinic / Branch',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedDcId,
              isExpanded: true,
              decoration: const InputDecoration(
                hintText: '-- Choose a Clinic/Branch --',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: _clinics
                  .map((c) => DropdownMenuItem(
                        value: c.dcId,
                        child: Text(
                          '🏥 ${c.clinicNameEn ?? 'Clinic'} - ${c.branchNameEn ?? 'Branch'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: _onClinicChange,
            ),
          ],
        ),
      ),
    );
  }

  // Mirrors .placement-info-card in availability.component.css.
  Widget _buildPlacementCard(DoctorClinicModel c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF0F9FF), Color(0xFFE8F4FD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBAE6FD), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 4, color: const Color(0xFF0EA5E9)),
              const SizedBox(width: 12),
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: const Text('🏥', style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.clinicNameEn ?? 'Clinic',
                        style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B))),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _chip(
                          c.isPrimary
                              ? '⭐ Primary Specialist'
                              : '👤 Consultant',
                          c.isPrimary
                              ? const Color(0xFFDCFCE7)
                              : const Color(0xFFF1F5F9),
                          c.isPrimary
                              ? const Color(0xFF166534)
                              : const Color(0xFF475569),
                        ),
                        _chip(
                          c.isActive ? '● Active' : '● Inactive',
                          c.isActive
                              ? const Color(0xFFDCFCE7)
                              : const Color(0xFFF1F5F9),
                          c.isActive
                              ? const Color(0xFF166534)
                              : const Color(0xFF64748B),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text('📍 ${c.branchNameEn ?? 'Branch'}',
                            style: const TextStyle(
                                fontSize: 12.5, color: Color(0xFF64748B))),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            (c.department ?? 'General Practice').toUpperCase(),
                            style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0369A1),
                                letterSpacing: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFBAE6FD)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 3.2,
            children: [
              _stat('CONSULTATION FEE', 'SAR ${c.consultationFeeSar ?? '—'}',
                  valueColor: const Color(0xFF16A34A)),
              _stat('JOINED SINCE', c.startDate ?? '—'),
              if (c.endDate != null && c.endDate!.isNotEmpty)
                _stat('CONTRACT UNTIL', c.endDate!,
                    valueColor: const Color(0xFFB45309)),
              _stat('TOTAL PLACEMENTS', '${_clinics.length} Clinic(s)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style:
              TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _stat(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFF94A3B8),
                letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: valueColor ?? const Color(0xFF1E293B))),
      ],
    );
  }

  Widget _buildTabBar() {
    Widget seg(String label, _AvailabilityTab tab) {
      final selected = _activeTab == tab;
      return Expanded(
        child: GestureDetector(
          onTap: () => _switchTab(tab),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primaryTeal : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppTheme.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.backgroundApp,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Row(
        children: [
          seg('🗓️ Schedule', _AvailabilityTab.schedule),
          seg('🏖️ Leaves', _AvailabilityTab.leaves),
          seg('⚡ Slots', _AvailabilityTab.slots),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_activeTab) {
      case _AvailabilityTab.schedule:
        return _buildScheduleTab();
      case _AvailabilityTab.leaves:
        return _buildLeavesTab();
      case _AvailabilityTab.slots:
        return _buildSlotsTab();
    }
  }

  // ── SCHEDULE TAB ────────────────────────────────────────────────────
  Widget _buildScheduleTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primaryLightTeal,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ℹ️', style: TextStyle(fontSize: 16)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Add weekly recurring schedules. These auto-generate your bookable slots.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_schedules.isEmpty)
          _emptyState('No schedule rules defined yet.')
        else
          ..._schedules.map((s) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppTheme.borderGray),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_dayName(s.dayOfWeek),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text('${s.startTime} - ${s.endTime}',
                              style: const TextStyle(
                                  fontSize: 12.5, color: AppTheme.textMuted)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: [
                              _chip('⏱️ ${s.slotDurationMin} min',
                                  AppTheme.backgroundApp, AppTheme.textMuted),
                              _chip(
                                  s.sessionType.value.replaceAll('_', ' '),
                                  AppTheme.primaryLightTeal,
                                  AppTheme.primaryDarkTeal),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppTheme.dangerRed),
                      onPressed: () => _removeSchedule(s.scheduleId),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  // ── LEAVES TAB ──────────────────────────────────────────────────────
  Widget _buildLeavesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_leaves.isEmpty)
          _emptyState('No leave requests found.')
        else
          ..._leaves.map((l) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppTheme.borderGray),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                    l.leaveType.value.replaceAll('_', ' '),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14)),
                              ),
                              _chip(
                                l.isApproved ? '✓ Approved' : '⏳ Pending',
                                l.isApproved
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFFFF7ED),
                                l.isApproved
                                    ? const Color(0xFF166534)
                                    : const Color(0xFFB45309),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('${l.startDate} to ${l.endDate}',
                              style: const TextStyle(
                                  fontSize: 12.5, color: AppTheme.textMuted)),
                          if (l.notes != null && l.notes!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(l.notes!,
                                style: const TextStyle(
                                    fontSize: 12, color: AppTheme.textMuted)),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppTheme.dangerRed),
                      onPressed: () => _removeLeave(l.leaveId),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  // ── SLOTS TAB ───────────────────────────────────────────────────────
  Widget _buildSlotsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 15),
                label: Text(_fmtDate(_slotFilterDate)),
                onPressed: _pickSlotFilterDate,
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.bolt, size: 16),
              label: const Text('Auto-Generate'),
              onPressed: _generateSlotsForDate,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_slots.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.borderGray),
              borderRadius: BorderRadius.circular(12),
              color: AppTheme.backgroundApp,
            ),
            child: Column(
              children: [
                const Text('No Slots Available',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                    'Generate slots automatically from your weekly schedule rules.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _generateSlotsForDate,
                  child: const Text('⚡ Auto-Generate Now'),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
            ),
            itemCount: _slots.length,
            itemBuilder: (context, i) {
              final slot = _slots[i];
              final start = (slot['startTime'] as String?) ?? '';
              final status = slot['status'] ?? 'AVAILABLE';
              final isAvailable = status == 'AVAILABLE';
              final isBlocked = status == 'BLOCKED' || status == 'NO_SHOW';
              final bg = isAvailable
                  ? const Color(0xFFDCFCE7)
                  : isBlocked
                      ? const Color(0xFFE2E8F0)
                      : const Color(0xFFDBEAFE);
              final border = isAvailable
                  ? AppTheme.primaryTeal
                  : isBlocked
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF3B82F6);
              final fg = isAvailable
                  ? AppTheme.primaryDarkTeal
                  : isBlocked
                      ? const Color(0xFF64748B)
                      : const Color(0xFF1E40AF);

              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bg,
                  border: Border.all(color: border, width: 1.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          start.length >= 5 ? start.substring(0, 5) : start,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: fg),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (slot['sessionType'] ?? '').toString(),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(fontSize: 9.5, color: fg),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(status,
                              style: TextStyle(fontSize: 8.5, color: fg)),
                        ),
                      ],
                    ),
                    if (isAvailable)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: GestureDetector(
                          onTap: () => _deleteSlot(slot['slotId'].toString()),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                size: 12, color: AppTheme.dangerRed),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _emptyState(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30),
      alignment: Alignment.center,
      child: Text(text, style: const TextStyle(color: AppTheme.textMuted)),
    );
  }

  // ── Bottom sheet shell (same pattern as patients screen) ────────────
  Widget _sheetScaffold({
    required String title,
    required Widget child,
    required VoidCallback onSubmit,
    required String submitLabel,
  }) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppTheme.borderGray,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text(title,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryTeal)),
            const SizedBox(height: 16),
            child,
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onSubmit,
                child: Text(submitLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openScheduleSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => _sheetScaffold(
          title: 'Add Schedule Rule',
          submitLabel: '+ Add Rule',
          onSubmit: () {
            Navigator.pop(ctx);
            _submitSchedule();
          },
          child: Column(
            children: [
              DropdownButtonFormField<int>(
                initialValue: _dayOfWeek,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Day of Week *'),
                items: _kDaysOfWeek
                    .map((d) => DropdownMenuItem<int>(
                        value: d['value'], child: Text(d['label'])))
                    .toList(),
                onChanged: (v) =>
                    setSheetState(() => setState(() => _dayOfWeek = v ?? 1)),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await _pickTime(_schStartTime);
                      if (t != null) {
                        setSheetState(() => setState(() => _schStartTime = t));
                      }
                    },
                    child: Text('Start: $_schStartTime'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await _pickTime(_schEndTime);
                      if (t != null) {
                        setSheetState(() => setState(() => _schEndTime = t));
                      }
                    },
                    child: Text('End: $_schEndTime'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextFormField(
                initialValue: _slotDurationMin.toString(),
                decoration:
                    const InputDecoration(labelText: 'Slot Duration (min) *'),
                keyboardType: TextInputType.number,
                onChanged: (v) =>
                    _slotDurationMin = int.tryParse(v) ?? _slotDurationMin,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<SessionType>(
                initialValue: _schSessionType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Session Type *'),
                items: SessionType.values
                    .map((s) => DropdownMenuItem(
                        value: s, child: Text(s.value.replaceAll('_', ' '))))
                    .toList(),
                onChanged: (v) => setSheetState(() =>
                    setState(() => _schSessionType = v ?? _schSessionType)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openLeaveSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => _sheetScaffold(
          title: 'Request Leave',
          submitLabel: 'Request Leave',
          onSubmit: () {
            Navigator.pop(ctx);
            _submitLeave();
          },
          child: Column(
            children: [
              DropdownButtonFormField<LeaveType>(
                initialValue: _leaveType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Leave Type *'),
                items: LeaveType.values
                    .map((l) => DropdownMenuItem(
                        value: l, child: Text(l.value.replaceAll('_', ' '))))
                    .toList(),
                onChanged: (v) => setSheetState(
                    () => setState(() => _leaveType = v ?? _leaveType)),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _leaveStart ?? DateTime.now(),
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setSheetState(
                            () => setState(() => _leaveStart = picked));
                      }
                    },
                    child: Text(_leaveStart == null
                        ? 'Start Date *'
                        : _fmtDate(_leaveStart!)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _leaveEnd ?? DateTime.now(),
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setSheetState(() => setState(() => _leaveEnd = picked));
                      }
                    },
                    child: Text(_leaveEnd == null
                        ? 'End Date *'
                        : _fmtDate(_leaveEnd!)),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextFormField(
                controller: _leaveNotesCtrl,
                decoration: const InputDecoration(
                    labelText: 'Notes', hintText: 'Optional'),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSlotSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => _sheetScaffold(
          title: 'Add Manual Slot — ${_fmtDate(_slotFilterDate)}',
          submitLabel: 'Add Single Slot',
          onSubmit: () {
            Navigator.pop(ctx);
            _submitSlot();
          },
          child: Column(
            children: [
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await _pickTime(_slotStartTime);
                      if (t != null) {
                        setSheetState(() => setState(() => _slotStartTime = t));
                      }
                    },
                    child: Text('Start: $_slotStartTime'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await _pickTime(_slotEndTime);
                      if (t != null) {
                        setSheetState(() => setState(() => _slotEndTime = t));
                      }
                    },
                    child: Text('End: $_slotEndTime'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<SessionType>(
                initialValue: _slotSessionType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Session Type *'),
                items: SessionType.values
                    .map((s) => DropdownMenuItem(
                        value: s, child: Text(s.value.replaceAll('_', ' '))))
                    .toList(),
                onChanged: (v) => setSheetState(() =>
                    setState(() => _slotSessionType = v ?? _slotSessionType)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

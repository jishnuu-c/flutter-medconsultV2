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

  // Same pattern as consultations_screen: no "my doctor" endpoint, so match
  // logged-in user's userId against /doctors/all to resolve doctorId first.
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

  // Mirrors Angular's loadClinics(): fetch active clinic placements, then
  // enrich each with clinicNameEn / branchNameEn via clinic + branches calls.
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
    try {
      await ref.read(doctorServiceProvider).addSchedule({
        'dcId': _selectedDcId,
        'dayOfWeek': _dayOfWeek,
        'startTime': _schStartTime,
        'endTime': _schEndTime,
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

  // Mirrors Angular's generateSlotsForDate(): find the active schedule rule
  // for the filter date's day-of-week (1=Monday..7=Sunday), then create
  // sequential slots from startTime to endTime in slotDurationMin steps.
  Future<void> _generateSlotsForDate() async {
    if (_selectedDcId == null) return;
    final javaDayOfWeek =
        _slotFilterDate.weekday; // DateTime.weekday: 1=Mon..7=Sun already
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

  // ── Responsive helpers ──────────────────────────────────────────────
  bool _isMobile(BuildContext c) => MediaQuery.of(c).size.width < 600;

  // Form field width: full-row on mobile so fields stack instead of
  // getting squeezed, fixed desired width on tablet/desktop.
  double _fw(BuildContext c, double desired) {
    if (!_isMobile(c)) return desired;
    final avail = MediaQuery.of(c).size.width - 24 * 2 - 16 * 2;
    return avail < desired ? avail.clamp(140, double.infinity) : desired;
  }

  // Slot card width: 2 columns on mobile, fixed size on tablet/desktop.
  double _slotCardWidth(BuildContext c) {
    if (!_isMobile(c)) return 140;
    final avail = MediaQuery.of(c).size.width - 24 * 2 - 16 * 2 - 12;
    return (avail / 2).clamp(110, 200);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: EdgeInsets.all(_isMobile(context) ? 12 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🗓️ My Availability & Schedule',
              style: TextStyle(
                  fontSize: _isMobile(context) ? 18 : 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain),
            ),
            const SizedBox(height: 4),
            const Text(
              'Manage clinic schedules, time off, and booking slots efficiently.',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),

            // Clinic selector
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select Clinic/Branch to Manage',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedDcId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          hintText: '-- Choose a Clinic/Branch --'),
                      items: _clinics
                          .map((c) => DropdownMenuItem(
                                value: c.dcId,
                                child: Text(
                                  '🏥 ${c.clinicNameEn ?? 'Clinic'} - ${c.branchNameEn ?? 'Branch'} (${c.department})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: _onClinicChange,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (_isLoading && _clinics.isEmpty)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_clinics.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                      'No active clinic placements found for your profile.',
                      style: TextStyle(color: AppTheme.textMuted)),
                ),
              )
            else if (_selectedDcId != null)
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _isMobile(context)
                            ? SizedBox(
                                height: 44,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    _tabButton('🗓️ Schedule',
                                        _AvailabilityTab.schedule),
                                    const SizedBox(width: 8),
                                    _tabButton(
                                        '🏖️ Leaves', _AvailabilityTab.leaves),
                                    const SizedBox(width: 8),
                                    _tabButton(
                                        '⚡ Slots', _AvailabilityTab.slots),
                                  ],
                                ),
                              )
                            : Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _tabButton('🗓️ Weekly Schedule Rules',
                                      _AvailabilityTab.schedule),
                                  _tabButton('🏖️ Time Off / Leaves',
                                      _AvailabilityTab.leaves),
                                  _tabButton('⚡ Slots Generator',
                                      _AvailabilityTab.slots),
                                ],
                              ),
                        const Divider(height: 24),
                        Expanded(
                          child: _isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : SingleChildScrollView(
                                  child: _buildTabContent(),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(String label, _AvailabilityTab tab) {
    final selected = _activeTab == tab;
    return selected
        ? ElevatedButton(onPressed: () => _switchTab(tab), child: Text(label))
        : OutlinedButton(onPressed: () => _switchTab(tab), child: Text(label));
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

  // ── SCHEDULE TAB UI ─────────────────────────────────────────────────
  Widget _buildScheduleTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primaryLightTeal,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ℹ️', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('About Schedule Rules',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 2),
                    Text(
                        'Add weekly recurring schedules. The system uses these rules to automatically generate your bookable slots for future dates.',
                        style:
                            TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(
                  width: _fw(context, 160),
                  child: DropdownButtonFormField<int>(
                    initialValue: _dayOfWeek,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Day of Week *'),
                    items: _kDaysOfWeek
                        .map((d) => DropdownMenuItem<int>(
                            value: d['value'], child: Text(d['label'])))
                        .toList(),
                    onChanged: (v) => setState(() => _dayOfWeek = v ?? 1),
                  ),
                ),
                SizedBox(
                  width: _fw(context, 140),
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await _pickTime(_schStartTime);
                      if (t != null) setState(() => _schStartTime = t);
                    },
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Start: $_schStartTime', maxLines: 1),
                    ),
                  ),
                ),
                SizedBox(
                  width: _fw(context, 140),
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await _pickTime(_schEndTime);
                      if (t != null) setState(() => _schEndTime = t);
                    },
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('End: $_schEndTime', maxLines: 1),
                    ),
                  ),
                ),
                SizedBox(
                  width: _fw(context, 120),
                  child: TextFormField(
                    initialValue: _slotDurationMin.toString(),
                    decoration:
                        const InputDecoration(labelText: 'Slot (min) *'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) =>
                        _slotDurationMin = int.tryParse(v) ?? _slotDurationMin,
                  ),
                ),
                SizedBox(
                  width: _fw(context, 160),
                  child: DropdownButtonFormField<SessionType>(
                    initialValue: _schSessionType,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Type *'),
                    items: SessionType.values
                        .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s.value.replaceAll('_', ' '),
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _schSessionType = v ?? _schSessionType),
                  ),
                ),
                SizedBox(
                  width: _fw(context, double.infinity),
                  child: ElevatedButton(
                    onPressed: _submitSchedule,
                    child: const Text('+ Add Rule'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _schedules.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: Text('No schedule rules defined yet.',
                        style: TextStyle(color: AppTheme.textMuted))),
              )
            : Column(
                children: _schedules.map((s) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_dayName(s.dayOfWeek),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        '${s.startTime} - ${s.endTime} · ⏱️ ${s.slotDurationMin} min · ${s.sessionType.value}'),
                    trailing: TextButton(
                      onPressed: () => _removeSchedule(s.scheduleId),
                      child: const Text('× Delete',
                          style: TextStyle(color: AppTheme.dangerRed)),
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  // ── LEAVES TAB UI ───────────────────────────────────────────────────
  Widget _buildLeavesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(
                  width: _fw(context, 180),
                  child: DropdownButtonFormField<LeaveType>(
                    initialValue: _leaveType,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Leave Type *'),
                    items: LeaveType.values
                        .map((l) => DropdownMenuItem(
                            value: l,
                            child: Text(l.value.replaceAll('_', ' '),
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _leaveType = v ?? _leaveType),
                  ),
                ),
                SizedBox(
                  width: _fw(context, 160),
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _leaveStart ?? DateTime.now(),
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _leaveStart = picked);
                    },
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                          _leaveStart == null
                              ? 'Start Date *'
                              : _fmtDate(_leaveStart!),
                          maxLines: 1),
                    ),
                  ),
                ),
                SizedBox(
                  width: _fw(context, 160),
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _leaveEnd ?? DateTime.now(),
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _leaveEnd = picked);
                    },
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                          _leaveEnd == null
                              ? 'End Date *'
                              : _fmtDate(_leaveEnd!),
                          maxLines: 1),
                    ),
                  ),
                ),
                SizedBox(
                  width: _fw(context, 220),
                  child: TextFormField(
                    controller: _leaveNotesCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Notes', hintText: 'Optional'),
                  ),
                ),
                SizedBox(
                  width: _fw(context, double.infinity),
                  child: ElevatedButton(
                    onPressed: _submitLeave,
                    child: const Text('Request Leave'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _leaves.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: Text('No leave requests found.',
                        style: TextStyle(color: AppTheme.textMuted))),
              )
            : Column(
                children: _leaves.map((l) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.leaveType.value,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        '${l.startDate} to ${l.endDate}${l.notes != null && l.notes!.isNotEmpty ? ' · ${l.notes}' : ''}'),
                    trailing: Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          label:
                              Text(l.isApproved ? '✓ Approved' : '⏳ Pending'),
                          backgroundColor: l.isApproved
                              ? Colors.green.shade100
                              : Colors.orange.shade100,
                        ),
                        TextButton(
                          onPressed: () => _removeLeave(l.leaveId),
                          child: const Text('× Delete',
                              style: TextStyle(color: AppTheme.dangerRed)),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  // ── SLOTS TAB UI ────────────────────────────────────────────────────
  Widget _buildSlotsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.borderGray.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text('Date: ${_fmtDate(_slotFilterDate)}'),
                onPressed: _pickSlotFilterDate,
              ),
              OutlinedButton(
                  onPressed: _loadSlots, child: const Text('Load Slots')),
              ElevatedButton(
                onPressed: _generateSlotsForDate,
                child: const Text('⚡ Auto-Generate'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('+ Add Manual Single Slot',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    SizedBox(
                      width: _fw(context, 140),
                      child: OutlinedButton(
                        onPressed: () async {
                          final t = await _pickTime(_slotStartTime);
                          if (t != null) setState(() => _slotStartTime = t);
                        },
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Start: $_slotStartTime', maxLines: 1),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: _fw(context, 140),
                      child: OutlinedButton(
                        onPressed: () async {
                          final t = await _pickTime(_slotEndTime);
                          if (t != null) setState(() => _slotEndTime = t);
                        },
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('End: $_slotEndTime', maxLines: 1),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: _fw(context, 160),
                      child: DropdownButtonFormField<SessionType>(
                        initialValue: _slotSessionType,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Type *'),
                        items: SessionType.values
                            .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s.value.replaceAll('_', ' '),
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(
                            () => _slotSessionType = v ?? _slotSessionType),
                      ),
                    ),
                    SizedBox(
                      width: _fw(context, double.infinity),
                      child: ElevatedButton(
                        onPressed: _submitSlot,
                        child: const Text('Add Single Slot'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_slots.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.borderGray),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                const Text('No Slots Available for Selected Date',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const SizedBox(height: 4),
                const Text(
                    'Click below to generate slots automatically from your weekly schedule rules.',
                    style: TextStyle(color: AppTheme.textMuted),
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
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _slots.map((slot) {
              final start = (slot['startTime'] as String?) ?? '';
              final status = slot['status'] ?? 'AVAILABLE';
              final isAvailable = status == 'AVAILABLE';
              final isBlocked = status == 'BLOCKED' || status == 'NO_SHOW';
              return Container(
                width: _slotCardWidth(context),
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                decoration: BoxDecoration(
                  color: isAvailable
                      ? AppTheme.primaryLightTeal
                      : isBlocked
                          ? AppTheme.borderGray.withValues(alpha: 0.4)
                          : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderGray),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(start.length >= 5 ? start.substring(0, 5) : start,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(slot['sessionType'] ?? '',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textMuted)),
                        const SizedBox(height: 8),
                        Chip(
                          label: Text(status,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    if (isAvailable)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close,
                              size: 16, color: AppTheme.dangerRed),
                          onPressed: () =>
                              _deleteSlot(slot['slotId'].toString()),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

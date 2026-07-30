import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/doctor_models.dart';
import '../data/doctor_service.dart';

class DoctorsScreen extends ConsumerStatefulWidget {
  const DoctorsScreen({super.key});

  @override
  ConsumerState<DoctorsScreen> createState() => _DoctorsScreenState();
}

class _DoctorsScreenState extends ConsumerState<DoctorsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _mainTabController;

  bool _isLoading = false;
  List<DoctorModel> _doctors = [];

  // Mock Placements
  List<DoctorClinicModel> _placements = [];

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 2, vsync: this);
    _loadDoctorsData();
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    super.dispose();
  }

  Future<void> _loadDoctorsData() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref.read(doctorServiceProvider).getAllDoctors();
      setState(() => _doctors = res);
    } catch (_) {
      _populateMockDoctors();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateMockDoctors() {
    _doctors = [
      DoctorModel(
        doctorId: 'doc-1',
        userId: 'usr-1',
        fullName: 'Dr. Tariq Al-Mansoor',
        mohRegistrationNumber: 'MOH-DOC-1002',
        mohVerified: true,
        title: DoctorTitle.DR,
        experienceYears: 12,
        overallRating: 4.9,
        reviewCount: 48,
        consultationFeeSar: 250.0,
        isActive: true,
      ),
      DoctorModel(
        doctorId: 'doc-2',
        userId: 'usr-2',
        fullName: 'Dr. Sarah Jenkins',
        mohRegistrationNumber: 'MOH-DOC-1005',
        mohVerified: true,
        title: DoctorTitle.PROF,
        experienceYears: 8,
        overallRating: 5.0,
        reviewCount: 92,
        consultationFeeSar: 200.0,
        isActive: true,
      ),
    ];

    _placements = [
      DoctorClinicModel(
        dcId: 'dc-1',
        doctorId: 'doc-1',
        clinicId: 'cl-1',
        branchId: 'b-1',
        department: 'Cardiology Department',
        consultationFeeSar: 250.0,
        isPrimary: true,
        startDate: '2024-01-01',
        isActive: true,
        clinicNameEn: 'Al-Habib Medical Center',
        branchNameEn: 'Olaya Main Branch',
      ),
    ];
  }

  void _openPlacementDialog() {
    String selectedDocId = _doctors.isNotEmpty ? _doctors.first.doctorId : '';
    final deptController = TextEditingController(text: 'General Practice');
    final feeController = TextEditingController(text: '150');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Doctor Placement Link'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedDocId,
                decoration: const InputDecoration(labelText: 'Select Doctor'),
                items: _doctors.map((d) {
                  return DropdownMenuItem(
                      value: d.doctorId, child: Text(d.fullName));
                }).toList(),
                onChanged: (val) {
                  if (val != null) selectedDocId = val;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: deptController,
                  decoration: const InputDecoration(labelText: 'Department')),
              const SizedBox(height: 12),
              TextField(
                  controller: feeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Consultation Fee (SAR)')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final payload = {
                'doctorId': selectedDocId,
                'clinicId': 'cl-1',
                'branchId': 'b-1',
                'department': deptController.text.trim(),
                'consultationFeeSar':
                    double.tryParse(feeController.text) ?? 150.0,
                'isPrimary': true,
                'startDate': DateTime.now().toString().split(' ')[0],
                'isActive': true,
              };
              try {
                await ref.read(doctorServiceProvider).addDoctorClinic(payload);
              } catch (_) {}
              if (mounted) Navigator.pop(ctx);
              _loadDoctorsData();
            },
            child: const Text('Create Link'),
          ),
        ],
      ),
    );
  }

  void _openScheduleDialog(DoctorClinicModel dc) async {
    List<DoctorScheduleModel> schedules = [];
    try {
      schedules = await ref.read(doctorServiceProvider).getDcSchedules(dc.dcId);
    } catch (_) {}

    int dayOfWeek = 0;
    SessionType sessionType = SessionType.IN_CLINIC;
    final startController = TextEditingController(text: '09:00');
    final endController = TextEditingController(text: '17:00');
    final durationController = TextEditingController(text: '30');
    final maxPatientsController = TextEditingController(text: '16');
    bool isActive = true;
    final days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday'
    ];

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('📅 Consultation Schedule — ${_doctorName(dc.doctorId)}'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Department: ${dc.department}  ·  Fee: SAR ${dc.consultationFeeSar.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textMuted)),
                  const SizedBox(height: 12),
                  const Text('📋 Configured Working Schedules',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  if (schedules.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No working schedule rules configured yet.',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted)),
                    )
                  else
                    ...schedules.map((s) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(6)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '🗓️ ${days[s.dayOfWeek]} · ${s.sessionType.value}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                    Text(
                                        '⏰ ${s.startTime} – ${s.endTime} | ${s.slotDurationMin}min slots | Max ${s.maxPatients}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textMuted)),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(doctorServiceProvider)
                                        .removeSchedule(s.scheduleId);
                                  } catch (_) {}
                                  if (mounted) Navigator.pop(ctx);
                                  _openScheduleDialog(dc);
                                },
                                child: const Text('Remove',
                                    style:
                                        TextStyle(color: AppTheme.dangerRed)),
                              ),
                            ],
                          ),
                        )),
                  const Divider(height: 24),
                  const Text('+ Configure New Working Schedule Rule',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: dayOfWeek,
                    decoration: const InputDecoration(labelText: 'Day of Week'),
                    items: List.generate(
                        7,
                        (i) =>
                            DropdownMenuItem(value: i, child: Text(days[i]))),
                    onChanged: (v) => setDialogState(() => dayOfWeek = v ?? 0),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<SessionType>(
                    initialValue: sessionType,
                    decoration:
                        const InputDecoration(labelText: 'Session Mode'),
                    items: SessionType.values
                        .map((s) =>
                            DropdownMenuItem(value: s, child: Text(s.value)))
                        .toList(),
                    onChanged: (v) => setDialogState(
                        () => sessionType = v ?? SessionType.IN_CLINIC),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: startController,
                            decoration: const InputDecoration(
                                labelText: 'Start Time'))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextField(
                            controller: endController,
                            decoration:
                                const InputDecoration(labelText: 'End Time'))),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: durationController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Slot Duration (mins)'))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextField(
                            controller: maxPatientsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Max Patients'))),
                  ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active Rule'),
                    value: isActive,
                    onChanged: (v) => setDialogState(() => isActive = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
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
                  'maxPatients': int.tryParse(maxPatientsController.text) ?? 16,
                  'isActive': isActive,
                };
                try {
                  await ref.read(doctorServiceProvider).addSchedule(payload);
                } catch (_) {}
                if (mounted) Navigator.pop(ctx);
                _openScheduleDialog(dc);
              },
              child: const Text('Add Schedule Rule'),
            ),
          ],
        ),
      ),
    );
  }

  void _openLeaveDialog(DoctorClinicModel dc) async {
    List<DoctorLeaveModel> leaves = [];
    try {
      leaves = await ref.read(doctorServiceProvider).getDcLeave(dc.dcId);
    } catch (_) {}
    final pending = leaves.where((l) => !l.isApproved).length;
    final approved = leaves.where((l) => l.isApproved).length;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('🏖️ Leave Requests — ${_doctorName(dc.doctorId)}'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [
                      Text('${leaves.length}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18)),
                      const Text('Total', style: TextStyle(fontSize: 11))
                    ]),
                    Column(children: [
                      Text('$pending',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.orange)),
                      const Text('Pending', style: TextStyle(fontSize: 11))
                    ]),
                    Column(children: [
                      Text('$approved',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.green)),
                      const Text('Approved', style: TextStyle(fontSize: 11))
                    ]),
                  ],
                ),
                const SizedBox(height: 16),
                if (leaves.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No leave requests found for this doctor.',
                        style:
                            TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  )
                else
                  ...leaves.map((l) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: l.isApproved
                                  ? Colors.green.shade200
                                  : Colors.orange.shade200),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Chip(
                                        label: Text(l.leaveType.value,
                                            style:
                                                const TextStyle(fontSize: 11)),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap),
                                    const SizedBox(width: 6),
                                    Text(
                                        l.isApproved
                                            ? '✅ Approved'
                                            : '⏳ Pending',
                                        style: const TextStyle(fontSize: 12)),
                                  ]),
                                  const SizedBox(height: 4),
                                  Text('📅 ${l.startDate} → ${l.endDate}',
                                      style: const TextStyle(fontSize: 12)),
                                  if (l.notes != null && l.notes!.isNotEmpty)
                                    Text('📝 ${l.notes}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textMuted)),
                                ],
                              ),
                            ),
                            if (!l.isApproved)
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(doctorServiceProvider)
                                        .updateLeave(
                                            l.leaveId, {'isApproved': true});
                                  } catch (_) {}
                                  if (mounted) Navigator.pop(ctx);
                                  _openLeaveDialog(dc);
                                },
                                child: const Text('✅ Approve'),
                              ),
                            TextButton(
                              onPressed: () async {
                                try {
                                  if (l.isApproved) {
                                    await ref
                                        .read(doctorServiceProvider)
                                        .updateLeave(
                                            l.leaveId, {'isApproved': false});
                                  } else {
                                    await ref
                                        .read(doctorServiceProvider)
                                        .removeLeave(l.leaveId);
                                  }
                                } catch (_) {}
                                if (mounted) Navigator.pop(ctx);
                                _openLeaveDialog(dc);
                              },
                              child: Text(
                                  l.isApproved ? '↩️ Revoke' : '❌ Reject',
                                  style: const TextStyle(
                                      color: AppTheme.dangerRed)),
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  String _doctorName(String doctorId) {
    return _doctors
        .firstWhere((d) => d.doctorId == doctorId,
            orElse: () => DoctorModel(
                doctorId: '',
                userId: '',
                fullName: 'Doctor',
                mohRegistrationNumber: '',
                mohVerified: true,
                title: DoctorTitle.DR,
                experienceYears: 0,
                overallRating: 0,
                reviewCount: 0,
                consultationFeeSar: 0,
                isActive: true))
        .fullName;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Doctors Management',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMain),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Manage doctor clinic placements, schedules, qualifications, and specialties.',
                  style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const Key('add_placement_btn'),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Doctor Placement'),
                    onPressed: _openPlacementDialog,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // TabBar
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: AppTheme.borderGray)),
              ),
              child: TabBar(
                controller: _mainTabController,
                labelColor: AppTheme.primaryTeal,
                unselectedLabelColor: AppTheme.textMuted,
                tabs: const [
                  Tab(text: 'Clinic Placements'),
                  Tab(text: 'Doctor Profiles'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: TabBarView(
                controller: _mainTabController,
                children: [
                  // Tab 1: Placements
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _placements.isEmpty
                          ? const Center(
                              child: Text('No placements found.',
                                  style: TextStyle(color: AppTheme.textMuted)))
                          : ListView.separated(
                              itemCount: _placements.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final p = _placements[index];
                                final docName = _doctors
                                    .firstWhere((d) => d.doctorId == p.doctorId,
                                        orElse: () => DoctorModel(
                                            doctorId: '',
                                            userId: '',
                                            fullName: 'Dr. Tariq',
                                            mohRegistrationNumber: '',
                                            mohVerified: true,
                                            title: DoctorTitle.DR,
                                            experienceYears: 5,
                                            overallRating: 5,
                                            reviewCount: 0,
                                            consultationFeeSar: 150,
                                            isActive: true))
                                    .fullName;
                                return Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(docName,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16)),
                                            ),
                                            Chip(
                                              label: Text(
                                                  p.isActive
                                                      ? 'Active'
                                                      : 'Inactive',
                                                  style: const TextStyle(
                                                      fontSize: 12)),
                                              backgroundColor: p.isActive
                                                  ? AppTheme.primaryLightTeal
                                                  : Colors.grey[200],
                                              visualDensity:
                                                  VisualDensity.compact,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.calendar_month,
                                                  size: 18),
                                              tooltip: 'Consultation Schedule',
                                              onPressed: () =>
                                                  _openScheduleDialog(p),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.beach_access,
                                                  size: 18),
                                              tooltip: 'Leave Requests',
                                              onPressed: () =>
                                                  _openLeaveDialog(p),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete,
                                                  size: 18,
                                                  color: AppTheme.dangerRed),
                                              onPressed: () async {
                                                try {
                                                  await ref
                                                      .read(
                                                          doctorServiceProvider)
                                                      .removeDoctorClinic(
                                                          p.dcId);
                                                } catch (_) {}
                                                _loadDoctorsData();
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                            '${p.clinicNameEn ?? 'Al-Habib Center'} (${p.branchNameEn ?? 'Main Branch'})',
                                            style: const TextStyle(
                                                fontSize: 13,
                                                color: AppTheme.textMain)),
                                        const SizedBox(height: 4),
                                        Text(
                                            '${p.department} · SAR ${p.consultationFeeSar.toStringAsFixed(0)}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.textMuted)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                  // Tab 2: Doctor Profiles
                  Card(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _doctors.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final doc = _doctors[index];
                        return ListTile(
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
                          title: Text(doc.fullName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              'MOH Reg: ${doc.mohRegistrationNumber} | ${doc.experienceYears} Yrs Exp'),
                          trailing: Chip(
                            label: Text('★ ${doc.overallRating}'),
                            backgroundColor: Colors.amber[100],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

class _DoctorsScreenState extends ConsumerState<DoctorsScreen> with SingleTickerProviderStateMixin {
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
                  return DropdownMenuItem(value: d.doctorId, child: Text(d.fullName));
                }).toList(),
                onChanged: (val) {
                  if (val != null) selectedDocId = val;
                },
              ),
              const SizedBox(height: 12),
              TextField(controller: deptController, decoration: const InputDecoration(labelText: 'Department')),
              const SizedBox(height: 12),
              TextField(controller: feeController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Consultation Fee (SAR)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final payload = {
                'doctorId': selectedDocId,
                'clinicId': 'cl-1',
                'branchId': 'b-1',
                'department': deptController.text.trim(),
                'consultationFeeSar': double.tryParse(feeController.text) ?? 150.0,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Doctors Management',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Manage doctor clinic placements, schedules, qualifications, and specialties.',
                        style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  key: const Key('add_placement_btn'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Doctor Placement'),
                  onPressed: _openPlacementDialog,
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
                  Card(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : SingleChildScrollView(
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Doctor')),
                                DataColumn(label: Text('Clinic & Branch')),
                                DataColumn(label: Text('Department')),
                                DataColumn(label: Text('Fee (SAR)')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('Actions')),
                              ],
                              rows: _placements.map((p) {
                                final docName = _doctors.firstWhere((d) => d.doctorId == p.doctorId, orElse: () => DoctorModel(doctorId: '', userId: '', fullName: 'Dr. Tariq', mohRegistrationNumber: '', mohVerified: true, title: DoctorTitle.DR, experienceYears: 5, overallRating: 5, reviewCount: 0, consultationFeeSar: 150, isActive: true)).fullName;
                                return DataRow(cells: [
                                  DataCell(Text(docName, style: const TextStyle(fontWeight: FontWeight.bold))),
                                  DataCell(Text('${p.clinicNameEn ?? 'Al-Habib Center'} (${p.branchNameEn ?? 'Main Branch'})')),
                                  DataCell(Text(p.department)),
                                  DataCell(Text('SAR ${p.consultationFeeSar.toStringAsFixed(0)}')),
                                  DataCell(
                                    Chip(
                                      label: Text(p.isActive ? 'Active' : 'Inactive'),
                                      backgroundColor: p.isActive ? AppTheme.primaryLightTeal : Colors.grey[200],
                                    ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(Icons.delete, size: 18, color: AppTheme.dangerRed),
                                      onPressed: () async {
                                        try {
                                          await ref.read(doctorServiceProvider).removeDoctorClinic(p.dcId);
                                        } catch (_) {}
                                        _loadDoctorsData();
                                      },
                                    ),
                                  ),
                                ]);
                              }).toList(),
                            ),
                          ),
                  ),

                  // Tab 2: Doctor Profiles
                  Card(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _doctors.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final doc = _doctors[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primaryLightTeal,
                            child: Text(
                              doc.title.value,
                              style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                          title: Text(doc.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('MOH Reg: ${doc.mohRegistrationNumber} | ${doc.experienceYears} Yrs Exp'),
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

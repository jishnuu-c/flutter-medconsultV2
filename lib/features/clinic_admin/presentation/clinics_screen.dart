import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/clinic_models.dart';
import '../data/clinic_service.dart';

class ClinicsScreen extends ConsumerStatefulWidget {
  const ClinicsScreen({super.key});

  @override
  ConsumerState<ClinicsScreen> createState() => _ClinicsScreenState();
}

class _ClinicsScreenState extends ConsumerState<ClinicsScreen> with SingleTickerProviderStateMixin {
  late TabController _subTabController;

  bool _isLoading = false;
  List<ClinicModel> _clinics = [];
  ClinicModel? _selectedClinic;

  // Sub-items for selected clinic
  List<ClinicBranchModel> _branches = [];
  List<ClinicSpecialtyModel> _specialties = [];
  List<ClinicInsuranceModel> _insurances = [];
  List<ClinicLanguageModel> _languages = [];

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 4, vsync: this);
    _loadClinics();
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  Future<void> _loadClinics() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref.read(clinicServiceProvider).getAllClinics();
      setState(() => _clinics = res);
    } catch (_) {
      _populateMockClinics();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateMockClinics() {
    _clinics = [
      ClinicModel(
        clinicId: 'cl-1',
        nameEn: 'Al-Habib Medical Center',
        nameAr: 'مركز الحبيب الطبي',
        email: 'info@alhabib.sa',
        phonePrimary: '+966 11 400 1111',
        mohLicenseNumber: 'MOH-77881',
        vatNumber: '300123456700003',
        isActive: true,
      ),
      ClinicModel(
        clinicId: 'cl-2',
        nameEn: 'Riyadh Care Hospital Clinic',
        nameAr: 'عياادات رعاية الرياض',
        email: 'contact@riyadhcare.sa',
        phonePrimary: '+966 11 222 3333',
        mohLicenseNumber: 'MOH-99210',
        isActive: true,
      ),
    ];
  }

  Future<void> _selectClinic(ClinicModel clinic) async {
    setState(() {
      _selectedClinic = clinic;
      _isLoading = true;
    });

    try {
      final detail = await ref.read(clinicServiceProvider).getClinicDetail(clinic.clinicId);
      setState(() {
        _branches = detail.branches;
        _specialties = detail.specialties;
        _insurances = detail.insurances;
        _languages = detail.languages;
      });
    } catch (_) {
      setState(() {
        _branches = [
          ClinicBranchModel(
            branchId: 'b-1',
            clinicId: clinic.clinicId,
            branchNameEn: 'Olaya Main Branch',
            branchNameAr: 'فرع العليا الرئيسي',
            cityId: 'c1',
            addressLine1: 'Olaya Main Road',
            isPrimary: true,
            isActive: true,
          ),
        ];
        _specialties = [
          ClinicSpecialtyModel(id: 'cs-1', clinicId: clinic.clinicId, specialtyId: 'General Practice'),
          ClinicSpecialtyModel(id: 'cs-2', clinicId: clinic.clinicId, specialtyId: 'Cardiology'),
        ];
        _insurances = [
          ClinicInsuranceModel(id: 'ci-1', clinicId: clinic.clinicId, providerId: 'Tawuniya', networkClass: 'Class A', isActive: true),
        ];
        _languages = [
          ClinicLanguageModel(id: 'clg-1', clinicId: clinic.clinicId, languageId: 'English'),
          ClinicLanguageModel(id: 'clg-2', clinicId: clinic.clinicId, languageId: 'Arabic'),
        ];
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openClinicDialog(ClinicModel? clinic) {
    final isEdit = clinic != null;
    final nameEnController = TextEditingController(text: clinic?.nameEn ?? '');
    final nameArController = TextEditingController(text: clinic?.nameAr ?? '');
    final emailController = TextEditingController(text: clinic?.email ?? '');
    final phoneController = TextEditingController(text: clinic?.phonePrimary ?? '');
    final mohController = TextEditingController(text: clinic?.mohLicenseNumber ?? '');
    final vatController = TextEditingController(text: clinic?.vatNumber ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Clinic' : 'Add New Clinic'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameEnController, decoration: const InputDecoration(labelText: 'Clinic Name (EN)')),
              const SizedBox(height: 12),
              TextField(controller: nameArController, decoration: const InputDecoration(labelText: 'Clinic Name (AR)')),
              const SizedBox(height: 12),
              TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email Address')),
              const SizedBox(height: 12),
              TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Primary Phone')),
              const SizedBox(height: 12),
              TextField(controller: mohController, decoration: const InputDecoration(labelText: 'MOH License Number')),
              const SizedBox(height: 12),
              TextField(controller: vatController, decoration: const InputDecoration(labelText: 'VAT Number')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final payload = {
                'nameEn': nameEnController.text.trim(),
                'nameAr': nameArController.text.trim(),
                'email': emailController.text.trim(),
                'phonePrimary': phoneController.text.trim(),
                'mohLicenseNumber': mohController.text.trim(),
                'vatNumber': vatController.text.trim(),
                'isActive': true,
              };
              try {
                if (isEdit) {
                  await ref.read(clinicServiceProvider).updateClinic(clinic.clinicId, payload);
                } else {
                  await ref.read(clinicServiceProvider).createClinic(payload);
                }
              } catch (_) {}
              if (mounted) Navigator.pop(ctx);
              _loadClinics();
            },
            child: Text(isEdit ? 'Save Changes' : 'Create Clinic'),
          ),
        ],
      ),
    );
  }

  void _openBranchDialog(ClinicBranchModel? branch) {
    if (_selectedClinic == null) return;
    final isEdit = branch != null;
    final nameEnController = TextEditingController(text: branch?.branchNameEn ?? '');
    final nameArController = TextEditingController(text: branch?.branchNameAr ?? '');
    final addressController = TextEditingController(text: branch?.addressLine1 ?? '');
    final phoneController = TextEditingController(text: branch?.phone ?? '');
    bool isPrimary = branch?.isPrimary ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Edit Branch' : 'Add Branch to ${_selectedClinic!.nameEn}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameEnController, decoration: const InputDecoration(labelText: 'Branch Name (EN)')),
                const SizedBox(height: 12),
                TextField(controller: nameArController, decoration: const InputDecoration(labelText: 'Branch Name (AR)')),
                const SizedBox(height: 12),
                TextField(controller: addressController, decoration: const InputDecoration(labelText: 'Address Line 1')),
                const SizedBox(height: 12),
                TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Branch Phone')),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Primary Branch'),
                  value: isPrimary,
                  onChanged: (val) => setDialogState(() => isPrimary = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final payload = {
                  'branchNameEn': nameEnController.text.trim(),
                  'branchNameAr': nameArController.text.trim(),
                  'cityId': 'c1',
                  'addressLine1': addressController.text.trim(),
                  'phone': phoneController.text.trim(),
                  'isPrimary': isPrimary,
                  'isActive': true,
                };
                try {
                  if (isEdit) {
                    await ref.read(clinicServiceProvider).updateClinicBranch(branch.branchId, payload);
                  } else {
                    await ref.read(clinicServiceProvider).createClinicBranch(_selectedClinic!.clinicId, payload);
                  }
                } catch (_) {}
                if (mounted) Navigator.pop(ctx);
                _selectClinic(_selectedClinic!);
              },
              child: Text(isEdit ? 'Save Changes' : 'Add Branch'),
            ),
          ],
        ),
      ),
    );
  }

  void _openHoursDialog(ClinicBranchModel branch) {
    final days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Operating Hours - ${branch.branchNameEn}'),
        content: SizedBox(
          width: 500,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: 7,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final dayName = days[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(width: 100, child: Text(dayName, style: const TextStyle(fontWeight: FontWeight.bold))),
                    const SizedBox(width: 12),
                    const Text('09:00 AM - 05:00 PM', style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                    const Spacer(),
                    const Chip(label: Text('Open'), backgroundColor: AppTheme.primaryLightTeal),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Save Hours')),
        ],
      ),
    );
  }

  void _deleteClinic(String clinicId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Clinic'),
        content: const Text('Are you sure you want to delete this clinic profile?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(clinicServiceProvider).deleteClinic(clinicId);
              } catch (_) {}
              _loadClinics();
            },
            child: const Text('Delete'),
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
                        'Clinics Management',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Manage clinic profiles, branches, operating hours, insurance links, and specialties.',
                        style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  key: const Key('add_clinic_btn'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add New Clinic'),
                  onPressed: () => _openClinicDialog(null),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Clinics Table
                  Expanded(
                    flex: 3,
                    child: Card(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : SingleChildScrollView(
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('Clinic Name')),
                                  DataColumn(label: Text('MOH License')),
                                  DataColumn(label: Text('Primary Phone')),
                                  DataColumn(label: Text('Status')),
                                  DataColumn(label: Text('Actions')),
                                ],
                                rows: _clinics.map((clinic) {
                                  final isSelected = _selectedClinic?.clinicId == clinic.clinicId;
                                  return DataRow(
                                    selected: isSelected,
                                    cells: [
                                      DataCell(
                                        SizedBox(
                                          height: 44,
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(clinic.nameEn, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                              Text(clinic.nameAr, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted), overflow: TextOverflow.ellipsis),
                                            ],
                                          ),
                                        ),
                                      ),
                                      DataCell(Text(clinic.mohLicenseNumber)),
                                      DataCell(Text(clinic.phonePrimary)),
                                      DataCell(
                                        Chip(
                                          label: Text(clinic.isActive ? 'Active' : 'Inactive'),
                                          backgroundColor: clinic.isActive ? AppTheme.primaryLightTeal : Colors.grey[200],
                                        ),
                                      ),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TextButton(
                                              onPressed: () => _selectClinic(clinic),
                                              child: Text(isSelected ? 'Selected' : 'Manage'),
                                            ),
                                            IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _openClinicDialog(clinic)),
                                            IconButton(icon: const Icon(Icons.delete, size: 18, color: AppTheme.dangerRed), onPressed: () => _deleteClinic(clinic.clinicId)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                    ),
                  ),

                  // Detail Drawer (when a clinic is selected)
                  if (_selectedClinic != null) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              color: AppTheme.primaryLightTeal,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_selectedClinic!.nameEn, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        Text('MOH License: ${_selectedClinic!.mohLicenseNumber}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                      ],
                                    ),
                                  ),
                                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _selectedClinic = null)),
                                ],
                              ),
                            ),
                            TabBar(
                              controller: _subTabController,
                              labelColor: AppTheme.primaryTeal,
                              unselectedLabelColor: AppTheme.textMuted,
                              tabs: const [
                                Tab(text: 'Branches'),
                                Tab(text: 'Specialties'),
                                Tab(text: 'Insurances'),
                                Tab(text: 'Languages'),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                controller: _subTabController,
                                children: [
                                  // Branches Tab
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      children: [
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: ElevatedButton.icon(
                                            icon: const Icon(Icons.add, size: 16),
                                            label: const Text('Add Branch'),
                                            onPressed: () => _openBranchDialog(null),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Expanded(
                                          child: ListView.builder(
                                            itemCount: _branches.length,
                                            itemBuilder: (context, idx) {
                                              final b = _branches[idx];
                                              return Card(
                                                margin: const EdgeInsets.only(bottom: 8),
                                                child: ListTile(
                                                  title: Text(b.branchNameEn),
                                                  subtitle: Text(b.addressLine1),
                                                  trailing: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                        icon: const Icon(Icons.access_time, size: 18),
                                                        tooltip: 'Operating Hours',
                                                        onPressed: () => _openHoursDialog(b),
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(Icons.edit, size: 18),
                                                        onPressed: () => _openBranchDialog(b),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Specialties Tab
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: ListView.builder(
                                      itemCount: _specialties.length,
                                      itemBuilder: (context, idx) {
                                        final s = _specialties[idx];
                                        return ListTile(
                                          title: Text(s.specialtyId),
                                          leading: const Icon(Icons.medical_services_outlined),
                                        );
                                      },
                                    ),
                                  ),

                                  // Insurances Tab
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: ListView.builder(
                                      itemCount: _insurances.length,
                                      itemBuilder: (context, idx) {
                                        final ins = _insurances[idx];
                                        return ListTile(
                                          title: Text(ins.providerId),
                                          subtitle: Text('Network: ${ins.networkClass}'),
                                          leading: const Icon(Icons.health_and_safety_outlined),
                                        );
                                      },
                                    ),
                                  ),

                                  // Languages Tab
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: ListView.builder(
                                      itemCount: _languages.length,
                                      itemBuilder: (context, idx) {
                                        final lang = _languages[idx];
                                        return ListTile(
                                          title: Text(lang.languageId),
                                          leading: const Icon(Icons.language_outlined),
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
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

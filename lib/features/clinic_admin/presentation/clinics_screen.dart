import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/references_service.dart';
import '../../../core/theme/app_theme.dart';
import '../data/clinic_models.dart';
import '../data/clinic_service.dart';

class ClinicsScreen extends ConsumerStatefulWidget {
  const ClinicsScreen({super.key});

  @override
  ConsumerState<ClinicsScreen> createState() => _ClinicsScreenState();
}

class _ClinicsScreenState extends ConsumerState<ClinicsScreen> {
  int _activeSubTab = 0; // 0=branches,1=specialties,2=insurances,3=languages

  bool _isLoading = false;
  List<ClinicModel> _clinics = [];
  ClinicModel? _selectedClinic;
  String _searchTerm = '';

  List<ClinicModel> get _filteredClinics {
    if (_searchTerm.trim().isEmpty) return _clinics;
    final q = _searchTerm.trim().toLowerCase();
    return _clinics
        .where((c) =>
            c.nameEn.toLowerCase().contains(q) ||
            (c.mohLicenseNumber.toLowerCase().contains(q)))
        .toList();
  }

  // Sub-items for selected clinic
  List<ClinicBranchModel> _branches = [];
  List<ClinicSpecialtyModel> _specialties = [];
  List<ClinicInsuranceModel> _insurances = [];
  List<ClinicLanguageModel> _languages = [];

  // Global lookup lists for the link/associate dialogs
  List<SpecialtyModel> _globalSpecialties = [];
  List<InsuranceProviderModel> _globalInsurances = [];
  List<LanguageModel> _globalLanguages = [];

  @override
  void initState() {
    super.initState();
    _loadClinics();
    _loadReferenceData();
  }

  Future<void> _loadReferenceData() async {
    try {
      final specialties =
          await ref.read(referenceServiceProvider).getAllSpecialties();
      if (mounted) setState(() => _globalSpecialties = specialties);
    } catch (_) {}
    try {
      final insurances =
          await ref.read(referenceServiceProvider).getAllInsuranceProviders();
      if (mounted) setState(() => _globalInsurances = insurances);
    } catch (_) {}
    try {
      final languages =
          await ref.read(referenceServiceProvider).getAllLanguages();
      if (mounted) setState(() => _globalLanguages = languages);
    } catch (_) {}
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
      _activeSubTab = 0;
    });

    try {
      final detail = await ref
          .read(clinicServiceProvider)
          .getClinicDetail(clinic.clinicId);
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
          ClinicSpecialtyModel(
              id: 'cs-1',
              clinicId: clinic.clinicId,
              specialtyId: 'General Practice'),
          ClinicSpecialtyModel(
              id: 'cs-2', clinicId: clinic.clinicId, specialtyId: 'Cardiology'),
        ];
        _insurances = [
          ClinicInsuranceModel(
              id: 'ci-1',
              clinicId: clinic.clinicId,
              providerId: 'Tawuniya',
              networkClass: 'Class A',
              isActive: true),
        ];
        _languages = [
          ClinicLanguageModel(
              id: 'clg-1', clinicId: clinic.clinicId, languageId: 'English'),
          ClinicLanguageModel(
              id: 'clg-2', clinicId: clinic.clinicId, languageId: 'Arabic'),
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
    final phoneController =
        TextEditingController(text: clinic?.phonePrimary ?? '');
    final mohController =
        TextEditingController(text: clinic?.mohLicenseNumber ?? '');
    final vatController = TextEditingController(text: clinic?.vatNumber ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Clinic' : 'Add New Clinic'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameEnController,
                  decoration:
                      const InputDecoration(labelText: 'Clinic Name (EN)')),
              const SizedBox(height: 12),
              TextField(
                  controller: nameArController,
                  decoration:
                      const InputDecoration(labelText: 'Clinic Name (AR)')),
              const SizedBox(height: 12),
              TextField(
                  controller: emailController,
                  decoration:
                      const InputDecoration(labelText: 'Email Address')),
              const SizedBox(height: 12),
              TextField(
                  controller: phoneController,
                  decoration:
                      const InputDecoration(labelText: 'Primary Phone')),
              const SizedBox(height: 12),
              TextField(
                  controller: mohController,
                  decoration:
                      const InputDecoration(labelText: 'MOH License Number')),
              const SizedBox(height: 12),
              TextField(
                  controller: vatController,
                  decoration: const InputDecoration(labelText: 'VAT Number')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
                  await ref
                      .read(clinicServiceProvider)
                      .updateClinic(clinic.clinicId, payload);
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
    final nameEnController =
        TextEditingController(text: branch?.branchNameEn ?? '');
    final nameArController =
        TextEditingController(text: branch?.branchNameAr ?? '');
    final addressController =
        TextEditingController(text: branch?.addressLine1 ?? '');
    final phoneController = TextEditingController(text: branch?.phone ?? '');
    bool isPrimary = branch?.isPrimary ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit
              ? 'Edit Branch'
              : 'Add Branch to ${_selectedClinic!.nameEn}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameEnController,
                    decoration:
                        const InputDecoration(labelText: 'Branch Name (EN)')),
                const SizedBox(height: 12),
                TextField(
                    controller: nameArController,
                    decoration:
                        const InputDecoration(labelText: 'Branch Name (AR)')),
                const SizedBox(height: 12),
                TextField(
                    controller: addressController,
                    decoration:
                        const InputDecoration(labelText: 'Address Line 1')),
                const SizedBox(height: 12),
                TextField(
                    controller: phoneController,
                    decoration:
                        const InputDecoration(labelText: 'Branch Phone')),
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
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
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
                    await ref
                        .read(clinicServiceProvider)
                        .updateClinicBranch(branch.branchId, payload);
                  } else {
                    await ref
                        .read(clinicServiceProvider)
                        .createClinicBranch(_selectedClinic!.clinicId, payload);
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
    final days = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday'
    ];

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
                    SizedBox(
                        width: 100,
                        child: Text(dayName,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold))),
                    const SizedBox(width: 12),
                    const Text('09:00 AM - 05:00 PM',
                        style:
                            TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                    const Spacer(),
                    const Chip(
                        label: Text('Open'),
                        backgroundColor: AppTheme.primaryLightTeal),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Save Hours')),
        ],
      ),
    );
  }

  void _openSpecialtyDialog() {
    if (_selectedClinic == null) return;
    String? selectedSpecialtyId = _globalSpecialties.isNotEmpty
        ? _globalSpecialties.first.specialtyId
        : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Link Medical Specialty'),
          content: DropdownButtonFormField<String>(
            value: selectedSpecialtyId,
            decoration: const InputDecoration(labelText: 'Choose Specialty'),
            items: _globalSpecialties
                .map((s) => DropdownMenuItem(
                    value: s.specialtyId, child: Text(s.nameEn)))
                .toList(),
            onChanged: (val) => setDialogState(() => selectedSpecialtyId = val),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selectedSpecialtyId == null
                  ? null
                  : () async {
                      try {
                        await ref
                            .read(clinicServiceProvider)
                            .addClinicSpecialty(_selectedClinic!.clinicId,
                                selectedSpecialtyId!);
                      } catch (_) {}
                      if (mounted) Navigator.pop(ctx);
                      _selectClinic(_selectedClinic!);
                    },
              child: const Text('Link Specialty'),
            ),
          ],
        ),
      ),
    );
  }

  void _openInsuranceDialog() {
    if (_selectedClinic == null) return;
    String? selectedProviderId = _globalInsurances.isNotEmpty
        ? _globalInsurances.first.providerId
        : null;
    final networkClassController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Associate Insurance Provider'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedProviderId,
                decoration:
                    const InputDecoration(labelText: 'Insurance Provider'),
                items: _globalInsurances
                    .map((ins) => DropdownMenuItem(
                        value: ins.providerId, child: Text(ins.nameEn)))
                    .toList(),
                onChanged: (val) =>
                    setDialogState(() => selectedProviderId = val),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: networkClassController,
                decoration: const InputDecoration(
                    labelText: 'Network Class',
                    hintText: 'E.g. VIP, Class A, Gold'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selectedProviderId == null
                  ? null
                  : () async {
                      final payload = {
                        'providerId': selectedProviderId,
                        'networkClass': networkClassController.text.trim(),
                        'isActive': true,
                      };
                      try {
                        await ref
                            .read(clinicServiceProvider)
                            .addClinicInsurance(_selectedClinic!.clinicId,
                                selectedProviderId!, payload);
                      } catch (_) {}
                      if (mounted) Navigator.pop(ctx);
                      _selectClinic(_selectedClinic!);
                    },
              child: const Text('Associate Provider'),
            ),
          ],
        ),
      ),
    );
  }

  void _openLanguageDialog() {
    if (_selectedClinic == null) return;
    String? selectedLanguageId =
        _globalLanguages.isNotEmpty ? _globalLanguages.first.languageId : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Link Supported Language'),
          content: DropdownButtonFormField<String>(
            value: selectedLanguageId,
            decoration: const InputDecoration(labelText: 'Choose Language'),
            items: _globalLanguages
                .map((l) => DropdownMenuItem(
                    value: l.languageId, child: Text(l.nameEn)))
                .toList(),
            onChanged: (val) => setDialogState(() => selectedLanguageId = val),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: selectedLanguageId == null
                  ? null
                  : () async {
                      try {
                        await ref.read(clinicServiceProvider).addClinicLanguage(
                            _selectedClinic!.clinicId, selectedLanguageId!);
                      } catch (_) {}
                      if (mounted) Navigator.pop(ctx);
                      _selectClinic(_selectedClinic!);
                    },
              child: const Text('Link Language'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteClinic(String clinicId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Clinic'),
        content:
            const Text('Are you sure you want to delete this clinic profile?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
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

  Future<void> _deleteSpecialty(String specialtyId) async {
    if (_selectedClinic == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink Specialty'),
        content: const Text('Are you sure you want to unlink this specialty?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Unlink')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(clinicServiceProvider)
          .deleteClinicSpecialty(_selectedClinic!.clinicId, specialtyId);
    } catch (_) {}
    _selectClinic(_selectedClinic!);
  }

  Future<void> _deleteInsurance(String providerId) async {
    if (_selectedClinic == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink Insurance'),
        content: const Text(
            'Are you sure you want to unlink this insurance provider?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Unlink')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(clinicServiceProvider)
          .deleteClinicInsurance(_selectedClinic!.clinicId, providerId);
    } catch (_) {}
    _selectClinic(_selectedClinic!);
  }

  Future<void> _deleteLanguage(String languageId) async {
    if (_selectedClinic == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink Language'),
        content: const Text('Are you sure you want to unlink this language?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Unlink')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(clinicServiceProvider)
          .deleteClinicLanguage(_selectedClinic!.clinicId, languageId);
    } catch (_) {}
    _selectClinic(_selectedClinic!);
  }

  Widget _buildSidebarCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('My Clinics',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppTheme.primaryTeal)),
                Chip(
                  label: Text('${_filteredClinics.length} Listed',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.primaryDarkTeal)),
                  backgroundColor: AppTheme.primaryLightTeal,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide.none,
                ),
              ],
            ),
            const Divider(height: 20),
            TextField(
              decoration: const InputDecoration(
                hintText: '🔍 Search clinics by name or license...',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchTerm = v),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredClinics.isEmpty
                      ? _emptyStateCard(
                          icon: '🏥',
                          text: 'No matching clinics found.',
                          subtext:
                              'Try adjusting your search terms or click "+ Add New Clinic".',
                        )
                      : ListView.separated(
                          itemCount: _filteredClinics.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final clinic = _filteredClinics[index];
                            final selected =
                                _selectedClinic?.clinicId == clinic.clinicId;
                            return InkWell(
                              onTap: () => _selectClinic(clinic),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppTheme.primaryLightTeal
                                      : AppTheme.surfaceWhite,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border(
                                    top: BorderSide(color: AppTheme.borderGray),
                                    right:
                                        BorderSide(color: AppTheme.borderGray),
                                    bottom:
                                        BorderSide(color: AppTheme.borderGray),
                                    left: BorderSide(
                                        color: selected
                                            ? AppTheme.primaryTeal
                                            : AppTheme.borderGray,
                                        width: selected ? 5 : 1),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: AppTheme.backgroundApp,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                            color: AppTheme.borderGray),
                                      ),
                                      child: const Text('🏥',
                                          style: TextStyle(fontSize: 20)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(clinic.nameEn,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: AppTheme.primaryTeal)),
                                          const SizedBox(height: 4),
                                          Text(
                                              'MOH: ${clinic.mohLicenseNumber.isEmpty ? 'N/A' : clinic.mohLicenseNumber}',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.textMuted)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        textStyle:
                                            const TextStyle(fontSize: 11),
                                      ),
                                      onPressed: () => _selectClinic(clinic),
                                      child: const Text('Manage'),
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
    );
  }

  Widget _emptyStateCard(
      {required String icon, required String text, String? subtext}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.backgroundApp,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray, width: 1.5),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
          if (subtext != null) ...[
            const SizedBox(height: 4),
            Text(subtext,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ],
      ),
    );
  }

  Widget _subTabButton(String label, int index) {
    final active = _activeSubTab == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              active ? AppTheme.primaryTeal : AppTheme.surfaceWhite,
          foregroundColor: active ? Colors.white : AppTheme.primaryTeal,
          elevation: 0,
          side: BorderSide(
              color: active ? AppTheme.primaryTeal : AppTheme.borderGray),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 13),
        ),
        onPressed: () => setState(() => _activeSubTab = index),
        child: Text(label),
      ),
    );
  }

  Widget _sectionHeader(String title, String actionLabel, VoidCallback onTap) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppTheme.primaryTeal)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: const TextStyle(fontSize: 12),
          ),
          onPressed: onTap,
          child: Text(actionLabel),
        ),
      ],
    );
  }

  Widget _badge(String text,
      {Color? bg, Color? fg, EdgeInsetsGeometry? padding}) {
    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg ?? AppTheme.primaryLightTeal,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg ?? AppTheme.primaryDarkTeal)),
    );
  }

  Widget _buildBranchesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Facility Branch Locations', '+ Add Branch',
            () => _openBranchDialog(null)),
        const SizedBox(height: 16),
        Expanded(
          child: _branches.isEmpty
              ? _emptyStateCard(
                  icon: '🏢',
                  text: 'No branch locations added for this clinic yet.')
              : ListView.separated(
                  itemCount: _branches.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final b = _branches[idx];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.borderGray),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('📍 ${b.branchNameEn}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: AppTheme.primaryTeal)),
                              ),
                              _badge(b.isPrimary ? 'Primary' : 'Branch',
                                  bg: b.isPrimary
                                      ? AppTheme.successGreen.withOpacity(0.15)
                                      : AppTheme.backgroundApp,
                                  fg: b.isPrimary
                                      ? AppTheme.successGreen
                                      : AppTheme.textMuted),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(b.addressLine1,
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.textMain)),
                          const SizedBox(height: 2),
                          Text(b.phone?.isNotEmpty == true ? b.phone! : 'N/A',
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.textMuted)),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                onPressed: () => _openHoursDialog(b),
                                child: const Text('⏰ Hours'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.dangerRed,
                                    side: const BorderSide(
                                        color: AppTheme.dangerRed)),
                                onPressed: () => _openBranchDialog(b),
                                child: const Text('Edit'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSpecialtiesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Offered Medical Specialties', '+ Link Specialty',
            _openSpecialtyDialog),
        const SizedBox(height: 16),
        Expanded(
          child: _specialties.isEmpty
              ? _emptyStateCard(
                  icon: '🩺', text: 'No specialties linked to this clinic.')
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    mainAxisExtent: 56,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _specialties.length,
                  itemBuilder: (context, idx) {
                    final s = _specialties[idx];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundApp,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Text('🩺', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(s.specialtyId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textMain)),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close,
                                size: 16, color: AppTheme.dangerRed),
                            tooltip: 'Unlink',
                            onPressed: () => _deleteSpecialty(s.specialtyId),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildInsurancesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Accepted Insurance Networks', '+ Link Provider',
            _openInsuranceDialog),
        const SizedBox(height: 16),
        Expanded(
          child: _insurances.isEmpty
              ? _emptyStateCard(
                  icon: '🛡️',
                  text: 'No insurance providers linked to this clinic.')
              : ListView.separated(
                  itemCount: _insurances.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final ins = _insurances[idx];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.borderGray),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('🛡️ ${ins.providerId}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: AppTheme.primaryTeal)),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    _badge(ins.networkClass.isEmpty
                                        ? 'General'
                                        : ins.networkClass),
                                    _badge(
                                        ins.isActive ? 'Active' : 'Suspended',
                                        bg: ins.isActive
                                            ? AppTheme.successGreen
                                                .withOpacity(0.15)
                                            : AppTheme.dangerRed
                                                .withOpacity(0.12),
                                        fg: ins.isActive
                                            ? AppTheme.successGreen
                                            : AppTheme.dangerRed),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.dangerRed,
                                side: const BorderSide(
                                    color: AppTheme.dangerRed)),
                            onPressed: () => _deleteInsurance(ins.providerId),
                            child: const Text('Unlink'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLanguagesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
            'Supported Languages', '+ Link Language', _openLanguageDialog),
        const SizedBox(height: 16),
        Expanded(
          child: _languages.isEmpty
              ? _emptyStateCard(
                  icon: '🗣️', text: 'No languages linked to this clinic.')
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisExtent: 56,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _languages.length,
                  itemBuilder: (context, idx) {
                    final lang = _languages[idx];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundApp,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Text('🗣️', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(lang.languageId,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textMain)),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close,
                                size: 16, color: AppTheme.dangerRed),
                            tooltip: 'Unlink',
                            onPressed: () => _deleteLanguage(lang.languageId),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDetailPanel({required bool isMobile}) {
    if (_selectedClinic == null) {
      return const Center(
        child: Text('Select a clinic from the list to manage its details.',
            style: TextStyle(color: AppTheme.textMuted)),
      );
    }
    final clinic = _selectedClinic!;

    final logoBox = Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: const Text('🏥', style: TextStyle(fontSize: 28)),
    );

    final infoColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 2,
          children: [
            Text(clinic.nameEn,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: AppTheme.primaryTeal)),
            Text('(${clinic.nameAr})',
                style:
                    const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
        ),
        const SizedBox(height: 6),
        Text(clinic.descriptionEn ?? 'No overview description provided.',
            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _badge('MOH License: ${clinic.mohLicenseNumber}'),
            if (clinic.vatNumber != null && clinic.vatNumber!.isNotEmpty)
              _badge('VAT: ${clinic.vatNumber}'),
            Text('📞 ${clinic.phonePrimary}',
                style: const TextStyle(fontSize: 12)),
            if (clinic.email != null && clinic.email!.isNotEmpty)
              Text('✉️ ${clinic.email}', style: const TextStyle(fontSize: 12)),
          ],
        ),
      ],
    );

    final editButton = OutlinedButton(
      onPressed: () => _openClinicDialog(clinic),
      child: const Text('✏️ Edit Profile'),
    );
    final deleteButton = OutlinedButton(
      style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.dangerRed,
          side: const BorderSide(color: AppTheme.dangerRed)),
      onPressed: () => _deleteClinic(clinic.clinicId),
      child: const Text('Delete'),
    );

    final headerCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // teal top accent
          Container(height: 4, color: AppTheme.primaryTeal),
          const SizedBox(height: 16),
          if (isMobile) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                logoBox,
                const SizedBox(width: 12),
                Expanded(child: infoColumn),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: editButton),
                const SizedBox(width: 8),
                Expanded(child: deleteButton),
              ],
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                logoBox,
                const SizedBox(width: 16),
                Expanded(child: infoColumn),
                const SizedBox(width: 12),
                editButton,
                const SizedBox(width: 8),
                deleteButton,
              ],
            ),
          ],
        ],
      ),
    );

    final tabsCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _subTabButton('🏢 Facility Branches (${_branches.length})', 0),
                _subTabButton('🎓 Specialties (${_specialties.length})', 1),
                _subTabButton(
                    '🛡️ Insurance Networks (${_insurances.length})', 2),
                _subTabButton('🗣️ Languages (${_languages.length})', 3),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: switch (_activeSubTab) {
              0 => _buildBranchesTab(),
              1 => _buildSpecialtiesTab(),
              2 => _buildInsurancesTab(),
              _ => _buildLanguagesTab(),
            },
          ),
        ],
      ),
    );

    if (isMobile) {
      // No bounded height from the parent (it's inside a scroll view), so
      // the tab-content area gets its own fixed height for internal
      // scrolling instead of relying on Expanded.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          headerCard,
          const SizedBox(height: 16),
          SizedBox(height: 460, child: tabsCard),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        headerCard,
        const SizedBox(height: 16),
        Expanded(child: tabsCard),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 900;
          return Padding(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            child: isMobile
                ? SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Banner (stacked for mobile, mirrors angular flex-wrap)
                        const Text('🏥 Clinic & Facility Management',
                            style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textMain)),
                        const SizedBox(height: 4),
                        const Text(
                          'Configure clinic locations, operating hours, medical specialties, and insurance networks',
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            key: const Key('add_clinic_btn'),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add New Clinic'),
                            onPressed: () => _openClinicDialog(null),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Sidebar stacked above detail panel on mobile
                        SizedBox(
                          height: 380,
                          width: double.infinity,
                          child: _buildSidebarCard(),
                        ),
                        const SizedBox(height: 16),
                        _buildDetailPanel(isMobile: true),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Banner
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('🏥 Clinic & Facility Management',
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textMain)),
                                SizedBox(height: 4),
                                Text(
                                  'Configure clinic locations, operating hours, medical specialties, and insurance networks',
                                  style: TextStyle(
                                      fontSize: 13, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            key: const Key('add_clinic_btn'),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add New Clinic'),
                            onPressed: () => _openClinicDialog(null),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Sidebar + Detail, side by side (mirrors angular clinic-admin-layout)
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 340, child: _buildSidebarCard()),
                            const SizedBox(width: 16),
                            Expanded(child: _buildDetailPanel(isMobile: false)),
                          ],
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

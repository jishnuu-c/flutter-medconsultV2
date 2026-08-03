import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/references_service.dart';
import '../../../core/theme/app_theme.dart';
import '../data/clinic_models.dart';
import '../data/clinic_service.dart';

// Shared visual polish for every popup dialog in this screen: rounded
// corners consistent with the rest of the UI, and a max width that never
// exceeds the available screen width (fixes horizontal overflow on small
// screens where dialogs previously used a hard-coded width like 560).
RoundedRectangleBorder _dialogShape() =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

double _dialogMaxHeight(BuildContext context, {double preferred = 560}) {
  final screenHeight = MediaQuery.of(context).size.height;
  return math.min(preferred, screenHeight * 0.8);
}

// Fixed, comfortable dialog width: capped by the screen on small devices,
// but not left to shrink-wrap to tiny intrinsic content width on large
// screens either (that's what made fields look squeezed together).
double _dialogWidth(BuildContext context, {double preferred = 420}) {
  final screenWidth = MediaQuery.of(context).size.width;
  return math.min(preferred, screenWidth - 32);
}

class ClinicsScreen extends ConsumerStatefulWidget {
  const ClinicsScreen({super.key});

  @override
  ConsumerState<ClinicsScreen> createState() => _ClinicsScreenState();
}

class _ClinicsScreenState extends ConsumerState<ClinicsScreen> {
  int _activeSubTab = 0; // 0=branches,1=specialties,2=insurances,3=languages

  bool _isLoading = false; // drives the "My Clinics" sidebar list only
  bool _isDetailLoading = false; // drives the branches/specialties/etc tabs
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
    } catch (e) {
      debugPrint('[ManageClinics] getAllSpecialties failed: $e');
      if (mounted) _showError('Failed to load specialties list: $e');
    }
    try {
      final insurances =
          await ref.read(referenceServiceProvider).getAllInsuranceProviders();
      if (mounted) setState(() => _globalInsurances = insurances);
    } catch (e) {
      debugPrint('[ManageClinics] getAllInsuranceProviders failed: $e');
      if (mounted) _showError('Failed to load insurance providers list: $e');
    }
    try {
      final languages =
          await ref.read(referenceServiceProvider).getAllLanguages();
      if (mounted) setState(() => _globalLanguages = languages);
    } catch (e) {
      debugPrint('[ManageClinics] getAllLanguages failed: $e');
      if (mounted) _showError('Failed to load languages list: $e');
    }
  }

  // ── Name resolvers, mirror clinics.component.ts's getSpecialtyName /
  // getInsuranceName / getLanguageName. Clinic-specialty/insurance/language
  // link records only carry the foreign-key id; the display name has to be
  // looked up in the global reference lists loaded above.
  String _getSpecialtyName(String specialtyId) {
    final match = _globalSpecialties.where((s) => s.specialtyId == specialtyId);
    return match.isEmpty ? 'Unknown Specialty' : match.first.nameEn;
  }

  String _getInsuranceName(String providerId) {
    final match = _globalInsurances.where((i) => i.providerId == providerId);
    return match.isEmpty ? 'Unknown Provider' : match.first.nameEn;
  }

  String _getLanguageName(String languageId) {
    final match = _globalLanguages.where((l) => l.languageId == languageId);
    return match.isEmpty ? 'Unknown Language' : match.first.nameEn;
  }

  Future<void> _loadClinics() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref.read(clinicServiceProvider).getAllClinics();
      debugPrint(
          '[ManageClinics] getAllClinics -> ${res.length} clinics: ${res.map((c) => '${c.clinicId}:${c.nameEn}').join(', ')}');
      setState(() => _clinics = res);
      if (res.isNotEmpty) {
        await _selectClinic(res.first);
      } else {
        setState(() {
          _selectedClinic = null;
          _branches = [];
          _specialties = [];
          _insurances = [];
          _languages = [];
        });
      }
    } catch (e, st) {
      debugPrint('[ManageClinics] getAllClinics failed: $e');
      debugPrintStack(stackTrace: st);
      if (mounted)
        _showError('Failed to load clinics: $e', retry: _loadClinics);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Mirrors clinics.component.ts's loadClinicDetails(): four independent
  // calls against the real API, each updating its own section so a failure
  // in one (e.g. insurance) doesn't blank out the others.
  Future<void> _selectClinic(ClinicModel clinic) async {
    setState(() {
      _selectedClinic = clinic;
      _isDetailLoading = true;
      _activeSubTab = 0;
    });

    final service = ref.read(clinicServiceProvider);

    try {
      final branches = await service.getClinicBranches(clinic.clinicId);
      if (mounted) setState(() => _branches = branches);
    } catch (e) {
      debugPrint('[ManageClinics] getClinicBranches failed: $e');
      if (mounted) setState(() => _branches = []);
    }

    try {
      final specialties = await service.getClinicSpecialties(clinic.clinicId);
      if (mounted) setState(() => _specialties = specialties);
    } catch (e) {
      debugPrint('[ManageClinics] getClinicSpecialties failed: $e');
      if (mounted) setState(() => _specialties = []);
    }

    try {
      final insurances = await service.getClinicInsurances(clinic.clinicId);
      if (mounted) setState(() => _insurances = insurances);
    } catch (e) {
      debugPrint('[ManageClinics] getClinicInsurances failed: $e');
      if (mounted) setState(() => _insurances = []);
    }

    try {
      final languages = await service.getClinicLanguages(clinic.clinicId);
      if (mounted) setState(() => _languages = languages);
    } catch (e) {
      debugPrint('[ManageClinics] getClinicLanguages failed: $e');
      if (mounted) setState(() => _languages = []);
    }

    if (mounted) setState(() => _isDetailLoading = false);
  }

  // Small helpers mirroring UiService.showSuccess/showError from Angular.
  void _showError(String message, {VoidCallback? retry}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.dangerRed,
        duration: const Duration(seconds: 5),
        action: retry != null
            ? SnackBarAction(label: 'Retry', onPressed: retry)
            : null,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
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
        shape: _dialogShape(),
        title: Text(isEdit ? 'Edit Clinic' : 'Add New Clinic'),
        content: SizedBox(
          width: _dialogWidth(ctx),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: _dialogMaxHeight(ctx),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      decoration: const InputDecoration(
                          labelText: 'MOH License Number')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: vatController,
                      decoration:
                          const InputDecoration(labelText: 'VAT Number')),
                ],
              ),
            ),
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
                if (mounted) Navigator.pop(ctx);
                if (mounted) {
                  _showSuccess(isEdit
                      ? 'Clinic profile updated successfully.'
                      : 'Clinic created successfully.');
                }
                _loadClinics();
              } catch (e) {
                if (mounted) {
                  _showError(isEdit
                      ? 'Failed to update clinic: $e'
                      : 'Failed to create clinic: $e');
                }
              }
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
          shape: _dialogShape(),
          title: Text(isEdit
              ? 'Edit Branch'
              : 'Add Branch to ${_selectedClinic!.nameEn}'),
          content: SizedBox(
            width: _dialogWidth(context),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: _dialogMaxHeight(context),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                        controller: nameEnController,
                        decoration: const InputDecoration(
                            labelText: 'Branch Name (EN)')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: nameArController,
                        decoration: const InputDecoration(
                            labelText: 'Branch Name (AR)')),
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
                  if (mounted) Navigator.pop(ctx);
                  if (mounted) {
                    _showSuccess(isEdit
                        ? 'Branch updated successfully.'
                        : 'Branch created successfully.');
                  }
                  _selectClinic(_selectedClinic!);
                } catch (e) {
                  if (mounted) _showError('Failed to save branch: $e');
                }
              },
              child: Text(isEdit ? 'Save Changes' : 'Add Branch'),
            ),
          ],
        ),
      ),
    );
  }

  // dayOfWeek convention matches Angular's branchHoursFormList: 1=Monday..7=Sunday.
  static const _dayNames = {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  };

  void _openHoursDialog(ClinicBranchModel branch) {
    List<ClinicOperatingHourModel> hoursForm = [];
    bool loading = true;
    bool saving = false;

    Future<void> load(void Function(void Function()) setDialogState) async {
      try {
        final existing = await ref
            .read(clinicServiceProvider)
            .getBranchHours(branch.branchId);
        final days = [1, 2, 3, 4, 5, 6, 7];
        final built = days.map((day) {
          final match = existing.where((h) => h.dayOfWeek == day);
          final found = match.isEmpty ? null : match.first;
          return ClinicOperatingHourModel(
            branchId: branch.branchId,
            dayOfWeek: day,
            isClosed: found?.isClosed ?? false,
            openTime: found?.openTime ?? '09:00',
            closeTime: found?.closeTime ?? '17:00',
            breakStart: found?.breakStart ?? '',
            breakEnd: found?.breakEnd ?? '',
          );
        }).toList();
        setDialogState(() {
          hoursForm = built;
          loading = false;
        });
      } catch (e) {
        setDialogState(() => loading = false);
        if (mounted) _showError('Failed to load branch hours: $e');
      }
    }

    String? normalizeTime(String? t) {
      if (t == null || t.isEmpty) return null;
      return t.length == 5 ? '$t:00' : t;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (loading && hoursForm.isEmpty) {
            load(setDialogState);
          }
          return AlertDialog(
            shape: _dialogShape(),
            title: Text('Operating Hours - ${branch.branchNameEn}'),
            content: SizedBox(
              width: _dialogWidth(context, preferred: 560),
              height: loading ? 120 : _dialogMaxHeight(context, preferred: 480),
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      itemCount: hoursForm.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final h = hoursForm[index];
                        final openCtrl =
                            TextEditingController(text: h.openTime);
                        final closeCtrl =
                            TextEditingController(text: h.closeTime);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                      width: 100,
                                      child: Text(_dayNames[h.dayOfWeek] ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold))),
                                  Checkbox(
                                    value: h.isClosed,
                                    onChanged: (val) => setDialogState(() {
                                      hoursForm[index] =
                                          ClinicOperatingHourModel(
                                        branchId: h.branchId,
                                        dayOfWeek: h.dayOfWeek,
                                        isClosed: val ?? false,
                                        openTime: h.openTime,
                                        closeTime: h.closeTime,
                                        breakStart: h.breakStart,
                                        breakEnd: h.breakEnd,
                                      );
                                    }),
                                  ),
                                  const Text('Closed'),
                                ],
                              ),
                              if (!h.isClosed)
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: openCtrl,
                                        decoration: const InputDecoration(
                                            labelText: 'Open (HH:mm)'),
                                        onChanged: (val) => hoursForm[index] =
                                            ClinicOperatingHourModel(
                                          branchId: h.branchId,
                                          dayOfWeek: h.dayOfWeek,
                                          isClosed: h.isClosed,
                                          openTime: val,
                                          closeTime: h.closeTime,
                                          breakStart: h.breakStart,
                                          breakEnd: h.breakEnd,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: closeCtrl,
                                        decoration: const InputDecoration(
                                            labelText: 'Close (HH:mm)'),
                                        onChanged: (val) => hoursForm[index] =
                                            ClinicOperatingHourModel(
                                          branchId: h.branchId,
                                          dayOfWeek: h.dayOfWeek,
                                          isClosed: h.isClosed,
                                          openTime: h.openTime,
                                          closeTime: val,
                                          breakStart: h.breakStart,
                                          breakEnd: h.breakEnd,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close')),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        setDialogState(() => saving = true);
                        final dtos = hoursForm
                            .map((h) => {
                                  'branchId': h.branchId,
                                  'dayOfWeek': h.dayOfWeek,
                                  'isClosed': h.isClosed,
                                  'openTime': normalizeTime(h.openTime),
                                  'closeTime': normalizeTime(h.closeTime),
                                  'breakStart': normalizeTime(h.breakStart),
                                  'breakEnd': normalizeTime(h.breakEnd),
                                })
                            .toList();
                        try {
                          await ref
                              .read(clinicServiceProvider)
                              .updateBranchHours(branch.branchId, dtos);
                          if (mounted) Navigator.pop(ctx);
                          if (mounted) {
                            _showSuccess('Branch hours updated successfully.');
                          }
                        } catch (e) {
                          setDialogState(() => saving = false);
                          if (mounted) {
                            _showError('Failed to update branch hours: $e');
                          }
                        }
                      },
                child: Text(saving ? 'Saving...' : 'Save Hours'),
              ),
            ],
          );
        },
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
          shape: _dialogShape(),
          title: const Text('Link Medical Specialty'),
          content: SizedBox(
            width: _dialogWidth(context),
            child: DropdownButtonFormField<String>(
              value: selectedSpecialtyId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Choose Specialty'),
              items: _globalSpecialties
                  .map((s) => DropdownMenuItem(
                      value: s.specialtyId,
                      child: Text(s.nameEn,
                          maxLines: 1, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (val) =>
                  setDialogState(() => selectedSpecialtyId = val),
            ),
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
                        if (mounted) Navigator.pop(ctx);
                        if (mounted) {
                          _showSuccess('Specialty linked to clinic.');
                        }
                        _selectClinic(_selectedClinic!);
                      } catch (e) {
                        if (mounted) {
                          _showError('Failed to link specialty: $e');
                        }
                      }
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
          shape: _dialogShape(),
          title: const Text('Associate Insurance Provider'),
          content: SizedBox(
            width: _dialogWidth(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedProviderId,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Insurance Provider'),
                  items: _globalInsurances
                      .map((ins) => DropdownMenuItem(
                          value: ins.providerId,
                          child: Text(ins.nameEn,
                              maxLines: 1, overflow: TextOverflow.ellipsis)))
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
                        if (mounted) Navigator.pop(ctx);
                        if (mounted) {
                          _showSuccess('Insurance provider associated.');
                        }
                        _selectClinic(_selectedClinic!);
                      } catch (e) {
                        if (mounted) {
                          _showError('Failed to link insurance: $e');
                        }
                      }
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
          shape: _dialogShape(),
          title: const Text('Link Supported Language'),
          content: SizedBox(
            width: _dialogWidth(context),
            child: DropdownButtonFormField<String>(
              value: selectedLanguageId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Choose Language'),
              items: _globalLanguages
                  .map((l) => DropdownMenuItem(
                      value: l.languageId,
                      child: Text(l.nameEn,
                          maxLines: 1, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (val) =>
                  setDialogState(() => selectedLanguageId = val),
            ),
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
                        if (mounted) Navigator.pop(ctx);
                        if (mounted) {
                          _showSuccess('Language linked to clinic.');
                        }
                        _selectClinic(_selectedClinic!);
                      } catch (e) {
                        if (mounted) {
                          _showError('Failed to link language: $e');
                        }
                      }
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
        shape: _dialogShape(),
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
                if (mounted) _showSuccess('Clinic removed.');
                _loadClinics();
              } catch (e) {
                if (mounted) _showError('Failed to delete clinic: $e');
              }
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
        shape: _dialogShape(),
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
      if (mounted) _showSuccess('Specialty unlinked.');
      _selectClinic(_selectedClinic!);
    } catch (e) {
      if (mounted) _showError('Failed to unlink specialty: $e');
    }
  }

  Future<void> _deleteInsurance(String providerId) async {
    if (_selectedClinic == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: _dialogShape(),
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
      if (mounted) _showSuccess('Insurance unlinked.');
      _selectClinic(_selectedClinic!);
    } catch (e) {
      if (mounted) _showError('Failed to unlink insurance: $e');
    }
  }

  Future<void> _deleteLanguage(String languageId) async {
    if (_selectedClinic == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: _dialogShape(),
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
      if (mounted) _showSuccess('Language unlinked.');
      _selectClinic(_selectedClinic!);
    } catch (e) {
      if (mounted) _showError('Failed to unlink language: $e');
    }
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
                      ? RefreshIndicator(
                          onRefresh: _loadClinics,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              _emptyStateCard(
                                icon: '🏥',
                                text: 'No matching clinics found.',
                                subtext:
                                    'Try adjusting your search terms or click "+ Add New Clinic".',
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadClinics,
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _filteredClinics.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final clinic = _filteredClinics[index];
                              final selected =
                                  _selectedClinic?.clinicId == clinic.clinicId;
                              // NOTE: BoxDecoration cannot combine a
                              // borderRadius with a Border whose sides have
                              // different colors/widths (Flutter throws "A
                              // borderRadius can only be given on borders
                              // with uniform colors" and the item silently
                              // fails to paint). So the outer border stays
                              // uniform, and the teal "selected" indicator
                              // is drawn as a separate strip inside a
                              // ClipRRect instead of being the container's
                              // left BorderSide. IntrinsicHeight gives the
                              // stretch Row a bounded height (ListView items
                              // are otherwise unbounded), which the
                              // indicator strip needs.
                              final iconBox = Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppTheme.backgroundApp,
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: AppTheme.borderGray),
                                ),
                                child: const Text('🏥',
                                    style: TextStyle(fontSize: 20)),
                              );
                              final nameColumn = Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                              );
                              final manageButton = OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  minimumSize: const Size(0, 40),
                                  tapTargetSize: MaterialTapTargetSize.padded,
                                  textStyle: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () => _selectClinic(clinic),
                                child: const Text('Manage'),
                              );

                              return ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  onTap: () => _selectClinic(clinic),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? AppTheme.primaryLightTeal
                                          : AppTheme.surfaceWhite,
                                      border: Border.all(
                                          color: AppTheme.borderGray),
                                    ),
                                    child: IntrinsicHeight(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Container(
                                            width: selected ? 5 : 1,
                                            color: selected
                                                ? AppTheme.primaryTeal
                                                : Colors.transparent,
                                          ),
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  iconBox,
                                                  const SizedBox(width: 12),
                                                  nameColumn,
                                                  const SizedBox(width: 8),
                                                  manageButton,
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 13),
        ),
        onPressed: () => setState(() => _activeSubTab = index),
        child: Text(label),
      ),
    );
  }

  Widget _sectionHeader(String title, String actionLabel, VoidCallback onTap,
      {bool isMobile = false}) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppTheme.primaryTeal)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                minimumSize: const Size(0, 44),
                textStyle: const TextStyle(fontSize: 12),
              ),
              onPressed: onTap,
              child: Text(actionLabel),
            ),
          ),
        ],
      );
    }
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

  Widget _buildBranchesTab(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Facility Branch Locations', '+ Add Branch',
            () => _openBranchDialog(null),
            isMobile: isMobile),
        const SizedBox(height: 16),
        Expanded(
          child: _branches.isEmpty
              ? _emptyStateCard(
                  icon: '🏢',
                  text: 'No branch locations added for this clinic yet.')
              : RefreshIndicator(
                  onRefresh: () => _selectClinic(_selectedClinic!),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                                        ? AppTheme.successGreen
                                            .withOpacity(0.15)
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
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 44),
                                    ),
                                    onPressed: () => _openHoursDialog(b),
                                    child: const Text('⏰ Hours'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 44),
                                        foregroundColor: AppTheme.dangerRed,
                                        side: const BorderSide(
                                            color: AppTheme.dangerRed)),
                                    onPressed: () => _openBranchDialog(b),
                                    child: const Text('Edit'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSpecialtiesTab(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Offered Medical Specialties', '+ Link Specialty',
            _openSpecialtyDialog,
            isMobile: isMobile),
        const SizedBox(height: 16),
        Expanded(
          child: _specialties.isEmpty
              ? _emptyStateCard(
                  icon: '🩺', text: 'No specialties linked to this clinic.')
              : RefreshIndicator(
                  onRefresh: () => _selectClinic(_selectedClinic!),
                  child: GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
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
                              child: Text(_getSpecialtyName(s.specialtyId),
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
                                  size: 18, color: AppTheme.dangerRed),
                              tooltip: 'Unlink',
                              onPressed: () => _deleteSpecialty(s.specialtyId),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildInsurancesTab(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Accepted Insurance Networks', '+ Link Provider',
            _openInsuranceDialog,
            isMobile: isMobile),
        const SizedBox(height: 16),
        Expanded(
          child: _insurances.isEmpty
              ? _emptyStateCard(
                  icon: '🛡️',
                  text: 'No insurance providers linked to this clinic.')
              : RefreshIndicator(
                  onRefresh: () => _selectClinic(_selectedClinic!),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          '🛡️ ${_getInsuranceName(ins.providerId)}',
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
                                              ins.isActive
                                                  ? 'Active'
                                                  : 'Suspended',
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
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 44),
                                    foregroundColor: AppTheme.dangerRed,
                                    side: const BorderSide(
                                        color: AppTheme.dangerRed)),
                                onPressed: () =>
                                    _deleteInsurance(ins.providerId),
                                child: const Text('Unlink'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildLanguagesTab(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
            'Supported Languages', '+ Link Language', _openLanguageDialog,
            isMobile: isMobile),
        const SizedBox(height: 16),
        Expanded(
          child: _languages.isEmpty
              ? _emptyStateCard(
                  icon: '🗣️', text: 'No languages linked to this clinic.')
              : RefreshIndicator(
                  onRefresh: () => _selectClinic(_selectedClinic!),
                  child: GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
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
                              child: Text(_getLanguageName(lang.languageId),
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
                                  size: 18, color: AppTheme.dangerRed),
                              tooltip: 'Unlink',
                              onPressed: () => _deleteLanguage(lang.languageId),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
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
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
      onPressed: () => _openClinicDialog(clinic),
      child: const Text('✏️ Edit Profile'),
    );
    final deleteButton = OutlinedButton(
      style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
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
            child: _isDetailLoading
                ? const Center(child: CircularProgressIndicator())
                : switch (_activeSubTab) {
                    0 => _buildBranchesTab(isMobile),
                    1 => _buildSpecialtiesTab(isMobile),
                    2 => _buildInsurancesTab(isMobile),
                    _ => _buildLanguagesTab(isMobile),
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
          SizedBox(height: 520, child: tabsCard),
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
                        // Header Banner (compact single row for mobile:
                        // title + icon-only add button, subtitle dropped
                        // to save vertical space above the fold)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Expanded(
                              child: Text('🏥 Clinics & Facilities',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textMain)),
                            ),
                            IconButton.filled(
                              key: const Key('add_clinic_btn'),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(44, 44),
                              ),
                              icon: const Icon(Icons.add, size: 22),
                              tooltip: 'Add New Clinic',
                              onPressed: () => _openClinicDialog(null),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

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

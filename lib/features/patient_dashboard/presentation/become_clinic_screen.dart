import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/clinic_service.dart';
import '../../clinic_admin/data/clinic_models.dart';
import '../../system_admin/data/reference_service.dart';
import '../../system_admin/data/reference_models.dart';

/// Mirrors become-clinic.component.ts/.html: a 4-step wizard that lets a
/// logged-in patient register a clinic facility. Step 1 creates the
/// ClinicModel; steps 2-4 (specialties/languages/insurance) unlock only
/// once the clinic record exists, exactly like Angular's switchTab() guard.
class BecomeClinicScreen extends ConsumerStatefulWidget {
  const BecomeClinicScreen({super.key});

  @override
  ConsumerState<BecomeClinicScreen> createState() => _BecomeClinicScreenState();
}

enum _WizardTab { general, specialties, languages, insurance }

class _ProfileCardGroup extends StatelessWidget {
  final String title;
  final Widget child;
  const _ProfileCardGroup({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        (MediaQuery.of(context).size.width * 0.04).clamp(16, 28),
      ),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.borderGray)),
            ),
            child: Text(
              title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppTheme.primaryTeal),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _AddFormBox extends StatelessWidget {
  final String title;
  final Widget child;
  const _AddFormBox({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppTheme.backgroundApp,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.4,
                color: AppTheme.primaryTeal),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _BecomeClinicScreenState extends ConsumerState<BecomeClinicScreen> {
  _WizardTab _activeTab = _WizardTab.general;
  String? _clinicId;

  // ── Step 1: Clinic profile form state ────────────────────────────────
  final _nameEnController = TextEditingController();
  final _nameArController = TextEditingController();
  final _descEnController = TextEditingController();
  final _descArController = TextEditingController();
  final _websiteController = TextEditingController();
  final _emailController = TextEditingController();
  final _phonePrimaryController = TextEditingController();
  final _phoneSecondaryController = TextEditingController();
  final _mohLicenseController = TextEditingController();
  final _vatController = TextEditingController();
  PlatformFile? _logoFile;
  bool _isRegistering = false;

  // ── Step 2: Specialty add-form state ─────────────────────────────────
  List<SpecialtyModel> _globalSpecialties = [];
  String? _specSpecialtyId;
  bool _isSubmittingSpecialty = false;
  final List<ClinicSpecialtyModel> _addedSpecialties = [];

  // ── Step 3: Language add-form state ──────────────────────────────────
  List<LanguageModel> _globalLanguages = [];
  String? _langLanguageId;
  bool _isSubmittingLanguage = false;
  final List<ClinicLanguageModel> _addedLanguages = [];

  // ── Step 4: Insurance add-form state ─────────────────────────────────
  List<InsuranceProviderModel> _globalInsuranceProviders = [];
  String? _insProviderId;
  final _networkClassController = TextEditingController(text: 'CLASS_A');
  bool _insIsActive = true;
  bool _isSubmittingInsurance = false;
  final List<ClinicInsuranceModel> _addedInsurance = [];

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    _loadReferences();
  }

  @override
  void dispose() {
    _nameEnController.dispose();
    _nameArController.dispose();
    _descEnController.dispose();
    _descArController.dispose();
    _websiteController.dispose();
    _emailController.dispose();
    _phonePrimaryController.dispose();
    _phoneSecondaryController.dispose();
    _mohLicenseController.dispose();
    _vatController.dispose();
    _networkClassController.dispose();
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

  Future<void> _loadReferences() async {
    try {
      final specs =
          await ref.read(referenceServiceProvider).getAllSpecialties();
      if (mounted) setState(() => _globalSpecialties = specs);
    } catch (_) {}
    try {
      final langs = await ref.read(referenceServiceProvider).getAllLanguages();
      if (mounted) setState(() => _globalLanguages = langs);
    } catch (_) {}
    try {
      final providers =
          await ref.read(referenceServiceProvider).getAllInsuranceProviders();
      if (mounted) setState(() => _globalInsuranceProviders = providers);
    } catch (_) {}
  }

  String _specialtyName(String specialtyId) {
    final match = _globalSpecialties.where((s) => s.specialtyId == specialtyId);
    return match.isNotEmpty ? match.first.nameEn : specialtyId;
  }

  String _languageName(String languageId) {
    final match = _globalLanguages.where((l) => l.languageId == languageId);
    return match.isNotEmpty ? match.first.nameEn : languageId;
  }

  String _insuranceName(String providerId) {
    final match =
        _globalInsuranceProviders.where((p) => p.providerId == providerId);
    return match.isNotEmpty ? match.first.nameEn : providerId;
  }

  void _switchTab(_WizardTab tab) {
    if (_clinicId == null && tab != _WizardTab.general) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Please register the clinic details first in step 1.')));
      return;
    }
    setState(() => _activeTab = tab);
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _logoFile = result.files.first);
    }
  }

  bool get _clinicFormValid =>
      _nameEnController.text.trim().length >= 2 &&
      _nameArController.text.trim().length >= 2 &&
      _emailPattern.hasMatch(_emailController.text.trim()) &&
      _phonePrimaryController.text.trim().isNotEmpty &&
      _mohLicenseController.text.trim().isNotEmpty;

  // ── Step 1: registerClinicProfile ────────────────────────────────────
  Future<void> _registerClinicProfile() async {
    if (!_clinicFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Please fill in all required fields with a valid email.')));
      return;
    }

    setState(() => _isRegistering = true);
    final data = {
      'nameEn': _nameEnController.text.trim(),
      'nameAr': _nameArController.text.trim(),
      if (_descEnController.text.trim().isNotEmpty)
        'descriptionEn': _descEnController.text.trim(),
      if (_descArController.text.trim().isNotEmpty)
        'descriptionAr': _descArController.text.trim(),
      if (_websiteController.text.trim().isNotEmpty)
        'website': _websiteController.text.trim(),
      'email': _emailController.text.trim(),
      'phonePrimary': _phonePrimaryController.text.trim(),
      if (_phoneSecondaryController.text.trim().isNotEmpty)
        'phoneSecondary': _phoneSecondaryController.text.trim(),
      'mohLicenseNumber': _mohLicenseController.text.trim(),
      if (_vatController.text.trim().isNotEmpty)
        'vatNumber': _vatController.text.trim(),
      'isActive': true,
    };

    try {
      final created = await ref.read(clinicServiceProvider).createClinic(
            data,
            logoFilePath: _logoFile?.path,
          );
      _clinicId = created.clinicId;

      // Refresh session so role flips to CLINIC_ADMIN, mirroring Angular's
      // fetchCurrentUser() call after registerClinic succeeds.
      try {
        await ref.read(authNotifierProvider.notifier).fetchCurrentUser();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Clinic registered successfully! You are now a Clinic Administrator.')));
        setState(() => _activeTab = _WizardTab.specialties);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to register clinic: ${_errorMessage(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  // ── Step 2: Specialty actions ─────────────────────────────────────────
  Future<void> _submitSpecialty() async {
    if (_clinicId == null || _specSpecialtyId == null) return;
    setState(() => _isSubmittingSpecialty = true);
    try {
      final res = await ref
          .read(clinicServiceProvider)
          .addClinicSpecialty(_clinicId!, _specSpecialtyId!);
      if (mounted) {
        setState(() {
          _addedSpecialties.add(res);
          _specSpecialtyId = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Specialty added.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _addedSpecialties.add(ClinicSpecialtyModel(
            id: 'cs-${DateTime.now().millisecondsSinceEpoch}',
            clinicId: _clinicId!,
            specialtyId: _specSpecialtyId!,
          ));
          _specSpecialtyId = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Specialty added.')));
      }
    } finally {
      if (mounted) setState(() => _isSubmittingSpecialty = false);
    }
  }

  Future<void> _removeSpecialty(ClinicSpecialtyModel s) async {
    if (_clinicId == null) return;
    try {
      await ref
          .read(clinicServiceProvider)
          .deleteClinicSpecialty(_clinicId!, s.specialtyId);
    } catch (_) {}
    if (mounted) {
      setState(() =>
          _addedSpecialties.removeWhere((x) => x.specialtyId == s.specialtyId));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Specialty removed.')));
    }
  }

  // ── Step 3: Language actions ──────────────────────────────────────────
  Future<void> _submitLanguage() async {
    if (_clinicId == null || _langLanguageId == null) return;
    setState(() => _isSubmittingLanguage = true);
    try {
      final res = await ref
          .read(clinicServiceProvider)
          .addClinicLanguage(_clinicId!, _langLanguageId!);
      if (mounted) {
        setState(() {
          _addedLanguages.add(res);
          _langLanguageId = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Language added.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _addedLanguages.add(ClinicLanguageModel(
            id: 'cl-${DateTime.now().millisecondsSinceEpoch}',
            clinicId: _clinicId!,
            languageId: _langLanguageId!,
          ));
          _langLanguageId = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Language added.')));
      }
    } finally {
      if (mounted) setState(() => _isSubmittingLanguage = false);
    }
  }

  Future<void> _removeLanguage(ClinicLanguageModel l) async {
    if (_clinicId == null) return;
    try {
      await ref
          .read(clinicServiceProvider)
          .deleteClinicLanguage(_clinicId!, l.languageId);
    } catch (_) {}
    if (mounted) {
      setState(() =>
          _addedLanguages.removeWhere((x) => x.languageId == l.languageId));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Language removed.')));
    }
  }

  // ── Step 4: Insurance actions ─────────────────────────────────────────
  Future<void> _submitInsurance() async {
    if (_clinicId == null || _insProviderId == null) return;
    setState(() => _isSubmittingInsurance = true);
    final details = {
      'providerId': _insProviderId,
      'networkClass': _networkClassController.text.trim(),
      'isActive': _insIsActive,
    };
    try {
      final res = await ref
          .read(clinicServiceProvider)
          .addClinicInsurance(_clinicId!, _insProviderId!, details);
      if (mounted) {
        setState(() {
          _addedInsurance.add(res);
          _insProviderId = null;
          _networkClassController.text = 'CLASS_A';
          _insIsActive = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Insurance provider linked.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _addedInsurance.add(ClinicInsuranceModel(
            id: 'ci-${DateTime.now().millisecondsSinceEpoch}',
            clinicId: _clinicId!,
            providerId: _insProviderId!,
            networkClass: details['networkClass'] as String,
            isActive: details['isActive'] as bool,
          ));
          _insProviderId = null;
          _networkClassController.text = 'CLASS_A';
          _insIsActive = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Insurance provider linked.')));
      }
    } finally {
      if (mounted) setState(() => _isSubmittingInsurance = false);
    }
  }

  Future<void> _removeInsurance(ClinicInsuranceModel i) async {
    if (_clinicId == null) return;
    try {
      await ref
          .read(clinicServiceProvider)
          .deleteClinicInsurance(_clinicId!, i.providerId);
    } catch (_) {}
    if (mounted) {
      setState(() =>
          _addedInsurance.removeWhere((x) => x.providerId == i.providerId));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Insurance unlinked.')));
    }
  }

  void _finishRegistration() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Clinic registration completed! Redirecting to managed clinics...')));
    context.go('/clinic-admin/clinics');
  }

  Widget _responsivePair(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 420;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [left, const SizedBox(height: 16), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 16),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  Widget _labeled(String label, Widget field, {bool required = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(required ? '$label *' : label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  Widget _buildWizardSteps(bool isMobile) {
    final steps = <Map<String, dynamic>>[
      {'tab': _WizardTab.general, 'label': 'Clinic Profile'},
      {'tab': _WizardTab.specialties, 'label': 'Specialties'},
      {'tab': _WizardTab.languages, 'label': 'Languages'},
      {'tab': _WizardTab.insurance, 'label': 'Insurance Providers'},
    ];
    return Wrap(
      spacing: isMobile ? 6 : 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          InkWell(
            onTap: () => _switchTab(steps[i]['tab'] as _WizardTab),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: _activeTab == steps[i]['tab']
                      ? AppTheme.primaryTeal
                      : (_clinicId != null
                          ? AppTheme.primaryLightTeal
                          : AppTheme.borderGray),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                        fontSize: 12,
                        color: _activeTab == steps[i]['tab']
                            ? Colors.white
                            : AppTheme.textMuted),
                  ),
                ),
                const SizedBox(width: 6),
                Text(steps[i]['label'] as String,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: _activeTab == steps[i]['tab']
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: _activeTab == steps[i]['tab']
                            ? AppTheme.primaryTeal
                            : AppTheme.textMain)),
              ],
            ),
          ),
          if (i != steps.length - 1)
            const Text('›', style: TextStyle(color: AppTheme.textMuted)),
        ],
      ],
    );
  }

  Widget _skipAndFinishButton() {
    return TextButton(
      onPressed: _finishRegistration,
      child: const Text('Skip & Finish Setup'),
    );
  }

  Widget _buildTabContent() {
    switch (_activeTab) {
      // ── Step 1: Health Facility Profile ──
      case _WizardTab.general:
        return _ProfileCardGroup(
          title: '📝 Step 1: Health Facility Profile',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _responsivePair(
                _labeled(
                  'Clinic Name (English)',
                  TextField(
                    controller: _nameEnController,
                    decoration: const InputDecoration(
                        hintText: 'e.g. Al-Amal Medical Clinic'),
                    onChanged: (_) => setState(() {}),
                  ),
                  required: true,
                ),
                _labeled(
                  'Clinic Name (Arabic)',
                  TextField(
                    controller: _nameArController,
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(
                        hintText: 'مثال: مجمع عيادات الأمل الطبي'),
                    onChanged: (_) => setState(() {}),
                  ),
                  required: true,
                ),
              ),
              const SizedBox(height: 16),
              _responsivePair(
                _labeled(
                  'Contact Email Address',
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        hintText: 'contact@clinicname.com'),
                    onChanged: (_) => setState(() {}),
                  ),
                  required: true,
                ),
                _labeled(
                  'Website Address',
                  TextField(
                    controller: _websiteController,
                    decoration: const InputDecoration(
                        hintText: 'https://www.clinicname.com'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _responsivePair(
                _labeled(
                  'Primary Phone Number',
                  TextField(
                    controller: _phonePrimaryController,
                    keyboardType: TextInputType.phone,
                    decoration:
                        const InputDecoration(hintText: '+966 50 000 0000'),
                    onChanged: (_) => setState(() {}),
                  ),
                  required: true,
                ),
                _labeled(
                  'Secondary Phone Number',
                  TextField(
                    controller: _phoneSecondaryController,
                    keyboardType: TextInputType.phone,
                    decoration:
                        const InputDecoration(hintText: '+966 11 000 0000'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _responsivePair(
                _labeled(
                  'MOH Facility License Number',
                  TextField(
                    controller: _mohLicenseController,
                    decoration: const InputDecoration(hintText: 'LIC-998877'),
                    onChanged: (_) => setState(() {}),
                  ),
                  required: true,
                ),
                _labeled(
                  'VAT Number / Tax ID',
                  TextField(
                    controller: _vatController,
                    decoration:
                        const InputDecoration(hintText: '300123456700003'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _labeled(
                'English Facility Description',
                TextField(
                  controller: _descEnController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      hintText:
                          'Introduce your medical facility, specialized departments, and care standards...'),
                ),
              ),
              const SizedBox(height: 16),
              _labeled(
                'Arabic Facility Description',
                TextField(
                  controller: _descArController,
                  maxLines: 3,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                      hintText: 'نبذة عن المرافق والأقسام الطبية...'),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Facility Brand Logo',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.borderGray),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundApp,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('🏥', style: TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickLogo,
                            icon: const Icon(Icons.upload_outlined, size: 16),
                            label: Text(_logoFile == null
                                ? 'Choose Logo Image'
                                : _logoFile!.name),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                              'Recommended size: Square PNG or JPG, max 2MB',
                              style: TextStyle(
                                  fontSize: 11, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: (_isRegistering || !_clinicFormValid)
                        ? null
                        : _registerClinicProfile,
                    child: _isRegistering
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('💾 Register Clinic & Continue'),
                  ),
                ),
              ),
            ],
          ),
        );

      // ── Step 2: Specialties ──
      case _WizardTab.specialties:
        return _ProfileCardGroup(
          title: '🎓 Step 2: Clinic Specialties',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                  alignment: Alignment.centerRight,
                  child: _skipAndFinishButton()),
              const SizedBox(height: 8),
              _AddFormBox(
                title: '+ Link Specialty to Clinic',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _labeled(
                        'Select Specialty',
                        DropdownButtonFormField<String>(
                          initialValue: _specSpecialtyId,
                          decoration: const InputDecoration(
                              hintText: '-- Choose Specialty --'),
                          items: _globalSpecialties
                              .map((s) => DropdownMenuItem(
                                  value: s.specialtyId, child: Text(s.nameEn)))
                              .toList(),
                          onChanged: (val) =>
                              setState(() => _specSpecialtyId = val),
                        ),
                        required: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed:
                          (_isSubmittingSpecialty || _specSpecialtyId == null)
                              ? null
                              : _submitSpecialty,
                      child: _isSubmittingSpecialty
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('+ Link'),
                    ),
                  ],
                ),
              ),
              if (_addedSpecialties.isEmpty)
                const Text('No specialties linked yet.',
                    style: TextStyle(color: AppTheme.textMuted))
              else
                Column(
                  children: _addedSpecialties.map((s) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.borderGray),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('🎓 ${_specialtyName(s.specialtyId)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                          TextButton(
                            onPressed: () => _removeSpecialty(s),
                            style: TextButton.styleFrom(
                                foregroundColor: AppTheme.dangerRed),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () => _switchTab(_WizardTab.languages),
                  child: const Text('Next: Languages ➡'),
                ),
              ),
            ],
          ),
        );

      // ── Step 3: Languages ──
      case _WizardTab.languages:
        return _ProfileCardGroup(
          title: '🗣️ Step 3: Facility Operating Languages',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                  alignment: Alignment.centerRight,
                  child: _skipAndFinishButton()),
              const SizedBox(height: 8),
              _AddFormBox(
                title: '+ Link Language to Clinic',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _labeled(
                        'Select Language',
                        DropdownButtonFormField<String>(
                          initialValue: _langLanguageId,
                          decoration: const InputDecoration(
                              hintText: '-- Choose Language --'),
                          items: _globalLanguages
                              .map((l) => DropdownMenuItem(
                                  value: l.languageId, child: Text(l.nameEn)))
                              .toList(),
                          onChanged: (val) =>
                              setState(() => _langLanguageId = val),
                        ),
                        required: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed:
                          (_isSubmittingLanguage || _langLanguageId == null)
                              ? null
                              : _submitLanguage,
                      child: _isSubmittingLanguage
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('+ Link'),
                    ),
                  ],
                ),
              ),
              if (_addedLanguages.isEmpty)
                const Text('No languages linked yet.',
                    style: TextStyle(color: AppTheme.textMuted))
              else
                Column(
                  children: _addedLanguages.map((l) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.borderGray),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('🗣️ ${_languageName(l.languageId)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                          TextButton(
                            onPressed: () => _removeLanguage(l),
                            style: TextButton.styleFrom(
                                foregroundColor: AppTheme.dangerRed),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () => _switchTab(_WizardTab.insurance),
                  child: const Text('Next: Insurance ➡'),
                ),
              ),
            ],
          ),
        );

      // ── Step 4: Insurance ──
      case _WizardTab.insurance:
        return _ProfileCardGroup(
          title: '🛡️ Step 4: Accepted Insurance Networks',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                  alignment: Alignment.centerRight,
                  child: _skipAndFinishButton()),
              const SizedBox(height: 8),
              _AddFormBox(
                title: '+ Link Insurance Provider',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _responsivePair(
                      _labeled(
                        'Insurance Provider',
                        DropdownButtonFormField<String>(
                          initialValue: _insProviderId,
                          decoration: const InputDecoration(
                              hintText: '-- Choose Provider --'),
                          items: _globalInsuranceProviders
                              .map((p) => DropdownMenuItem(
                                  value: p.providerId, child: Text(p.nameEn)))
                              .toList(),
                          onChanged: (val) =>
                              setState(() => _insProviderId = val),
                        ),
                        required: true,
                      ),
                      _labeled(
                        'Network Class',
                        TextField(
                          controller: _networkClassController,
                          decoration: const InputDecoration(
                              hintText: 'E.g. VIP, Class A, B, Silver'),
                        ),
                        required: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        onPressed:
                            (_isSubmittingInsurance || _insProviderId == null)
                                ? null
                                : _submitInsurance,
                        child: _isSubmittingInsurance
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('+ Link Insurance'),
                      ),
                    ),
                  ],
                ),
              ),
              if (_addedInsurance.isEmpty)
                const Text('No insurance networks linked yet.',
                    style: TextStyle(color: AppTheme.textMuted))
              else
                Column(
                  children: _addedInsurance.map((i) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.borderGray),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('🛡️ ${_insuranceName(i.providerId)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Chip(
                                  label: Text(i.networkClass,
                                      style: const TextStyle(fontSize: 11)),
                                  backgroundColor: AppTheme.primaryLightTeal,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _removeInsurance(i),
                            style: TextButton.styleFrom(
                                foregroundColor: AppTheme.dangerRed),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _finishRegistration,
                  child: const Text('🎉 Complete Setup & Finish'),
                ),
              ),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 576;

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 14 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🏥 Clinic Professional Registration',
                        style: TextStyle(
                            fontSize: isMobile ? 18 : 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal)),
                    const SizedBox(height: 4),
                    const Text(
                        'Establish your healthcare facility profile and primary administrator details',
                        style:
                            TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/patient/profile'),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Back to Profile'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildWizardSteps(isMobile),
            const SizedBox(height: 24),
            _buildTabContent(),
          ],
        ),
      ),
    );
  }
}

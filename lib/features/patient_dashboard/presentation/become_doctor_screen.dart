import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../clinic_admin/data/doctor_models.dart';
import '../../system_admin/data/reference_service.dart';
import '../../system_admin/data/reference_models.dart';

/// Mirrors become-doctor.component.ts/.html: a 4-step wizard that lets a
/// logged-in patient register as a doctor. Step 1 creates the DoctorModel;
/// steps 2-4 (specialties/languages/qualifications) unlock only once the
/// doctor record exists, exactly like Angular's switchTab() guard.
class BecomeDoctorScreen extends ConsumerStatefulWidget {
  const BecomeDoctorScreen({super.key});

  @override
  ConsumerState<BecomeDoctorScreen> createState() => _BecomeDoctorScreenState();
}

enum _WizardTab { general, specialties, languages, qualifications }

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

class _BecomeDoctorScreenState extends ConsumerState<BecomeDoctorScreen> {
  _WizardTab _activeTab = _WizardTab.general;
  String? _doctorId;

  // ── Step 1: General profile form state ──────────────────────────────
  final _mohRegController = TextEditingController();
  final _expController = TextEditingController(text: '0');
  final _feeController = TextEditingController(text: '150');
  final _bioEnController = TextEditingController();
  final _bioArController = TextEditingController();
  DoctorTitle _titleValue = DoctorTitle.DR;
  bool _isRegistering = false;

  // ── Step 2: Specialty add-form state ─────────────────────────────────
  List<SpecialtyModel> _globalSpecialties = [];
  List<SubSpecialtyModel> _subSpecialties = [];
  String? _specSpecialtyId;
  String? _specSubSpecialtyId;
  bool _specIsPrimary = false;
  bool _isSubmittingSpecialty = false;
  final List<DoctorSpecialtyModel> _addedSpecialties = [];

  // ── Step 3: Language add-form state ──────────────────────────────────
  List<LanguageModel> _globalLanguages = [];
  String? _langLanguageId;
  LanguageProficiency _langProficiency = LanguageProficiency.FLUENT;
  bool _isSubmittingLanguage = false;
  final List<DoctorLanguageModel> _addedLanguages = [];

  // ── Step 4: Qualification add-form state ─────────────────────────────
  final _degreeController = TextEditingController();
  final _institutionController = TextEditingController();
  final _countryController = TextEditingController();
  final _yearObtainedController =
      TextEditingController(text: DateTime.now().year.toString());
  final _sortOrderController = TextEditingController(text: '1');
  bool _isSubmittingQualification = false;
  final List<DoctorQualificationModel> _addedQualifications = [];

  @override
  void initState() {
    super.initState();
    _loadReferences();
  }

  @override
  void dispose() {
    _mohRegController.dispose();
    _expController.dispose();
    _feeController.dispose();
    _bioEnController.dispose();
    _bioArController.dispose();
    _degreeController.dispose();
    _institutionController.dispose();
    _countryController.dispose();
    _yearObtainedController.dispose();
    _sortOrderController.dispose();
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
  }

  String _specialtyName(String specialtyId) {
    final match = _globalSpecialties.where((s) => s.specialtyId == specialtyId);
    return match.isNotEmpty ? match.first.nameEn : specialtyId;
  }

  String _languageName(String languageId) {
    final match = _globalLanguages.where((l) => l.languageId == languageId);
    return match.isNotEmpty ? match.first.nameEn : languageId;
  }

  // Mirrors Angular switchTab(): steps 2-4 stay locked until step 1 has
  // created the doctor record.
  void _switchTab(_WizardTab tab) {
    if (_doctorId == null && tab != _WizardTab.general) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please register your profile first in step 1.')),
      );
      return;
    }
    setState(() => _activeTab = tab);
  }

  // ── Step 1: registerDoctorProfile ────────────────────────────────────
  Future<void> _registerDoctorProfile() async {
    if (_mohRegController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('MOH registration number is required.')));
      return;
    }
    final currentUser = ref.read(authNotifierProvider).currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User session not found.')));
      return;
    }

    setState(() => _isRegistering = true);
    try {
      final created = await ref.read(doctorServiceProvider).addDoctor({
        'userId': currentUser.id,
        'title': _titleValue.value,
        'mohRegistrationNumber': _mohRegController.text.trim(),
        'mohVerified': false,
        'experienceYears': int.tryParse(_expController.text) ?? 0,
        'consultationFeeSar': double.tryParse(_feeController.text) ?? 150.0,
        'bioEn': _bioEnController.text.trim(),
        'bioAr': _bioArController.text.trim(),
        'overallRating': 5.0,
        'reviewCount': 0,
        'isActive': true,
      });

      _doctorId = created.doctorId;

      // Refresh session so role flips to DOCTOR, same as Angular's
      // fetchCurrentUser() call after addDoctor succeeds.
      try {
        await ref.read(authNotifierProvider.notifier).fetchCurrentUser();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Professional details registered! You are now a Doctor.')));
        setState(() => _activeTab = _WizardTab.specialties);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Failed to register doctor profile: ${_errorMessage(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  // ── Step 2: Specialty actions ─────────────────────────────────────────
  Future<void> _onSpecialtyChanged(String? specialtyId) async {
    setState(() {
      _specSpecialtyId = specialtyId;
      _specSubSpecialtyId = null;
      _subSpecialties = [];
    });
    if (specialtyId == null) return;
    try {
      final subs = await ref
          .read(referenceServiceProvider)
          .getSubSpecialties(specialtyId);
      if (mounted) setState(() => _subSpecialties = subs);
    } catch (_) {}
  }

  Future<void> _submitSpecialty() async {
    if (_doctorId == null || _specSpecialtyId == null) return;
    setState(() => _isSubmittingSpecialty = true);
    final payload = {
      'doctorId': _doctorId,
      'specialtyId': _specSpecialtyId,
      if (_specSubSpecialtyId != null) 'subSpecialtyId': _specSubSpecialtyId,
      'isPrimary': _specIsPrimary,
    };
    try {
      final res = await ref.read(doctorServiceProvider).addSpecialty(payload);
      if (mounted) {
        setState(() {
          _addedSpecialties.add(res);
          _specSpecialtyId = null;
          _specSubSpecialtyId = null;
          _specIsPrimary = false;
          _subSpecialties = [];
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Specialty added.')));
      }
    } catch (_) {
      // Mirrors Angular's fallback: keep the wizard usable even if the
      // backend call fails, by recording it locally.
      if (mounted) {
        setState(() {
          _addedSpecialties.add(DoctorSpecialtyModel(
            id: 'spec-${DateTime.now().millisecondsSinceEpoch}',
            doctorId: _doctorId!,
            specialtyId: _specSpecialtyId!,
            subSpecialtyId: _specSubSpecialtyId,
            isPrimary: _specIsPrimary,
          ));
          _specSpecialtyId = null;
          _specSubSpecialtyId = null;
          _specIsPrimary = false;
          _subSpecialties = [];
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Specialty added.')));
      }
    } finally {
      if (mounted) setState(() => _isSubmittingSpecialty = false);
    }
  }

  Future<void> _removeSpecialty(DoctorSpecialtyModel s) async {
    try {
      await ref.read(doctorServiceProvider).removeSpecialty(s.id);
    } catch (_) {}
    if (mounted) {
      setState(() => _addedSpecialties.removeWhere((x) => x.id == s.id));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Specialty removed.')));
    }
  }

  // ── Step 3: Language actions ──────────────────────────────────────────
  Future<void> _submitLanguage() async {
    if (_doctorId == null || _langLanguageId == null) return;
    setState(() => _isSubmittingLanguage = true);
    final payload = {
      'doctorId': _doctorId,
      'languageId': _langLanguageId,
      'proficiency': _langProficiency.value,
    };
    try {
      final res = await ref.read(doctorServiceProvider).addLanguage(payload);
      if (mounted) {
        setState(() {
          _addedLanguages.add(res);
          _langLanguageId = null;
          _langProficiency = LanguageProficiency.FLUENT;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Language added.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _addedLanguages.add(DoctorLanguageModel(
            id: 'lang-${DateTime.now().millisecondsSinceEpoch}',
            doctorId: _doctorId!,
            languageId: _langLanguageId!,
            proficiency: _langProficiency,
          ));
          _langLanguageId = null;
          _langProficiency = LanguageProficiency.FLUENT;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Language added.')));
      }
    } finally {
      if (mounted) setState(() => _isSubmittingLanguage = false);
    }
  }

  Future<void> _removeLanguage(DoctorLanguageModel l) async {
    try {
      await ref.read(doctorServiceProvider).removeLanguage(l.id);
    } catch (_) {}
    if (mounted) {
      setState(() => _addedLanguages.removeWhere((x) => x.id == l.id));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Language removed.')));
    }
  }

  // ── Step 4: Qualification actions ─────────────────────────────────────
  Future<void> _submitQualification() async {
    if (_doctorId == null) return;
    if (_degreeController.text.trim().isEmpty ||
        _institutionController.text.trim().isEmpty ||
        _countryController.text.trim().isEmpty) {
      return;
    }
    setState(() => _isSubmittingQualification = true);
    final payload = {
      'doctorId': _doctorId,
      'degree': _degreeController.text.trim(),
      'institution': _institutionController.text.trim(),
      'country': _countryController.text.trim(),
      'yearObtained':
          int.tryParse(_yearObtainedController.text) ?? DateTime.now().year,
      'sortOrder': int.tryParse(_sortOrderController.text) ?? 1,
    };
    try {
      final res =
          await ref.read(doctorServiceProvider).addQualification(payload);
      if (mounted) {
        setState(() {
          _addedQualifications.add(res);
          _degreeController.clear();
          _institutionController.clear();
          _countryController.clear();
          _yearObtainedController.text = DateTime.now().year.toString();
          _sortOrderController.text = '1';
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Qualification degree added.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _addedQualifications.add(DoctorQualificationModel(
            qualId: 'qual-${DateTime.now().millisecondsSinceEpoch}',
            doctorId: _doctorId!,
            degree: payload['degree'] as String,
            institution: payload['institution'] as String,
            country: payload['country'] as String,
            yearObtained: payload['yearObtained'] as int,
            sortOrder: payload['sortOrder'] as int,
          ));
          _degreeController.clear();
          _institutionController.clear();
          _countryController.clear();
          _yearObtainedController.text = DateTime.now().year.toString();
          _sortOrderController.text = '1';
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Qualification degree added.')));
      }
    } finally {
      if (mounted) setState(() => _isSubmittingQualification = false);
    }
  }

  Future<void> _removeQualification(DoctorQualificationModel q) async {
    try {
      await ref.read(doctorServiceProvider).removeQualification(q.qualId);
    } catch (_) {}
    if (mounted) {
      setState(
          () => _addedQualifications.removeWhere((x) => x.qualId == q.qualId));
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Qualification removed.')));
    }
  }

  void _finishRegistration() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Setup completed successfully! Welcome to your Doctor Dashboard.')));
    context.go('/doctor/profile');
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

  // Mirrors .wizard-steps-container: numbered circles + connecting lines,
  // clickable (guarded by _switchTab) just like Angular's switchTab().
  Widget _buildWizardSteps(bool isMobile) {
    final steps = <Map<String, dynamic>>[
      {'tab': _WizardTab.general, 'label': 'Bio & Credentials'},
      {'tab': _WizardTab.specialties, 'label': 'Specialties'},
      {'tab': _WizardTab.languages, 'label': 'Languages'},
      {'tab': _WizardTab.qualifications, 'label': 'Qualifications'},
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
                      : (_doctorId != null
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
      // ── Step 1: Bio & Credentials ──
      case _WizardTab.general:
        return _ProfileCardGroup(
          title: '📝 Step 1: Personal Overview & Practice Bio',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _responsivePair(
                _labeled(
                  'Professional Title',
                  DropdownButtonFormField<DoctorTitle>(
                    initialValue: _titleValue,
                    decoration: const InputDecoration(),
                    items: DoctorTitle.values
                        .map((t) =>
                            DropdownMenuItem(value: t, child: Text(t.value)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _titleValue = val);
                    },
                  ),
                  required: true,
                ),
                _labeled(
                  'MOH Registration Number',
                  TextField(
                    controller: _mohRegController,
                    decoration: const InputDecoration(hintText: 'MOH-123456'),
                  ),
                  required: true,
                ),
              ),
              const SizedBox(height: 16),
              _responsivePair(
                _labeled(
                  'Years of Experience',
                  TextField(
                    controller: _expController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '10'),
                  ),
                  required: true,
                ),
                _labeled(
                  'Base Consultation Fee (SAR)',
                  TextField(
                    controller: _feeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '150'),
                  ),
                  required: true,
                ),
              ),
              const SizedBox(height: 16),
              _labeled(
                'English Biography / Summary',
                TextField(
                  controller: _bioEnController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      hintText:
                          'Describe your medical background, expertise, and patient care philosophy...'),
                ),
              ),
              const SizedBox(height: 16),
              _labeled(
                'Arabic Biography / Summary',
                TextField(
                  controller: _bioArController,
                  maxLines: 3,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                      hintText: 'نبذة عن خبراتك الطبية باللغة العربية...'),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _isRegistering ? null : _registerDoctorProfile,
                    child: _isRegistering
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('💾 Submit Registration & Continue'),
                  ),
                ),
              ),
            ],
          ),
        );

      // ── Step 2: Specialties ──
      case _WizardTab.specialties:
        return _ProfileCardGroup(
          title: '🎓 Step 2: Add Medical Specialties',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                  alignment: Alignment.centerRight,
                  child: _skipAndFinishButton()),
              const SizedBox(height: 8),
              _AddFormBox(
                title: '+ Add Medical Specialty',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _labeled(
                      'Specialty',
                      DropdownButtonFormField<String>(
                        initialValue: _specSpecialtyId,
                        decoration: const InputDecoration(
                            hintText: '-- Choose Specialty --'),
                        items: _globalSpecialties
                            .map((s) => DropdownMenuItem(
                                value: s.specialtyId, child: Text(s.nameEn)))
                            .toList(),
                        onChanged: _onSpecialtyChanged,
                      ),
                      required: true,
                    ),
                    const SizedBox(height: 12),
                    _labeled(
                      'Sub-Specialty (Optional)',
                      DropdownButtonFormField<String>(
                        initialValue: _specSubSpecialtyId,
                        decoration:
                            const InputDecoration(hintText: '-- None --'),
                        items: _subSpecialties
                            .map((ss) => DropdownMenuItem(
                                value: ss.subSpecialtyId,
                                child: Text(ss.nameEn)))
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _specSubSpecialtyId = val),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: _specIsPrimary,
                          onChanged: (val) =>
                              setState(() => _specIsPrimary = val ?? false),
                        ),
                        const Text('Primary Specialty'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
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
                            : const Text('+ Add Specialty'),
                      ),
                    ),
                  ],
                ),
              ),
              if (_addedSpecialties.isEmpty)
                const Text('No specialties added yet.',
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('🎓 ${_specialtyName(s.specialtyId)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Chip(
                                  label: Text(
                                      s.isPrimary ? 'Primary' : 'Secondary',
                                      style: const TextStyle(fontSize: 11)),
                                  backgroundColor: s.isPrimary
                                      ? AppTheme.primaryLightTeal
                                      : AppTheme.borderGray,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
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
          title: '🗣️ Step 3: Add Spoken Languages',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                  alignment: Alignment.centerRight,
                  child: _skipAndFinishButton()),
              const SizedBox(height: 8),
              _AddFormBox(
                title: '+ Add Spoken Language',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _responsivePair(
                      _labeled(
                        'Language',
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
                      _labeled(
                        'Proficiency',
                        DropdownButtonFormField<LanguageProficiency>(
                          initialValue: _langProficiency,
                          decoration: const InputDecoration(),
                          items: LanguageProficiency.values
                              .map((p) => DropdownMenuItem(
                                  value: p, child: Text(p.value)))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _langProficiency = val);
                            }
                          },
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
                            (_isSubmittingLanguage || _langLanguageId == null)
                                ? null
                                : _submitLanguage,
                        child: _isSubmittingLanguage
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('+ Add Language'),
                      ),
                    ),
                  ],
                ),
              ),
              if (_addedLanguages.isEmpty)
                const Text('No languages added yet.',
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
                            child: Text(
                                '🗣️ ${_languageName(l.languageId)} • ${l.proficiency.value}',
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
                  onPressed: () => _switchTab(_WizardTab.qualifications),
                  child: const Text('Next: Qualifications ➡'),
                ),
              ),
            ],
          ),
        );

      // ── Step 4: Qualifications ──
      case _WizardTab.qualifications:
        return _ProfileCardGroup(
          title: '📜 Step 4: Add Qualifications / Degrees',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                  alignment: Alignment.centerRight,
                  child: _skipAndFinishButton()),
              const SizedBox(height: 8),
              _AddFormBox(
                title: '+ Add Academic Degree / Qualification',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _responsivePair(
                      _labeled(
                        'Degree',
                        TextField(
                          controller: _degreeController,
                          decoration: const InputDecoration(
                              hintText: 'E.g. MBBS, MD, Board Certification'),
                        ),
                        required: true,
                      ),
                      _labeled(
                        'Institution / University',
                        TextField(
                          controller: _institutionController,
                          decoration: const InputDecoration(
                              hintText: 'University Name'),
                        ),
                        required: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _responsivePair(
                      _labeled(
                        'Country',
                        TextField(
                          controller: _countryController,
                          decoration:
                              const InputDecoration(hintText: 'Saudi Arabia'),
                        ),
                        required: true,
                      ),
                      _labeled(
                        'Year Obtained',
                        TextField(
                          controller: _yearObtainedController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: '2018'),
                        ),
                        required: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: _isSubmittingQualification
                            ? null
                            : _submitQualification,
                        child: _isSubmittingQualification
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('+ Add Degree'),
                      ),
                    ),
                  ],
                ),
              ),
              if (_addedQualifications.isEmpty)
                const Text('No qualifications added yet.',
                    style: TextStyle(color: AppTheme.textMuted))
              else
                Column(
                  children: _addedQualifications.map((q) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.borderGray),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.school_outlined,
                                size: 18, color: AppTheme.primaryTeal),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(q.degree,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14)),
                                Text(
                                  '${q.institution}, ${q.country} • ${q.yearObtained}',
                                  style: const TextStyle(
                                      fontSize: 12, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _removeQualification(q),
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
                    Text('🩺 Doctor Professional Registration',
                        style: TextStyle(
                            fontSize: isMobile ? 18 : 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal)),
                    const SizedBox(height: 4),
                    const Text(
                        'Complete your practitioner details to register as a consulting doctor',
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

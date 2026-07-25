import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../clinic_admin/data/doctor_models.dart';
import '../../system_admin/data/reference_service.dart';
import '../../system_admin/data/reference_models.dart';

class DoctorProfileScreen extends ConsumerStatefulWidget {
  const DoctorProfileScreen({super.key});

  @override
  ConsumerState<DoctorProfileScreen> createState() =>
      _DoctorProfileScreenState();
}

// Mirrors .profile-card-group / .group-card-header / .group-card-title
class _ProfileCardGroup extends StatelessWidget {
  final String title;
  final Widget child;
  const _ProfileCardGroup({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      // clamp(20px, 4vw, 32px) equivalent: scale padding with screen width, clamped
      padding: EdgeInsets.all(
        (MediaQuery.of(context).size.width * 0.04).clamp(20, 32),
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
                  fontSize: 20,
                  color: AppTheme.primaryTeal),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// Mirrors the light "card p-4 border bg-light" add-forms used above each
// specialties/languages/qualifications table in the Angular version.
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

class _DoctorProfileScreenState extends ConsumerState<DoctorProfileScreen> {
  final _bioEnController = TextEditingController();
  final _bioArController = TextEditingController();
  final _feeController = TextEditingController();
  final _expController = TextEditingController();
  final _mohRegController = TextEditingController();
  DoctorTitle _titleValue = DoctorTitle.DR;

  // Specialty add-form state
  String? _specSpecialtyId;
  String? _specSubSpecialtyId;
  bool _specIsPrimary = false;
  List<SubSpecialtyModel> _subSpecialties = [];
  bool _isSubmittingSpecialty = false;

  // Language add-form state
  String? _langLanguageId;
  LanguageProficiency _langProficiency = LanguageProficiency.FLUENT;
  bool _isSubmittingLanguage = false;

  // Qualification add-form state
  final _degreeController = TextEditingController();
  final _institutionController = TextEditingController();
  final _countryController = TextEditingController();
  final _yearObtainedController =
      TextEditingController(text: DateTime.now().year.toString());
  final _sortOrderController = TextEditingController(text: '1');
  bool _isSubmittingQualification = false;

  bool _isLoading = false;
  bool _isSaving = false;
  String? _doctorId;
  DoctorDetailResponse? _profile;

  List<SpecialtyModel> _globalSpecialties = [];
  List<LanguageModel> _globalLanguages = [];

  // Order matches Angular doctor-profile.component.html exactly:
  // general -> specialties -> languages -> qualifications -> clinics
  static const _tabs = [
    'Professional Details',
    'Specialties',
    'Languages',
    'Qualifications',
    'Clinic Placements'
  ];
  int _activeTab = 0;

  @override
  void initState() {
    super.initState();
    _resolveDoctorIdAndLoad();
    _loadReferences();
  }

  @override
  void dispose() {
    _bioEnController.dispose();
    _bioArController.dispose();
    _feeController.dispose();
    _expController.dispose();
    _mohRegController.dispose();
    _degreeController.dispose();
    _institutionController.dispose();
    _countryController.dispose();
    _yearObtainedController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  String _errorMessage(Object e) {
    if (e is DioException) {
      return e.response?.statusMessage ?? e.message ?? 'Network error';
    }
    return e.toString();
  }

  // Mirrors Angular loadReferences(): fetch global specialties & languages
  // lists so raw specialtyId/languageId values can be resolved to nameEn.
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

  // Mirrors Angular onSpecialtyChange(): load sub-specialties for the
  // selected specialty and reset any previously chosen sub-specialty.
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

  String _specialtyName(String specialtyId) {
    final match = _globalSpecialties.where((s) => s.specialtyId == specialtyId);
    return match.isNotEmpty ? match.first.nameEn : specialtyId;
  }

  String _languageName(String languageId) {
    final match = _globalLanguages.where((l) => l.languageId == languageId);
    return match.isNotEmpty ? match.first.nameEn : languageId;
  }

  // Same pattern as consultations_screen / availability_screen: no "my
  // doctor" endpoint, so match logged-in user's userId against /doctors/all
  // to resolve doctorId, then load the FULL profile (specialties, languages,
  // qualifications, clinic placements) in one call via getDoctorProfile.
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
      final profile =
          await ref.read(doctorServiceProvider).getDoctorProfile(_doctorId!);
      setState(() {
        _profile = profile;
        _bioEnController.text = profile.bioEn ?? '';
        _bioArController.text = profile.bioAr ?? '';
        _expController.text = profile.experienceYears.toString();
        _feeController.text = profile.consultationFeeSar.toString();
        _mohRegController.text = profile.mohRegistrationNumber;
        _titleValue = profile.title;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load profile: ${_errorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Mirrors Angular saveGeneralProfile(): sends title, mohRegistrationNumber,
  // bioEn, bioAr, experienceYears and consultationFeeSar together.
  Future<void> _saveProfile() async {
    if (_doctorId == null) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(doctorServiceProvider).updateDoctor(_doctorId!, {
        'title': _titleValue.value,
        'mohRegistrationNumber': _mohRegController.text.trim(),
        'bioEn': _bioEnController.text.trim(),
        'bioAr': _bioArController.text.trim(),
        'experienceYears': int.tryParse(_expController.text) ??
            _profile?.experienceYears ??
            10,
        'consultationFeeSar': double.tryParse(_feeController.text) ??
            _profile?.consultationFeeSar ??
            200.0,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Doctor profile updated successfully.')),
        );
      }
      await _resolveDoctorIdAndLoad();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to update profile: ${_errorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Specialty actions (mirrors Angular submitSpecialty / removeSpecialty) ──
  Future<void> _submitSpecialty() async {
    if (_doctorId == null || _specSpecialtyId == null) return;
    setState(() => _isSubmittingSpecialty = true);
    try {
      await ref.read(doctorServiceProvider).addSpecialty({
        'doctorId': _doctorId,
        'specialtyId': _specSpecialtyId,
        if (_specSubSpecialtyId != null) 'subSpecialtyId': _specSubSpecialtyId,
        'isPrimary': _specIsPrimary,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Specialty added to your profile.')),
        );
      }
      setState(() {
        _specSpecialtyId = null;
        _specSubSpecialtyId = null;
        _specIsPrimary = false;
        _subSpecialties = [];
      });
      await _resolveDoctorIdAndLoad();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to add specialty: ${_errorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingSpecialty = false);
    }
  }

  Future<void> _removeSpecialty(DoctorSpecialtyModel s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove specialty?'),
        content: const Text('Are you sure you want to remove this specialty?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(doctorServiceProvider).removeSpecialty(s.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Specialty removed.')));
      }
      await _resolveDoctorIdAndLoad();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to remove specialty: ${_errorMessage(e)}')));
      }
    }
  }

  // ── Language actions (mirrors Angular submitLanguage / removeLanguage) ──
  Future<void> _submitLanguage() async {
    if (_doctorId == null || _langLanguageId == null) return;
    setState(() => _isSubmittingLanguage = true);
    try {
      await ref.read(doctorServiceProvider).addLanguage({
        'doctorId': _doctorId,
        'languageId': _langLanguageId,
        'proficiency': _langProficiency.value,
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Language added.')));
      }
      setState(() {
        _langLanguageId = null;
        _langProficiency = LanguageProficiency.FLUENT;
      });
      await _resolveDoctorIdAndLoad();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to add language: ${_errorMessage(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isSubmittingLanguage = false);
    }
  }

  Future<void> _removeLanguage(DoctorLanguageModel l) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove language?'),
        content: const Text('Remove this language from your profile?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(doctorServiceProvider).removeLanguage(l.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Language removed.')));
      }
      await _resolveDoctorIdAndLoad();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to remove language: ${_errorMessage(e)}')));
      }
    }
  }

  // ── Qualification actions (mirrors Angular submitQualification / removeQualification) ──
  Future<void> _submitQualification() async {
    if (_doctorId == null) return;
    if (_degreeController.text.trim().isEmpty ||
        _institutionController.text.trim().isEmpty ||
        _countryController.text.trim().isEmpty) {
      return;
    }
    setState(() => _isSubmittingQualification = true);
    try {
      await ref.read(doctorServiceProvider).addQualification({
        'doctorId': _doctorId,
        'degree': _degreeController.text.trim(),
        'institution': _institutionController.text.trim(),
        'country': _countryController.text.trim(),
        'yearObtained':
            int.tryParse(_yearObtainedController.text) ?? DateTime.now().year,
        'sortOrder': int.tryParse(_sortOrderController.text) ?? 1,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Qualification degree added.')));
      }
      setState(() {
        _degreeController.clear();
        _institutionController.clear();
        _countryController.clear();
        _yearObtainedController.text = DateTime.now().year.toString();
        _sortOrderController.text = '1';
      });
      await _resolveDoctorIdAndLoad();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to add qualification: ${_errorMessage(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isSubmittingQualification = false);
    }
  }

  Future<void> _removeQualification(DoctorQualificationModel q) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove qualification?'),
        content: const Text('Remove this qualification degree?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(doctorServiceProvider).removeQualification(q.qualId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Qualification removed.')));
      }
      await _resolveDoctorIdAndLoad();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Failed to remove qualification: ${_errorMessage(e)}')));
      }
    }
  }

  // Two fields side by side on wide screens, stacked on narrow/mobile
  // screens so nothing overflows horizontally.
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

  // Mirrors .sub-nav-tabs / .sub-tab-btn: horizontally scrollable tab strip
  // so tab labels never wrap or overflow on narrow/mobile screens.
  Widget _buildSubNavTabs() {
    return Container(
      decoration: const BoxDecoration(
        border:
            Border(bottom: BorderSide(color: AppTheme.borderGray, width: 2)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: List.generate(_tabs.length, (i) {
            final active = _activeTab == i;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                onTap: () => setState(() => _activeTab = i),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: active
                              ? AppTheme.primaryTeal
                              : Colors.transparent,
                          width: 3),
                    ),
                  ),
                  child: Text(
                    _tabs[i],
                    style: TextStyle(
                      fontWeight: active ? FontWeight.bold : FontWeight.w600,
                      fontSize: 14,
                      color: active ? AppTheme.primaryTeal : AppTheme.textMuted,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _labeled(String label, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  Widget _buildTabContent() {
    final profile = _profile;
    switch (_activeTab) {
      // ── Tab 0: Professional Details (title, MOH#, bio EN/AR, exp, fee) ──
      case 0:
        return _ProfileCardGroup(
          title: 'Professional Details',
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
                ),
                _labeled(
                  'MOH Registration Number',
                  TextField(
                    controller: _mohRegController,
                    decoration: const InputDecoration(hintText: 'MOH-123456'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Biography (English)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _bioEnController,
                maxLines: 4,
                decoration: const InputDecoration(
                    hintText: 'Enter your professional biography...'),
              ),
              const SizedBox(height: 16),
              const Text('Biography (Arabic)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _bioArController,
                maxLines: 4,
                textDirection: TextDirection.rtl,
                decoration:
                    const InputDecoration(hintText: 'أدخل نبذتك المهنية...'),
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
                ),
                _labeled(
                  'Consultation Fee (SAR)',
                  TextField(
                    controller: _feeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '200'),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed:
                      (_isSaving || _doctorId == null) ? null : _saveProfile,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save Profile'),
                ),
              ),
            ],
          ),
        );

      // ── Tab 1: Specialties (add form + list with remove) ──
      case 1:
        return _ProfileCardGroup(
          title: 'Specialties (${profile?.specialties.length ?? 0})',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              if (profile == null || profile.specialties.isEmpty)
                const Text('No medical specialties listed on your profile yet.',
                    style: TextStyle(color: AppTheme.textMuted))
              else
                Column(
                  children: profile.specialties.map((s) {
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
            ],
          ),
        );

      // ── Tab 2: Languages (add form + list with remove) ──
      case 2:
        return _ProfileCardGroup(
          title: 'Languages (${profile?.languages.length ?? 0})',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AddFormBox(
                title: '+ Add Spoken Language',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                    ),
                    const SizedBox(height: 12),
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
              if (profile == null || profile.languages.isEmpty)
                const Text('No languages listed on your profile yet.',
                    style: TextStyle(color: AppTheme.textMuted))
              else
                Column(
                  children: profile.languages.map((l) {
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
            ],
          ),
        );

      // ── Tab 3: Qualifications (add form + list with remove) ──
      case 3:
        return _ProfileCardGroup(
          title: 'Qualifications (${profile?.qualifications.length ?? 0})',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AddFormBox(
                title: '+ Add Academic Degree / Qualification',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _labeled(
                      'Degree',
                      TextField(
                        controller: _degreeController,
                        decoration: const InputDecoration(
                            hintText: 'E.g. MBBS, MD, Board Certification'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _labeled(
                      'Institution / University',
                      TextField(
                        controller: _institutionController,
                        decoration:
                            const InputDecoration(hintText: 'University Name'),
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
                      ),
                      _labeled(
                        'Year Obtained',
                        TextField(
                          controller: _yearObtainedController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: '2018'),
                        ),
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
              if (profile == null || profile.qualifications.isEmpty)
                const Text('No qualifications on record.',
                    style: TextStyle(color: AppTheme.textMuted))
              else
                Column(
                  children: profile.qualifications.map((q) {
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
            ],
          ),
        );

      // ── Tab 4: Clinic Placements (read-only, matches Angular) ──
      case 4:
      default:
        return _ProfileCardGroup(
          title: 'Clinic Placements (${profile?.clinics.length ?? 0})',
          child: (profile == null || profile.clinics.isEmpty)
              ? const Text('Not currently placed at any clinic.',
                  style: TextStyle(color: AppTheme.textMuted))
              : Column(
                  children: profile.clinics.map((c) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.borderGray),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                c.clinicNameEn ?? c.department,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              if (c.isPrimary)
                                const Chip(
                                  label: Text('Primary',
                                      style: TextStyle(fontSize: 11)),
                                  backgroundColor: AppTheme.primaryLightTeal,
                                  visualDensity: VisualDensity.compact,
                                ),
                              Chip(
                                label: Text(c.isActive ? 'Active' : 'Inactive',
                                    style: const TextStyle(fontSize: 11)),
                                backgroundColor: c.isActive
                                    ? AppTheme.primaryLightTeal
                                    : AppTheme.borderGray,
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${c.branchNameEn ?? c.branchId} • ${c.department}',
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textMuted),
                          ),
                          Text(
                            'Fee: SAR ${c.consultationFeeSar.toStringAsFixed(0)} • Since ${c.startDate}',
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).currentUser;
    final isMobile = MediaQuery.of(context).size.width <= 576;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final profile = _profile;

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 14 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My Professional Profile',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain),
            ),
            const SizedBox(height: 4),
            const Text(
              'Manage your professional details, specialties, languages, and clinic placements.',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 20),

            // ── doctor-profile-container: column layout, 24px gap ──────
            // Overview card (avatar, name, MOH status, rating)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(isMobile
                  ? 14
                  : (MediaQuery.of(context).size.width * 0.04).clamp(20, 32)),
              margin: const EdgeInsets.only(bottom: 24),
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
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: AppTheme.primaryLightTeal,
                        child: Text(
                          user?.initials ?? 'DR',
                          style: const TextStyle(
                              color: AppTheme.primaryTeal,
                              fontWeight: FontWeight.bold,
                              fontSize: 18),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            profile != null
                                ? '${profile.title.value}. ${profile.fullName}'
                                : (user?.fullName ?? 'Dr. Practitioner'),
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textMain),
                          ),
                          const SizedBox(height: 4),
                          Text(user?.email ?? '',
                              style: const TextStyle(
                                  fontSize: 13, color: AppTheme.textMuted)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (profile != null)
                        Chip(
                          avatar: Icon(
                            profile.mohVerified
                                ? Icons.verified
                                : Icons.pending_outlined,
                            size: 16,
                            color: profile.mohVerified
                                ? AppTheme.successGreen
                                : AppTheme.warningAmber,
                          ),
                          label: Text(
                              'MOH: ${profile.mohRegistrationNumber} • ${profile.mohVerified ? "Verified" : "Pending"}'),
                          backgroundColor: AppTheme.backgroundApp,
                        ),
                      if (profile != null)
                        Chip(
                          avatar: const Icon(Icons.star,
                              size: 16, color: AppTheme.warningAmber),
                          label: Text(
                              '${profile.overallRating.toStringAsFixed(1)} (${profile.reviewCount} reviews)'),
                          backgroundColor: AppTheme.backgroundApp,
                        ),
                      if (profile != null)
                        Chip(
                          label: Text(profile.isActive ? 'Active' : 'Inactive'),
                          backgroundColor: profile.isActive
                              ? AppTheme.primaryLightTeal
                              : AppTheme.borderGray,
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // ── sub-nav-tabs: horizontally scrollable, mobile-safe ─────
            _buildSubNavTabs(),
            const SizedBox(height: 20),

            // ── active tab's profile-card-group ─────────────────────────
            _buildTabContent(),
          ],
        ),
      ),
    );
  }
}

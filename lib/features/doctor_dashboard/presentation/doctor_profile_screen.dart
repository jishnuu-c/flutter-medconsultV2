import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../clinic_admin/data/doctor_models.dart';
import '../../system_admin/data/reference_service.dart';
import '../../system_admin/data/reference_models.dart';
import '../../../core/network/api_client.dart';

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
  // Mirrors Angular's per-card `border-left: 5px solid ...` accent —
  // e.g. #0f172a (var(--primary-dark)) for the Account card, teal for
  // Personal Overview, amber/accent for Credentials.
  final Color accentColor;
  const _ProfileCardGroup({
    required this.title,
    required this.child,
    this.accentColor = AppTheme.primaryTeal,
  });

  @override
  Widget build(BuildContext context) {
    // NOTE: BoxDecoration.border with non-uniform side colors (accent left
    // vs. grey top/right/bottom) throws "A borderRadius can only be given
    // on borders with uniform colors" when combined with borderRadius.
    // Fix: keep the outer border/radius uniform (grey), and draw the
    // colored accent as a Positioned strip in a Stack — NOT a Row with
    // IntrinsicHeight/stretch, because `child` here contains a
    // LayoutBuilder (via _responsivePair) and IntrinsicHeight forces
    // intrinsic-dimension queries on its whole subtree, which
    // LayoutBuilder does not support ("LayoutBuilder does not support
    // returning intrinsic dimensions"). Stack + Positioned never queries
    // intrinsics, so it's safe here.
    final pad = (MediaQuery.of(context).size.width * 0.04).clamp(20, 32);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.surfaceWhite,
              border: Border.all(color: AppTheme.borderGray),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2)),
              ],
            ),
            padding: EdgeInsets.fromLTRB(
                pad - 5, pad.toDouble(), pad.toDouble(), pad.toDouble()),
            child: Padding(
              padding: const EdgeInsets.only(left: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(bottom: 16),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: const BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: AppTheme.borderGray)),
                    ),
                    child: Text(
                      title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: accentColor),
                    ),
                  ),
                  child,
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 5,
            child: Container(color: accentColor),
          ),
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

  bool _isLoading = true;
  bool _isSaving = false;
  String? _doctorId;
  DoctorDetailResponse? _profile;

  // ── Card 0: User Account Settings (mirrors Angular accountForm) ──
  bool _isEditingAccount = false;
  bool _isSavingAccount = false;
  String? _stagedAvatarPath; // local preview path, staged until save
  final _accFullNameController = TextEditingController();
  final _accEmailController = TextEditingController();
  final _accPhoneController = TextEditingController();
  String _accGender = 'MALE';
  String _accPreferredLang = 'en';

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
    _initAccountData();
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
    _accFullNameController.dispose();
    _accEmailController.dispose();
    _accPhoneController.dispose();
    super.dispose();
  }

  // Mirrors Angular initAccountData(): pre-fill account form from the
  // logged-in user, then disable it until "Edit Account Details" tapped.
  void _initAccountData() {
    final user = ref.read(authNotifierProvider).currentUser;
    _accFullNameController.text = user?.fullName ?? '';
    _accEmailController.text = user?.email ?? '';
    _accPhoneController.text = user?.phone ?? '';
    _accGender = 'MALE';
    _accPreferredLang = 'en';
  }

  void _enableAccountEdit() => setState(() => _isEditingAccount = true);

  void _cancelAccountEdit() {
    setState(() {
      _isEditingAccount = false;
      _stagedAvatarPath = null;
    });
    _initAccountData();
  }

  // Mirrors Angular triggerAvatarUpload()/onAvatarSelected(). Wire this to
  // your image_picker (or file_picker) call once the package is in
  // pubspec.yaml — kept as a stub here so this file compiles standalone.
  Future<void> _pickAvatar() async {
    setState(() => _isEditingAccount = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Photo picker not wired yet — hook up image_picker here.')),
      );
    }
  }

  // Mirrors Angular saveAccountInfo(): saves name/email/phone/gender/lang
  // (+ staged avatar) via the user/account service.
  Future<void> _saveAccountInfo() async {
    setState(() => _isSavingAccount = true);
    try {
      // TODO: replace with real call, e.g.
      // await ref.read(userServiceProvider).updateProfile(
      //   avatarPath: _stagedAvatarPath,
      //   fullName: _accFullNameController.text.trim(),
      //   email: _accEmailController.text.trim(),
      //   phone: _accPhoneController.text.trim(),
      //   gender: _accGender,
      //   preferredLang: _accPreferredLang,
      // );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Doctor user account details and avatar saved successfully!')));
      }
      setState(() {
        _isEditingAccount = false;
        _stagedAvatarPath = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Failed to update account details: ${_errorMessage(e)}')));
      }
    } finally {
      if (mounted) setState(() => _isSavingAccount = false);
    }
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

  // Mirrors Angular loadDoctorData(): match logged-in user's userId against
  // /doctors/all to resolve doctorId. If no doctor record exists yet for
  // this account (first login), auto-initialize one via addDoctor — same
  // default payload/fallback logic as Angular — instead of just erroring
  // out. Then load the FULL profile (specialties, languages,
  // qualifications, clinic placements) in one call via getDoctorProfile.
  Future<void> _resolveDoctorIdAndLoad() async {
    try {
      final userId = ref.read(authNotifierProvider).currentUser?.id;
      if (userId == null) {
        throw Exception('No logged-in user found.');
      }
      final doctors = await ref.read(doctorServiceProvider).getAllDoctors();
      final match = doctors.where((d) => d.userId == userId);

      String doctorId;
      if (match.isNotEmpty) {
        doctorId = match.first.doctorId;
      } else {
        // Auto-initialize profile for current logged-in Doctor user
        // (mirrors Angular's initPayload exactly, including the
        // `docterId` field the backend DTO expects).
        try {
          final created = await ref.read(doctorServiceProvider).addDoctor({
            'userId': userId,
            'title': 'DR',
            'mohRegistrationNumber': '',
            'mohVerified': false,
            'bioEn': '',
            'bioAr': '',
            'experienceYears': 0,
            'overallRating': 5.0,
            'reviewCount': 0,
            'consultationFeeSar': 150,
            'isActive': true,
            'docterId': '',
          });
          doctorId = created.doctorId;
        } catch (_) {
          // Same fallback as Angular: if init fails, fall back to the
          // first doctor in the list (if any) rather than dead-ending.
          if (doctors.isNotEmpty) {
            doctorId = doctors.first.doctorId;
          } else {
            rethrow;
          }
        }
      }

      _doctorId = doctorId;
      final profile =
          await ref.read(doctorServiceProvider).getDoctorProfile(doctorId);
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

  // Mirrors Angular saveGeneralProfile(): sends the edited fields *plus*
  // the existing userId/mohVerified/overallRating/reviewCount/isActive
  // (and the `docterId` field the backend DTO expects) so the update
  // doesn't blank out fields the form doesn't edit.
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
        'docterId': _doctorId,
        'userId': _profile?.userId,
        'mohVerified': _profile?.mohVerified ?? false,
        'overallRating': _profile?.overallRating ?? 5.0,
        'reviewCount': _profile?.reviewCount ?? 0,
        'isActive': _profile?.isActive ?? true,
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

  // Small emoji per tab, matching Angular's sub-tab icons.
  static const _tabIcons = ['📝', '🎓', '🗣️', '📜', '🏢'];

  int _tabCount(int i) {
    final p = _profile;
    if (p == null) return 0;
    switch (i) {
      case 1:
        return p.specialties.length;
      case 2:
        return p.languages.length;
      case 3:
        return p.qualifications.length;
      case 4:
        return p.clinics.length;
      default:
        return 0;
    }
  }

  // Mirrors .sub-nav-tabs / .sub-tab-btn: rounded pill strip on a light
  // background, active tab = white pill + soft shadow + badge count.
  Widget _buildSubNavTabs() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray, width: 1.5),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: List.generate(_tabs.length, (i) {
            final active = _activeTab == i;
            final count = _tabCount(i);
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _activeTab = i),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active
                          ? AppTheme.primaryTeal.withValues(alpha: 0.3)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                    boxShadow: active
                        ? [
                            BoxShadow(
                                color: AppTheme.primaryDarkTeal
                                    .withValues(alpha: 0.08),
                                blurRadius: 12,
                                offset: const Offset(0, 4)),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${_tabIcons[i]} ${_tabs[i]}',
                          style: TextStyle(
                              fontWeight:
                                  active ? FontWeight.bold : FontWeight.w600,
                              fontSize: 13,
                              color: active
                                  ? AppTheme.primaryDarkTeal
                                  : AppTheme.textSecondary)),
                      if (i > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 1),
                          decoration: BoxDecoration(
                            color: active
                                ? AppTheme.primaryLightTeal
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('$count',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: active
                                      ? AppTheme.primaryDarkTeal
                                      : AppTheme.textMuted)),
                        ),
                      ],
                    ],
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
        return Column(
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
            _labeled(
              'Biography (English)',
              TextField(
                controller: _bioEnController,
                maxLines: 4,
                decoration: const InputDecoration(
                    hintText: 'Enter your professional biography...'),
              ),
            ),
            const SizedBox(height: 16),
            _labeled(
              'Biography (Arabic)',
              TextField(
                controller: _bioArController,
                maxLines: 4,
                textDirection: TextDirection.rtl,
                decoration:
                    const InputDecoration(hintText: 'أدخل نبذتك المهنية...'),
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
        );

      // ── Tab 1: Specialties (add form + list with remove) ──
      case 1:
        return Column(
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
                      decoration: const InputDecoration(hintText: '-- None --'),
                      items: _subSpecialties
                          .map((ss) => DropdownMenuItem(
                              value: ss.subSpecialtyId, child: Text(ss.nameEn)))
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
                              Row(
                                children: [
                                  const Icon(Icons.health_and_safety_outlined,
                                      size: 18, color: AppTheme.primaryTeal),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _specialtyName(s.specialtyId),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
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
        );

      // ── Tab 2: Languages (add form + list with remove) ──
      case 2:
        return Column(
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
                      onChanged: (val) => setState(() => _langLanguageId = val),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _labeled(
                    'Proficiency',
                    DropdownButtonFormField<LanguageProficiency>(
                      initialValue: _langProficiency,
                      decoration: const InputDecoration(),
                      items: LanguageProficiency.values
                          .map((p) =>
                              DropdownMenuItem(value: p, child: Text(p.value)))
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
                        const Icon(Icons.translate,
                            size: 18, color: AppTheme.primaryTeal),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              '${_languageName(l.languageId)} • ${l.proficiency.value}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
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
        );

      // ── Tab 3: Qualifications (add form + list with remove) ──
      case 3:
        return Column(
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
        );

      // ── Tab 4: Clinic Placements (read-only, matches Angular) ──
      case 4:
      default:
        final clinics = profile?.clinics ?? [];
        final activeCount = clinics.where((c) => c.isActive).length;
        final primaryCount = clinics.where((c) => c.isPrimary).length;
        return clinics.isEmpty
            ? _buildClinicEmptyState()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary strip — mirrors .clinics-summary-strip
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF0F9FF), Color(0xFFE0F2FE)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: const Color(0xFFBAE6FD)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        _summaryStat('${clinics.length}', 'Total',
                            const Color(0xFF0EA5E9)),
                        _vDivider(),
                        _summaryStat(
                            '$activeCount', 'Active', const Color(0xFF22C55E)),
                        _vDivider(),
                        _summaryStat('$primaryCount', 'Primary',
                            AppTheme.primaryDarkTeal),
                      ],
                    ),
                  ),
                  // Placement cards — mirrors .clinic-placement-card
                  ...clinics.map((c) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border(
                            top: const BorderSide(
                                color: AppTheme.borderGray, width: 1.5),
                            right: const BorderSide(
                                color: AppTheme.borderGray, width: 1.5),
                            bottom: const BorderSide(
                                color: AppTheme.borderGray, width: 1.5),
                            left: BorderSide(
                                color: c.isActive
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFF94A3B8),
                                width: 5),
                          ),
                        ),
                        child: Opacity(
                          opacity: c.isActive ? 1 : 0.75,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFE0F2FE),
                                          Color(0xFFBAE6FD)
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.local_hospital_outlined,
                                      color: AppTheme.primaryDarkTeal,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c.clinicNameEn ?? 'Medical Facility',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              color: Color(0xFF1E293B)),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '📍 ${c.branchNameEn ?? 'Main Branch'}',
                                          style: const TextStyle(
                                              fontSize: 12.5,
                                              color: Color(0xFF64748B)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: c.isActive
                                          ? const Color(0xFFDCFCE7)
                                          : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: c.isActive
                                                ? const Color(0xFF22C55E)
                                                : const Color(0xFF94A3B8),
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(c.isActive ? 'Active' : 'Inactive',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: c.isActive
                                                    ? const Color(0xFF166534)
                                                    : const Color(0xFF64748B))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Divider(
                                    height: 1, color: AppTheme.borderGray),
                              ),
                              Wrap(
                                spacing: 16,
                                runSpacing: 10,
                                children: [
                                  _clinicDetail('Department',
                                      chip: c.department,
                                      chipBg: const Color(0xFFE0F2FE),
                                      chipFg: const Color(0xFF0369A1)),
                                  _clinicDetail('Consultation Fee',
                                      text:
                                          'SAR ${c.consultationFeeSar.toStringAsFixed(0)}',
                                      textColor: const Color(0xFF16A34A)),
                                  _clinicDetail('Role',
                                      chip: c.isPrimary
                                          ? 'Primary Specialist'
                                          : 'Consultant',
                                      chipBg: c.isPrimary
                                          ? const Color(0xFFFEF9C3)
                                          : const Color(0xFFF1F5F9),
                                      chipFg: c.isPrimary
                                          ? const Color(0xFF854D0E)
                                          : const Color(0xFF475569)),
                                  _clinicDetail('Since', text: c.startDate),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )),
                ],
              );
    }
  }

  Widget _vDivider() => Container(
        width: 1,
        height: 44,
        color: const Color(0xFFBAE6FD),
      );

  Widget _summaryStat(String num, String label, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(num,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 3),
            Text(label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: Color(0xFF94A3B8))),
          ],
        ),
      ),
    );
  }

  Widget _clinicDetail(String label,
      {String? text,
      String? chip,
      Color? chipBg,
      Color? chipFg,
      Color? textColor}) {
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: Color(0xFF94A3B8))),
          const SizedBox(height: 4),
          if (chip != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(chip,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: chipFg)),
            )
          else
            Text(text ?? '—',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor ?? const Color(0xFF1E293B))),
        ],
      ),
    );
  }

  Widget _buildClinicEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFFE2E8F0), width: 2, style: BorderStyle.solid),
      ),
      child: Column(
        children: const [
          Text('🏥', style: TextStyle(fontSize: 40)),
          SizedBox(height: 10),
          Text('No Clinic Placements Yet',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF64748B))),
          SizedBox(height: 6),
          Text(
              'You are currently not assigned to any clinic branch. Contact your clinic administrator to get assigned.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }

  // Mirrors Angular's `doctorDisplayName` getter:
  //   `${title}. ${name}`  — falls back to 'Dr' / logged-in user's name.
  String get _doctorDisplayName {
    final title = _profile?.title.value ?? 'Dr';
    final name = _profile?.fullName ??
        ref.read(authNotifierProvider).currentUser?.fullName ??
        'Doctor';
    return '$title. $name';
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
            // ── Header banner: mirrors Angular's title + MOH/Reg badges ──
            _buildHeaderBanner(profile, isMobile),
            const SizedBox(height: 24),

            // ── Card 0: User Account Settings & Profile Picture ─────────
            // Angular border-left: var(--primary-dark, #0f172a)
            _buildAccountCard(user, isMobile),
            const SizedBox(height: 24),

            // ── Card 1: Personal Overview & Practice Details ────────────
            // Angular border-left: var(--teal)
            _ProfileCardGroup(
              title: 'Personal Overview & Practice Details',
              accentColor: AppTheme.primaryTeal,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 12,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_doctorDisplayName,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMain)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text.rich(TextSpan(children: [
                            const TextSpan(
                                text: 'Experience: ',
                                style: TextStyle(
                                    fontSize: 12.5, color: AppTheme.textMuted)),
                            TextSpan(
                                text: '${profile?.experienceYears ?? 0} Years',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textSecondary)),
                          ])),
                          Text.rich(TextSpan(children: [
                            const TextSpan(
                                text: 'Rating: ',
                                style: TextStyle(
                                    fontSize: 12.5, color: AppTheme.textMuted)),
                            TextSpan(
                                text:
                                    '⭐ ${profile?.overallRating ?? 0} (${profile?.reviewCount ?? 0} reviews)',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textSecondary)),
                          ])),
                          Text.rich(TextSpan(children: [
                            const TextSpan(
                                text: 'Standard Fee: ',
                                style: TextStyle(
                                    fontSize: 12.5, color: AppTheme.textMuted)),
                            TextSpan(
                                text:
                                    'SAR ${profile?.consultationFeeSar ?? 150}',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF16A34A))),
                          ])),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Card 2: Professional Credentials & Qualifications ───────
            // Angular border-left: var(--accent)
            _ProfileCardGroup(
              title: 'Professional Credentials, Bio & Qualifications',
              accentColor: AppTheme.warningAmber,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSubNavTabs(),
                  const SizedBox(height: 20),
                  _buildTabContent(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mirrors Angular's header banner: h2 title + subtitle on the left,
  // MOH-verified / registration-ID badges on the right (wraps on mobile).
  // NOTE: rating/experience/fee live in the "Personal Overview" card
  // below (Card 1), not here — matches the Angular markup exactly.
  Widget _buildHeaderBanner(DoctorDetailResponse? profile, bool isMobile) {
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.borderGray)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('👨‍⚕️ Professional Profile',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryTeal)),
              const SizedBox(height: 4),
              const Text(
                  'Manage personal bio, clinical credentials, spoken languages, and academic qualifications',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (profile != null)
                Chip(
                  label: Text(profile.mohVerified
                      ? '✓ MOH Verified License'
                      : 'MOH Verification Pending'),
                  labelStyle: TextStyle(
                      color: profile.mohVerified
                          ? const Color(0xFF166534)
                          : const Color(0xFF1E429F),
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5),
                  backgroundColor: profile.mohVerified
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFE1EFFE),
                  side: BorderSide.none,
                ),
              if (profile != null && profile.mohRegistrationNumber.isNotEmpty)
                Chip(
                  label:
                      Text('Registration ID: ${profile.mohRegistrationNumber}'),
                  labelStyle: const TextStyle(
                      color: AppTheme.primaryDarkTeal,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5),
                  backgroundColor: AppTheme.primaryLightTeal,
                  side: BorderSide.none,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // Mirrors Angular Card 0: avatar upload + "1. User Account Details" form.
  // Uses ClipRRect + Stack/Positioned for the accent strip, same fix as
  // _ProfileCardGroup (uniform border/radius, colored strip drawn on top).
  // Accent color matches Angular exactly: var(--primary-dark, #0f172a).
  Widget _buildAccountCard(dynamic user, bool isMobile) {
    const accentColor = Color(0xFF0F172A);
    final pad = isMobile
        ? 14.0
        : 0.0; // wide-screen padding computed inline below via clamp
    final rawAvatarUrl = _profile?.avatarUrl ?? user?.avatarUrl ?? '';
    final avatarUrl = rawAvatarUrl.isNotEmpty
        ? (rawAvatarUrl.startsWith('http')
            ? rawAvatarUrl
            : '$kBaseUrl${rawAvatarUrl.startsWith('/') ? '' : '/'}$rawAvatarUrl')
        : '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.surfaceWhite,
              border: Border.all(color: AppTheme.borderGray),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2)),
              ],
            ),
            padding: EdgeInsets.fromLTRB((isMobile ? pad : 27),
                isMobile ? 14 : 32, isMobile ? 14 : 32, isMobile ? 14 : 32),
            child: Padding(
              padding: const EdgeInsets.only(left: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row: avatar + name/email/role + edit button
                  Container(
                    padding: const EdgeInsets.only(bottom: 12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: const BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: AppTheme.borderGray)),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 12,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: _pickAvatar,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  CircleAvatar(
                                    radius: 34,
                                    backgroundColor: AppTheme.primaryLightTeal,
                                    backgroundImage: avatarUrl.isNotEmpty
                                        ? NetworkImage(avatarUrl)
                                        : null,
                                    onBackgroundImageError: avatarUrl.isNotEmpty
                                        ? (_, __) {}
                                        : null,
                                    child: avatarUrl.isEmpty
                                        ? Text(
                                            user?.initials ?? 'DR',
                                            style: const TextStyle(
                                                color: AppTheme.primaryTeal,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 18),
                                          )
                                        : null,
                                  ),
                                  Positioned(
                                    bottom: -2,
                                    right: -2,
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: accentColor,
                                        border: Border.all(
                                            color: Colors.white, width: 2),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Text('📷',
                                          style: TextStyle(fontSize: 11)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(user?.fullName ?? '',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textMain)),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('✉️ ${user?.email ?? ''}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textMuted)),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text('DOCTOR',
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF166534))),
                                    ),
                                  ],
                                ),
                                if (_stagedAvatarPath != null)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text(
                                        '📷 New profile photo selected. Tap "Save Account Info" to upload.',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFB45309))),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        if (!_isEditingAccount)
                          OutlinedButton(
                            onPressed: _enableAccountEdit,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accentColor,
                              side: const BorderSide(color: accentColor),
                            ),
                            child: const Text('✏️ Edit Account Details'),
                          ),
                      ],
                    ),
                  ),

                  // "1. User Account Details" form
                  const Text('1. User Account Details',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppTheme.textMain)),
                  const SizedBox(height: 12),
                  _responsivePair(
                    _labeled(
                      'Full Name *',
                      TextField(
                        controller: _accFullNameController,
                        enabled: _isEditingAccount,
                      ),
                    ),
                    _labeled(
                      'Email Address *',
                      TextField(
                        controller: _accEmailController,
                        enabled: _isEditingAccount,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _responsivePair(
                    _labeled(
                      'Phone Number',
                      TextField(
                        controller: _accPhoneController,
                        enabled: _isEditingAccount,
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                    _labeled(
                      'Gender',
                      DropdownButtonFormField<String>(
                        initialValue: _accGender,
                        onChanged: _isEditingAccount
                            ? (val) =>
                                setState(() => _accGender = val ?? _accGender)
                            : null,
                        items: const [
                          DropdownMenuItem(value: 'MALE', child: Text('Male')),
                          DropdownMenuItem(
                              value: 'FEMALE', child: Text('Female')),
                          DropdownMenuItem(
                              value: 'OTHER', child: Text('Other')),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _labeled(
                    'Preferred Language',
                    DropdownButtonFormField<String>(
                      initialValue: _accPreferredLang,
                      onChanged: _isEditingAccount
                          ? (val) => setState(() =>
                              _accPreferredLang = val ?? _accPreferredLang)
                          : null,
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(value: 'ar', child: Text('العربية')),
                      ],
                    ),
                  ),

                  if (_isEditingAccount) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.only(top: 12),
                      decoration: const BoxDecoration(
                        border:
                            Border(top: BorderSide(color: AppTheme.borderGray)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed:
                                _isSavingAccount ? null : _cancelAccountEdit,
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed:
                                _isSavingAccount ? null : _saveAccountInfo,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor),
                            child: _isSavingAccount
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Text('💾 Save Account Info'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 5,
            child: ColoredBox(color: accentColor),
          ),
        ],
      ),
    );
  }
}

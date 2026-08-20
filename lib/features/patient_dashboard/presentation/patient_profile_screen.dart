import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/auth_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_notification.dart';
import '../data/patient_service.dart';

class PatientProfileScreen extends ConsumerStatefulWidget {
  const PatientProfileScreen({super.key});

  @override
  ConsumerState<PatientProfileScreen> createState() =>
      _PatientProfileScreenState();
}

class _Nationality {
  final String code;
  final String flag;
  final String name;
  const _Nationality(this.code, this.flag, this.name);
  String get label => '$flag  $name ($code)';
}

const _nationalities = <_Nationality>[
  _Nationality('SA', '🇸🇦', 'Saudi Arabia'),
  _Nationality('AE', '🇦🇪', 'United Arab Emirates'),
  _Nationality('KW', '🇰🇼', 'Kuwait'),
  _Nationality('QA', '🇶🇦', 'Qatar'),
  _Nationality('BH', '🇧🇭', 'Bahrain'),
  _Nationality('OM', '🇴🇲', 'Oman'),
  _Nationality('EG', '🇪🇬', 'Egypt'),
  _Nationality('JO', '🇯🇴', 'Jordan'),
  _Nationality('LB', '🇱🇧', 'Lebanon'),
  _Nationality('SY', '🇸🇾', 'Syria'),
  _Nationality('YE', '🇾🇪', 'Yemen'),
  _Nationality('IQ', '🇮🇶', 'Iraq'),
  _Nationality('SD', '🇸🇩', 'Sudan'),
  _Nationality('PS', '🇵🇸', 'Palestine'),
  _Nationality('TN', '🇹🇳', 'Tunisia'),
  _Nationality('MA', '🇲🇦', 'Morocco'),
  _Nationality('DZ', '🇩🇿', 'Algeria'),
  _Nationality('IN', '🇮🇳', 'India'),
  _Nationality('PK', '🇵🇰', 'Pakistan'),
  _Nationality('BD', '🇧🇩', 'Bangladesh'),
  _Nationality('PH', '🇵🇭', 'Philippines'),
  _Nationality('ID', '🇮🇩', 'Indonesia'),
  _Nationality('US', '🇺🇸', 'United States'),
  _Nationality('GB', '🇬🇧', 'United Kingdom'),
  _Nationality('CA', '🇨🇦', 'Canada'),
  _Nationality('AU', '🇦🇺', 'Australia'),
  _Nationality('DE', '🇩🇪', 'Germany'),
  _Nationality('FR', '🇫🇷', 'France'),
  _Nationality('IT', '🇮🇹', 'Italy'),
  _Nationality('ES', '🇪🇸', 'Spain'),
  _Nationality('TR', '🇹🇷', 'Turkey'),
  _Nationality('OT', '🌐', 'Other'),
];

class _PatientProfileScreenState extends ConsumerState<PatientProfileScreen> {
  // Account Form State (User)
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  Gender _gender = Gender.MALE;
  String _preferredLang = 'en';
  bool _isEditingAccount = false;
  bool _isSavingAccount = false;

  // Medical Profile Form State (Patient)
  final _nationalIdController = TextEditingController();
  final _emergencyContactNameController = TextEditingController();
  final _emergencyContactPhoneController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _dateOfBirth;
  String _bloodType = 'Unknown';
  String _maritalStatus = 'SINGLE';
  String? _nationalityCode = 'SA';

  static const _bloodTypes = [
    'A_POS',
    'A_NEG',
    'B_POS',
    'B_NEG',
    'AB_POS',
    'AB_NEG',
    'O_POS',
    'O_NEG',
    'Unknown'
  ];
  static const _maritalStatuses = ['SINGLE', 'MARRIED', 'DIVORCED', 'WIDOWED'];

  static final _nationalIdPattern = RegExp(r'^[0-9a-zA-Z]{5,20}$');
  static final _phonePattern = RegExp(r'^\+?[0-9 \-]{7,20}$');

  bool _isLoading = true;
  bool _isSavingMedical = false;
  bool _profileExists = false;
  bool _isEditMode = false;
  bool _dobTouched = false;
  bool _autovalidate = false;

  @override
  void initState() {
    super.initState();
    _initAccountData();
    _loadProfile();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _nationalIdController.dispose();
    _emergencyContactNameController.dispose();
    _emergencyContactPhoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _initAccountData() {
    final user = ref.read(authNotifierProvider).currentUser;
    if (user != null) {
      _fullNameController.text = user.fullName;
      _emailController.text = user.email;
      _phoneController.text = user.phone ?? '';
      _gender = user.gender ?? Gender.MALE;
      _preferredLang = user.preferredLang;
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    _initAccountData();
    try {
      final profile = await ref.read(patientServiceProvider).getMyProfile();
      if (mounted) {
        if (profile != null && profile is Map && profile['patientId'] != null) {
          setState(() {
            _profileExists = true;
            _isEditMode = false;
            _autovalidate = false;
            _dobTouched = false;
            _nationalIdController.text = profile['nationalId'] ?? '';
            _nationalityCode = profile['nationality'] ?? 'SA';
            _emergencyContactNameController.text =
                profile['emergencyContactName'] ?? '';
            _emergencyContactPhoneController.text =
                profile['emergencyContactPhone'] ?? '';
            _notesController.text = profile['notes'] ?? '';
            _bloodType = profile['bloodType'] ?? 'Unknown';
            _maritalStatus = profile['maritalStatus'] ?? 'SINGLE';
            _dateOfBirth = profile['dateOfBirth'] != null
                ? DateTime.tryParse(profile['dateOfBirth'])
                : null;
          });
        } else {
          setState(() {
            _profileExists = false;
            _isEditMode = false;
            _autovalidate = false;
            _dobTouched = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _profileExists = false;
          _isEditMode = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Account Save ───────────────────────────────────────────────────────
  Future<void> _saveAccountInfo() async {
    if (_fullNameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty) {
      AppNotification.showWarning(
        context,
        'Full name and email are required.',
      );
      return;
    }

    setState(() => _isSavingAccount = true);
    try {
      await ref.read(authNotifierProvider.notifier).updateUserProfile({
        'fullName': _fullNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'gender': _gender.value,
        'preferredLang': _preferredLang,
      });

      if (mounted) {
        setState(() => _isEditingAccount = false);
        AppNotification.showSuccess(
          context,
          'Account details updated successfully.',
        );
      }
    } catch (_) {
      if (mounted) {
        AppNotification.showError(
          context,
          'Failed to update account details.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingAccount = false);
    }
  }

  void _cancelAccountEdit() {
    setState(() => _isEditingAccount = false);
    _initAccountData();
  }

  // ── Medical Profile Save ────────────────────────────────────────────────
  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(1995, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
    setState(() => _dobTouched = true);
  }

  Future<void> _pickNationality() async {
    if (!_isEditMode) return;
    String query = '';
    final picked = await showModalBottomSheet<_Nationality>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = _nationalities
              .where((n) =>
                  query.isEmpty ||
                  n.name.toLowerCase().contains(query.toLowerCase()) ||
                  n.code.toLowerCase().contains(query.toLowerCase()))
              .toList();

          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: const BoxDecoration(
              color: AppTheme.surfaceWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.borderGray,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select Nationality',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search country name or code...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: AppTheme.backgroundApp,
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (v) => setSheetState(() => query = v),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final n = filtered[i];
                      final isSelected = n.code == _nationalityCode;
                      return ListTile(
                        leading:
                            Text(n.flag, style: const TextStyle(fontSize: 22)),
                        title: Text(n.name,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(n.code,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textMuted)),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle,
                                color: AppTheme.primaryTeal, size: 20)
                            : null,
                        onTap: () => Navigator.pop(ctx, n),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (picked != null) setState(() => _nationalityCode = picked.code);
  }

  bool get _dobValid => _dateOfBirth != null;
  bool get _nationalIdValid =>
      _nationalIdPattern.hasMatch(_nationalIdController.text.trim());
  bool get _emergencyNameValid =>
      _emergencyContactNameController.text.trim().isNotEmpty;
  bool get _emergencyPhoneValid =>
      _phonePattern.hasMatch(_emergencyContactPhoneController.text.trim());

  bool get _isMedicalFormValid =>
      _dobValid &&
      _nationalIdValid &&
      _emergencyNameValid &&
      _emergencyPhoneValid;

  Future<void> _saveMedicalProfile() async {
    setState(() {
      _dobTouched = true;
      _autovalidate = true;
    });

    if (!_isMedicalFormValid) {
      AppNotification.showWarning(
        context,
        'Please fill all required medical fields.',
      );
      return;
    }

    setState(() => _isSavingMedical = true);
    final dob =
        '${_dateOfBirth!.year.toString().padLeft(4, '0')}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}';
    final dto = {
      'dateOfBirth': dob,
      'bloodType': _bloodType,
      'nationalId': _nationalIdController.text.trim(),
      'nationality': _nationalityCode,
      'maritalStatus': _maritalStatus,
      'emergencyContactName': _emergencyContactNameController.text.trim(),
      'emergencyContactPhone': _emergencyContactPhoneController.text.trim(),
      'notes': _notesController.text.trim(),
    };

    try {
      final pService = ref.read(patientServiceProvider);
      final res = _profileExists
          ? await pService.updateProfile(dto)
          : await pService.createProfile(dto);

      if (mounted) {
        AppNotification.showSuccess(
          context,
          _profileExists
              ? 'Medical profile updated successfully.'
              : 'Patient profile initialized successfully.',
        );
        setState(() {
          _profileExists = true;
          _isEditMode = false;
          _autovalidate = false;
          if (res is Map && res['nationality'] != null) {
            _nationalityCode = res['nationality'];
          }
        });
      }
    } catch (e) {
      final msg = e is DioException
          ? (e.response?.data?['message'] ?? 'Failed to save medical profile.')
          : 'Failed to save medical profile.';
      if (mounted) {
        AppNotification.showError(
          context,
          msg.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingMedical = false);
    }
  }

  void _cancelMedicalEdit() {
    if (_profileExists) {
      setState(() => _isEditMode = false);
      _loadProfile();
    } else {
      setState(() => _isEditMode = false);
    }
  }

  // ── Main UI Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).currentUser;
    final isMobile = MediaQuery.of(context).size.width <= 600;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundApp,
        body: Center(
            child: CircularProgressIndicator(color: AppTheme.primaryTeal)),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundApp,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryTeal,
          onRefresh: _loadProfile,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: isMobile ? 16 : 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Account Settings Card (User details)
                _buildUserAccountCard(user, isMobile),
                const SizedBox(height: 20),

                // 2. Patient Medical Profile Card
                _buildMedicalProfileCard(isMobile),
                const SizedBox(height: 20),

                // 3. Healthcare Network Onboarding Card
                _buildHealthcareNetworkCard(isMobile),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 1. USER ACCOUNT & PROFILE CARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildUserAccountCard(UserModel? user, bool isMobile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    user?.initials ?? 'P',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.fullName ?? 'Patient Account',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user?.email ?? '',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLightTeal,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        user?.role.value ?? 'PATIENT',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryDarkTeal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_isEditingAccount) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _isEditingAccount = true),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(40, 32),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.edit, size: 14),
                label:
                    const Text('Edit Account', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          const Text(
            '1. Account & User Details',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryTeal),
          ),
          const SizedBox(height: 12),

          // Full Name
          const Text('Full Name *',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _fullNameController,
            enabled: _isEditingAccount,
            decoration: InputDecoration(
              isDense: true,
              filled: !_isEditingAccount,
              fillColor:
                  !_isEditingAccount ? AppTheme.backgroundApp : Colors.white,
            ),
          ),
          const SizedBox(height: 12),

          // Email
          const Text('Email Address *',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailController,
            enabled: _isEditingAccount,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              isDense: true,
              filled: !_isEditingAccount,
              fillColor:
                  !_isEditingAccount ? AppTheme.backgroundApp : Colors.white,
            ),
          ),
          const SizedBox(height: 12),

          // Phone
          const Text('Phone Number',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _phoneController,
            enabled: _isEditingAccount,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              isDense: true,
              hintText: '+966 50 000 0000',
              filled: !_isEditingAccount,
              fillColor:
                  !_isEditingAccount ? AppTheme.backgroundApp : Colors.white,
            ),
          ),
          const SizedBox(height: 12),

          // Gender & Language Dropdowns
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Gender',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<Gender>(
                      value: _gender,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: !_isEditingAccount,
                        fillColor: !_isEditingAccount
                            ? AppTheme.backgroundApp
                            : Colors.white,
                      ),
                      items: Gender.values
                          .map((g) => DropdownMenuItem(
                                value: g,
                                child: Text(g.value.replaceAll('_', ' ')),
                              ))
                          .toList(),
                      onChanged: _isEditingAccount
                          ? (v) => setState(() => _gender = v ?? _gender)
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Language',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _preferredLang,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: !_isEditingAccount,
                        fillColor: !_isEditingAccount
                            ? AppTheme.backgroundApp
                            : Colors.white,
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'en', child: Text('English (EN)')),
                        DropdownMenuItem(
                            value: 'ar', child: Text('العربية (AR)')),
                      ],
                      onChanged: _isEditingAccount
                          ? (v) => setState(
                              () => _preferredLang = v ?? _preferredLang)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (_isEditingAccount) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _cancelAccountEdit,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isSavingAccount ? null : _saveAccountInfo,
                  child: _isSavingAccount
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save Account Info'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. PATIENT MEDICAL PROFILE CARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMedicalProfileCard(bool isMobile) {
    final locked = _profileExists && !_isEditMode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '2. Medical & Emergency Profile',
            style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryTeal),
          ),
          const SizedBox(height: 2),
          Text(
            _profileExists
                ? 'Registered Patient Record'
                : 'Profile registration required',
            style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          ),
          if (locked) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _isEditMode = true),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(40, 32),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('Edit Medical Info',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Unregistered Alert Card (If no profile exists and not editing)
          if (!_profileExists && !_isEditMode) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFCBD5E1), style: BorderStyle.solid),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE0F2FE),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.badge_outlined,
                        color: Color(0xFF0284C7), size: 28),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'No Patient Profile Registered',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Complete your medical details to enable EMR records, prescription tracking, and doctor bookings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textMuted, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => setState(() => _isEditMode = true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Create Patient Profile Now',
                        style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Form Fields (Visible if profileExists OR isEditMode)
            // Date of Birth & Blood Group
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Date of Birth *',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: locked ? null : _pickDob,
                        borderRadius: BorderRadius.circular(10),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            isDense: true,
                            filled: locked,
                            fillColor:
                                locked ? AppTheme.backgroundApp : Colors.white,
                            suffixIcon:
                                const Icon(Icons.calendar_today, size: 16),
                          ),
                          child: Text(
                            _dateOfBirth == null
                                ? 'Select Date'
                                : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      if (_dobTouched && !_dobValid)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text('Date of birth is required.',
                              style: TextStyle(
                                  color: AppTheme.dangerRed, fontSize: 11)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Blood Group *',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _bloodType,
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          filled: locked,
                          fillColor:
                              locked ? AppTheme.backgroundApp : Colors.white,
                        ),
                        items: _bloodTypes
                            .map((b) => DropdownMenuItem(
                                value: b, child: Text(b.replaceAll('_', ' '))))
                            .toList(),
                        onChanged: locked
                            ? null
                            : (v) =>
                                setState(() => _bloodType = v ?? _bloodType),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // National ID & Nationality
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('National ID / Iqama *',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nationalIdController,
                        enabled: !locked,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'e.g. 1029384756',
                          filled: locked,
                          fillColor:
                              locked ? AppTheme.backgroundApp : Colors.white,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      if (_autovalidate && !_nationalIdValid)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text('5-20 alphanumeric characters.',
                              style: TextStyle(
                                  color: AppTheme.dangerRed, fontSize: 11)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Nationality *',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: locked ? null : _pickNationality,
                        borderRadius: BorderRadius.circular(10),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            isDense: true,
                            filled: locked,
                            fillColor:
                                locked ? AppTheme.backgroundApp : Colors.white,
                            suffixIcon:
                                const Icon(Icons.arrow_drop_down, size: 20),
                          ),
                          child: Text(
                            _nationalityCode != null
                                ? '${_nationalities.firstWhere((n) => n.code == _nationalityCode, orElse: () => const _Nationality('', '🌐', '')).flag} $_nationalityCode'
                                : 'Select Nationality',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Marital Status
            const Text('Marital Status *',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _maritalStatus,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                filled: locked,
                fillColor: locked ? AppTheme.backgroundApp : Colors.white,
              ),
              items: _maritalStatuses
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: locked
                  ? null
                  : (v) => setState(() => _maritalStatus = v ?? _maritalStatus),
            ),
            const SizedBox(height: 14),

            // Emergency Contact Person & Phone
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Emergency Contact *',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emergencyContactNameController,
                        enabled: !locked,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Full Name',
                          filled: locked,
                          fillColor:
                              locked ? AppTheme.backgroundApp : Colors.white,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Emergency Phone *',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emergencyContactPhoneController,
                        enabled: !locked,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: '+966 50...',
                          filled: locked,
                          fillColor:
                              locked ? AppTheme.backgroundApp : Colors.white,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Special Medical Notes
            const Text('Medical Notes & Special Observations',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _notesController,
              enabled: !locked,
              minLines: 2,
              maxLines: 3,
              decoration: InputDecoration(
                isDense: true,
                hintText:
                    'Any ongoing medical observations or special emergency requirements...',
                filled: locked,
                fillColor: locked ? AppTheme.backgroundApp : Colors.white,
              ),
            ),

            if (!locked) ...[
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _cancelMedicalEdit,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _isSavingMedical ? null : _saveMedicalProfile,
                    child: _isSavingMedical
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_profileExists
                            ? 'Save Medical Profile'
                            : 'Save & Register Profile'),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. HEALTHCARE NETWORK ONBOARDING OPTIONS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHealthcareNetworkCard(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '3. Healthcare Provider & Facility Registration',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryTeal),
          ),
          const SizedBox(height: 4),
          const Text(
            'Expand your role on MedConsult to consult patients as a doctor or manage clinic branches.',
            style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 14),
          _buildOnboardRow(
            title: 'Join as a Doctor',
            subtitle: 'Apply for medical credentials & consult patients',
            badge: 'DOCTOR',
            badgeColor: const Color(0xFF0F766E),
            icon: Icons.medical_services_outlined,
            onTap: () => context.go('/patient/become-doctor'),
          ),
          const SizedBox(height: 10),
          _buildOnboardRow(
            title: 'Register a Clinic',
            subtitle: 'List your medical center & manage clinic branches',
            badge: 'CLINIC',
            badgeColor: const Color(0xFF1E40AF),
            icon: Icons.local_hospital_outlined,
            onTap: () => context.go('/patient/become-clinic'),
          ),
        ],
      ),
    );
  }

  Widget _buildOnboardRow({
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundApp,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: badgeColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13.5)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(60, 30),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Apply', style: TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }
}

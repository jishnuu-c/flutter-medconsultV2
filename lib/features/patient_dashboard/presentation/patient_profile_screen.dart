import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../data/patient_service.dart';

class PatientProfileScreen extends ConsumerStatefulWidget {
  const PatientProfileScreen({super.key});

  @override
  ConsumerState<PatientProfileScreen> createState() =>
      _PatientProfileScreenState();
}

// Country list mirrors Angular's `nationalities` array (code + flag emoji).
class _Nationality {
  final String code;
  final String flag;
  const _Nationality(this.code, this.flag);
  String get label => '$flag $code';
}

const _nationalities = <_Nationality>[
  _Nationality('SA', '🇸🇦'),
  _Nationality('AE', '🇦🇪'),
  _Nationality('KW', '🇰🇼'),
  _Nationality('QA', '🇶🇦'),
  _Nationality('BH', '🇧🇭'),
  _Nationality('OM', '🇴🇲'),
  _Nationality('EG', '🇪🇬'),
  _Nationality('JO', '🇯🇴'),
  _Nationality('LB', '🇱🇧'),
  _Nationality('SY', '🇸🇾'),
  _Nationality('YE', '🇾🇪'),
  _Nationality('IQ', '🇮🇶'),
  _Nationality('SD', '🇸🇩'),
  _Nationality('PS', '🇵🇸'),
  _Nationality('TN', '🇹🇳'),
  _Nationality('MA', '🇲🇦'),
  _Nationality('DZ', '🇩🇿'),
  _Nationality('IN', '🇮🇳'),
  _Nationality('PK', '🇵🇰'),
  _Nationality('BD', '🇧🇩'),
  _Nationality('PH', '🇵🇭'),
  _Nationality('ID', '🇮🇩'),
  _Nationality('US', '🇺🇸'),
  _Nationality('GB', '🇬🇧'),
  _Nationality('CA', '🇨🇦'),
  _Nationality('AU', '🇦🇺'),
  _Nationality('DE', '🇩🇪'),
  _Nationality('FR', '🇫🇷'),
  _Nationality('IT', '🇮🇹'),
  _Nationality('ES', '🇪🇸'),
  _Nationality('TR', '🇹🇷'),
  _Nationality('OT', '🌐'),
];

class _PatientProfileScreenState extends ConsumerState<PatientProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nationalIdController = TextEditingController();
  final _emergencyContactNameController = TextEditingController();
  final _emergencyContactPhoneController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _dateOfBirth;
  String _bloodType = 'Unknown';
  String _maritalStatus = 'SINGLE';
  String? _nationalityCode;

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

  bool _isLoading = false;
  bool _isSaving = false;
  bool _profileExists = false;
  bool _isEditMode = false;
  bool _dobTouched = false;
  bool _autovalidate = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nationalIdController.dispose();
    _emergencyContactNameController.dispose();
    _emergencyContactPhoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final profile = await ref.read(patientServiceProvider).getMyProfile();
      if (mounted) {
        setState(() {
          _profileExists = true;
          _isEditMode = false;
          _autovalidate = false;
          _dobTouched = false;
          _nationalIdController.text = profile['nationalId'] ?? '';
          _nationalityCode = profile['nationality'];
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
      }
    } catch (e) {
      final status = e is DioException ? e.response?.statusCode : null;
      if (status == 404) {
        if (mounted) {
          setState(() {
            _profileExists = false;
            _isEditMode = true; // auto-edit for creation
          });
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load patient profile.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(1990, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
    setState(() => _dobTouched = true);
  }

  void _enableEdit() => setState(() => _isEditMode = true);

  // Mirrors Angular's routes to /patient/become-doctor and
  // /patient/become-clinic.
  void _goToBecomeDoctor() => context.go('/patient/become-doctor');

  void _goToBecomeClinic() => context.go('/patient/become-clinic');

  void _cancelEdit() {
    if (_profileExists) {
      // Angular re-fetches the saved profile on cancel to discard edits.
      _loadProfile();
    }
  }

  Future<void> _pickNationality() async {
    if (!_isEditMode) return;
    String query = '';
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = _nationalities
              .where((n) => query.isEmpty
                  ? true
                  : n.code.toLowerCase().contains(query.toLowerCase()))
              .toList();
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: const BoxDecoration(
                color: AppTheme.surfaceWhite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
                    child: Text('Select Nationality',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    autofocus: false,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search country code...',
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
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final n = filtered[i];
                        return ListTile(
                          leading: Text(n.flag,
                              style: const TextStyle(fontSize: 20)),
                          title: Text(n.code),
                          onTap: () => Navigator.pop(ctx, n.code),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (picked != null) setState(() => _nationalityCode = picked);
  }

  bool get _dobValid => _dateOfBirth != null;
  bool get _nationalIdValid =>
      _nationalIdPattern.hasMatch(_nationalIdController.text.trim());
  bool get _nationalityValid =>
      _nationalityCode != null && _nationalityCode!.trim().length >= 2;
  bool get _emergencyNameValid =>
      _emergencyContactNameController.text.trim().isNotEmpty;
  bool get _emergencyPhoneValid =>
      _phonePattern.hasMatch(_emergencyContactPhoneController.text.trim());

  bool get _formValid =>
      _dobValid &&
      _nationalIdValid &&
      _nationalityValid &&
      _emergencyNameValid &&
      _emergencyPhoneValid;

  Future<void> _saveProfile() async {
    setState(() {
      _dobTouched = true;
      _autovalidate = true;
    });
    if (!_formValid) return;

    setState(() => _isSaving = true);
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_profileExists
                ? 'Profile updated successfully.'
                : 'Profile initialized successfully.')));
        setState(() {
          _profileExists = true;
          _isEditMode = false;
          _autovalidate = false;
          if (res['nationality'] != null) _nationalityCode = res['nationality'];
        });
      }
    } catch (e) {
      final msg = e is DioException
          ? (e.response?.data?['message'] ?? 'Failed to save profile.')
          : 'Failed to save profile.';
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg.toString())));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _fieldLabel(String text, {bool required = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(children: [
          TextSpan(
              text: text,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          if (required)
            const TextSpan(
                text: ' *', style: TextStyle(color: AppTheme.dangerRed)),
        ])),
      );

  Widget _errorText(String msg) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(msg,
            style: const TextStyle(color: AppTheme.dangerRed, fontSize: 12)),
      );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).currentUser;
    final isMobile = MediaQuery.of(context).size.width <= 576;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final nationalitySelected =
        _nationalities.where((n) => n.code == _nationalityCode).toList();

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 14 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 16 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar header — Row uses Expanded for the text block so
                    // long labels wrap instead of overflowing on narrow
                    // screens, and action buttons live in their own Wrap
                    // below (a Wrap child must never be given infinite
                    // width, which was causing the overflow/crash before).
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CircleAvatar(
                          radius: 28,
                          backgroundColor: AppTheme.primaryLightTeal,
                          child: Text('👤', style: TextStyle(fontSize: 24)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Patient Medical Profile',
                                  style: TextStyle(
                                      fontSize: isMobile ? 17 : 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textMain)),
                              const SizedBox(height: 2),
                              const Text(
                                'Registered Patient Consultation Records & Emergency Information',
                                style: TextStyle(
                                    fontSize: 12, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!_isEditMode) ...[
                      const SizedBox(height: 14),
                      isMobile
                          ? Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _goToBecomeDoctor,
                                    icon: const Text('🩺'),
                                    label: const Text('Register as Doctor'),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _goToBecomeClinic,
                                    icon: const Text('🏥'),
                                    label: const Text('Register Clinic'),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _enableEdit,
                                    icon: const Icon(Icons.edit, size: 16),
                                    label: const Text('Edit Profile'),
                                  ),
                                ),
                              ],
                            )
                          : Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _goToBecomeDoctor,
                                  icon: const Text('🩺'),
                                  label: const Text('Register as Doctor'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _goToBecomeClinic,
                                  icon: const Text('🏥'),
                                  label: const Text('Register Clinic'),
                                ),
                                ElevatedButton.icon(
                                  onPressed: _enableEdit,
                                  icon: const Icon(Icons.edit, size: 16),
                                  label: const Text('Edit Profile'),
                                ),
                              ],
                            ),
                    ],
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Section 1: General Information
                    const Text('1. General Information',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal)),
                    const SizedBox(height: 14),

                    _ResponsiveTwoCol(
                      isMobile: isMobile,
                      children: [
                        // Date of birth
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('Date of Birth', required: true),
                            IgnorePointer(
                              ignoring: !_isEditMode,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  alignment: Alignment.centerLeft,
                                  minimumSize: const Size(double.infinity, 44),
                                ),
                                icon:
                                    const Icon(Icons.calendar_today, size: 16),
                                label: Text(_dateOfBirth == null
                                    ? 'Select date of birth'
                                    : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}'),
                                onPressed: _isEditMode ? _pickDob : null,
                              ),
                            ),
                            if (_dobTouched && !_dobValid)
                              _errorText('Date of birth is required.'),
                          ],
                        ),
                        // Blood type
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('Blood Group', required: true),
                            DropdownButtonFormField<String>(
                              initialValue: _bloodType,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                              items: _bloodTypes
                                  .map((b) => DropdownMenuItem(
                                      value: b,
                                      child: Text(b.replaceAll('_', ' '))))
                                  .toList(),
                              onChanged: _isEditMode
                                  ? (val) => setState(
                                      () => _bloodType = val ?? _bloodType)
                                  : null,
                            ),
                          ],
                        ),
                        // National ID
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('National ID / Iqama', required: true),
                            TextFormField(
                              controller: _nationalIdController,
                              enabled: _isEditMode,
                              autovalidateMode: _autovalidate
                                  ? AutovalidateMode.onUserInteraction
                                  : AutovalidateMode.disabled,
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: 'E.g. 1092837493',
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: (_) => _nationalIdValid
                                  ? null
                                  : 'Valid National ID is required (5-20 characters).',
                            ),
                          ],
                        ),
                        // Nationality (searchable picker, matches Angular's searchable custom-select)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('Nationality', required: true),
                            InkWell(
                              onTap: _isEditMode ? _pickNationality : null,
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        nationalitySelected.isNotEmpty
                                            ? nationalitySelected.first.label
                                            : '-- Select Nationality --',
                                        style: TextStyle(
                                          color: nationalitySelected.isNotEmpty
                                              ? AppTheme.textMain
                                              : AppTheme.textMuted,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.arrow_drop_down,
                                        color: AppTheme.textMuted),
                                  ],
                                ),
                              ),
                            ),
                            if (_autovalidate && !_nationalityValid)
                              _errorText('Nationality is required.'),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Marital status (single, full-width like Angular)
                    _fieldLabel('Marital Status'),
                    DropdownButtonFormField<String>(
                      initialValue: _maritalStatus,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: _maritalStatuses
                          .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)))
                          .toList(),
                      onChanged: _isEditMode
                          ? (val) => setState(
                              () => _maritalStatus = val ?? _maritalStatus)
                          : null,
                    ),

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Section 2: Emergency Contact
                    const Text('2. Emergency Contact Information',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal)),
                    const SizedBox(height: 14),

                    _ResponsiveTwoCol(
                      isMobile: isMobile,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('Contact Full Name', required: true),
                            TextFormField(
                              controller: _emergencyContactNameController,
                              enabled: _isEditMode,
                              autovalidateMode: _autovalidate
                                  ? AutovalidateMode.onUserInteraction
                                  : AutovalidateMode.disabled,
                              decoration:
                                  const InputDecoration(hintText: 'Jane Doe'),
                              onChanged: (_) => setState(() {}),
                              validator: (_) => _emergencyNameValid
                                  ? null
                                  : 'Emergency contact name is required.',
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('Contact Phone Number', required: true),
                            TextFormField(
                              controller: _emergencyContactPhoneController,
                              enabled: _isEditMode,
                              keyboardType: TextInputType.phone,
                              autovalidateMode: _autovalidate
                                  ? AutovalidateMode.onUserInteraction
                                  : AutovalidateMode.disabled,
                              decoration: const InputDecoration(
                                  hintText: '+966 50 000 0000'),
                              onChanged: (_) => setState(() {}),
                              validator: (_) => _emergencyPhoneValid
                                  ? null
                                  : 'Valid phone number is required.',
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Section 3: Notes
                    _fieldLabel('3. Additional Health Notes (Optional)'),
                    TextField(
                      controller: _notesController,
                      enabled: _isEditMode,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText:
                            'List any general health preferences or notes for your consulting doctor...',
                      ),
                    ),

                    if (_isEditMode) ...[
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),
                      isMobile
                          ? Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isSaving ? null : _saveProfile,
                                    child: _isSaving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white))
                                        : const Text('Save Profile'),
                                  ),
                                ),
                                if (_profileExists) ...[
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton(
                                      onPressed: _cancelEdit,
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (_profileExists)
                                  TextButton(
                                    onPressed: _cancelEdit,
                                    child: const Text('Cancel'),
                                  ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: _isSaving ? null : _saveProfile,
                                  child: _isSaving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white))
                                      : const Text('Save Profile'),
                                ),
                              ],
                            ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Two columns on wide screens, stacked single column on mobile —
// mirrors Angular's `.form-two-col` which collapses at its own breakpoint.
class _ResponsiveTwoCol extends StatelessWidget {
  final bool isMobile;
  final List<Widget> children;
  const _ResponsiveTwoCol({required this.isMobile, required this.children});

  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      return Column(
        children: [
          for (final c in children) ...[
            c,
            const SizedBox(height: 16),
          ],
        ],
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      final hasSecond = i + 1 < children.length;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[i]),
            if (hasSecond) ...[
              const SizedBox(width: 20),
              Expanded(child: children[i + 1]),
            ] else
              const Expanded(child: SizedBox()),
          ],
        ),
      ));
    }
    return Column(children: rows);
  }
}

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../data/patient_service.dart';

class PatientProfileScreen extends ConsumerStatefulWidget {
  const PatientProfileScreen({super.key});

  @override
  ConsumerState<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends ConsumerState<PatientProfileScreen> {
  final _nationalIdController = TextEditingController();
  final _nationalityController = TextEditingController();
  final _emergencyContactNameController = TextEditingController();
  final _emergencyContactPhoneController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _dateOfBirth;
  String _bloodType = 'Unknown';
  String _maritalStatus = 'SINGLE';

  static const _bloodTypes = ['A_POS', 'A_NEG', 'B_POS', 'B_NEG', 'AB_POS', 'AB_NEG', 'O_POS', 'O_NEG', 'Unknown'];
  static const _maritalStatuses = ['SINGLE', 'MARRIED', 'DIVORCED', 'WIDOWED'];

  bool _isLoading = false;
  bool _isSaving = false;
  bool _profileExists = false;
  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nationalIdController.dispose();
    _nationalityController.dispose();
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
          _nationalIdController.text = profile['nationalId'] ?? '';
          _nationalityController.text = profile['nationality'] ?? '';
          _emergencyContactNameController.text = profile['emergencyContactName'] ?? '';
          _emergencyContactPhoneController.text = profile['emergencyContactPhone'] ?? '';
          _notesController.text = profile['notes'] ?? '';
          _bloodType = profile['bloodType'] ?? 'Unknown';
          _maritalStatus = profile['maritalStatus'] ?? 'SINGLE';
          if (profile['dateOfBirth'] != null) {
            _dateOfBirth = DateTime.tryParse(profile['dateOfBirth']);
          }
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
  }

  Future<void> _saveProfile() async {
    if (_dateOfBirth == null || _nationalIdController.text.trim().isEmpty || _nationalityController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in date of birth, national ID, and nationality.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final dob =
        '${_dateOfBirth!.year.toString().padLeft(4, '0')}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}';
    final dto = {
      'dateOfBirth': dob,
      'bloodType': _bloodType,
      'nationalId': _nationalIdController.text.trim(),
      'nationality': _nationalityController.text.trim(),
      'maritalStatus': _maritalStatus,
      'emergencyContactName': _emergencyContactNameController.text.trim(),
      'emergencyContactPhone': _emergencyContactPhoneController.text.trim(),
      'notes': _notesController.text.trim(),
    };

    try {
      final pService = ref.read(patientServiceProvider);
      if (_profileExists) {
        await pService.updateProfile(dto);
      } else {
        await pService.createProfile(dto);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Patient profile saved successfully.')),
        );
        setState(() {
          _profileExists = true;
          _isEditMode = false;
        });
      }
    } catch (e) {
      final msg = e is DioException ? (e.response?.data?['message'] ?? 'Failed to save profile.') : 'Failed to save profile.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.toString())));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).currentUser;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Patient Consultation Profile', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                    SizedBox(height: 4),
                    Text('Your general patient registration records', style: TextStyle(fontSize: 14, color: AppTheme.textMuted)),
                  ],
                ),
                if (_profileExists && !_isEditMode)
                  ElevatedButton(
                    onPressed: () => setState(() => _isEditMode = true),
                    child: const Text('Edit Profile'),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppTheme.primaryLightTeal,
                          child: Text(
                            user?.initials ?? 'P',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user?.fullName ?? 'Patient Name',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textMain)),
                            const SizedBox(height: 4),
                            Text(user?.email ?? '', style: const TextStyle(fontSize: 14, color: AppTheme.textMuted)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),

                    const Text('Date of Birth', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    IgnorePointer(
                      ignoring: !_isEditMode,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(_dateOfBirth == null
                            ? 'Select date of birth'
                            : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}'),
                        onPressed: _isEditMode ? _pickDob : null,
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text('Blood Group', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _bloodType,
                      items: _bloodTypes.map((b) => DropdownMenuItem(value: b, child: Text(b.replaceAll('_', ' ')))).toList(),
                      onChanged: _isEditMode ? (val) => setState(() => _bloodType = val ?? _bloodType) : null,
                    ),
                    const SizedBox(height: 16),

                    const Text('National ID / Iqama', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nationalIdController,
                      enabled: _isEditMode,
                      decoration: const InputDecoration(hintText: 'E.g. 1092837493'),
                    ),
                    const SizedBox(height: 16),

                    const Text('Nationality', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nationalityController,
                      enabled: _isEditMode,
                      decoration: const InputDecoration(hintText: 'Saudi Arabia'),
                    ),
                    const SizedBox(height: 16),

                    const Text('Marital Status', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _maritalStatus,
                      items: _maritalStatuses.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                      onChanged: _isEditMode ? (val) => setState(() => _maritalStatus = val ?? _maritalStatus) : null,
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),

                    const Text('Emergency Contact', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Contact Full Name', style: TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _emergencyContactNameController,
                                enabled: _isEditMode,
                                decoration: const InputDecoration(hintText: 'Jane Doe'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Contact Phone', style: TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _emergencyContactPhoneController,
                                enabled: _isEditMode,
                                decoration: const InputDecoration(hintText: '+966 50 000 0000'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    const Text('Additional Health Notes (Optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _notesController,
                      enabled: _isEditMode,
                      maxLines: 3,
                      decoration: const InputDecoration(hintText: 'List any general health comments, preferences or constraints...'),
                    ),

                    if (_isEditMode) ...[
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (_profileExists)
                            TextButton(
                              onPressed: () => setState(() => _isEditMode = false),
                              child: const Text('Cancel'),
                            ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _isSaving ? null : _saveProfile,
                            child: _isSaving
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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

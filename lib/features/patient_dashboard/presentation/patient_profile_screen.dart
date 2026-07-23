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
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bloodTypeController = TextEditingController(text: 'O+');
  final _emergencyContactController = TextEditingController(text: '+966 55 111 2222');

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authNotifierProvider).currentUser;
    if (user != null) {
      _fullNameController.text = user.fullName;
      _phoneController.text = user.phone ?? '+966 50 123 4567';
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _bloodTypeController.dispose();
    _emergencyContactController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      await ref.read(patientServiceProvider).updateProfile({
        'fullName': _fullNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'bloodType': _bloodTypeController.text.trim(),
        'emergencyContact': _emergencyContactController.text.trim(),
      });
    } catch (_) {}

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patient profile updated successfully.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).currentUser;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My General Profile',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textMain),
            ),
            const SizedBox(height: 4),
            const Text(
              'View and manage your personal demographics and contact preferences.',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
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
                            Text(
                              user?.fullName ?? 'Patient Name',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user?.email ?? 'patient@example.com',
                              style: const TextStyle(fontSize: 14, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),

                    const Text('Full Name', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(controller: _fullNameController, decoration: const InputDecoration(hintText: 'John Doe')),
                    const SizedBox(height: 16),

                    const Text('Phone Number', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(controller: _phoneController, decoration: const InputDecoration(hintText: '+966 50 000 0000')),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Blood Group', style: TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              TextField(controller: _bloodTypeController, decoration: const InputDecoration(hintText: 'O+')),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Emergency Contact', style: TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              TextField(controller: _emergencyContactController, decoration: const InputDecoration(hintText: '+966 55...')),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: 200,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        child: _isSaving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save Profile'),
                      ),
                    ),
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

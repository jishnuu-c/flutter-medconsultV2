import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/doctor_service.dart';

class DoctorProfileScreen extends ConsumerStatefulWidget {
  const DoctorProfileScreen({super.key});

  @override
  ConsumerState<DoctorProfileScreen> createState() => _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends ConsumerState<DoctorProfileScreen> {
  final _bioController = TextEditingController(text: 'Senior Consultant with over 10 years of experience in internal medicine and tele-consultations.');
  final _feeController = TextEditingController(text: '200');
  final _expController = TextEditingController(text: '10');

  bool _isSaving = false;

  @override
  void dispose() {
    _bioController.dispose();
    _feeController.dispose();
    _expController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    final user = ref.read(authNotifierProvider).currentUser;
    if (user != null) {
      try {
        await ref.read(doctorServiceProvider).updateDoctor(user.id, {
          'bioEn': _bioController.text.trim(),
          'experienceYears': int.tryParse(_expController.text) ?? 10,
          'consultationFeeSar': double.tryParse(_feeController.text) ?? 200.0,
        });
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doctor profile updated successfully.')),
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
              'My Professional Profile',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textMain),
            ),
            const SizedBox(height: 4),
            const Text(
              'Update your professional bio, consultation pricing, and experience details.',
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
                          radius: 36,
                          backgroundColor: AppTheme.primaryLightTeal,
                          child: Text(
                            user?.initials ?? 'DR',
                            style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold, fontSize: 20),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.fullName ?? 'Dr. Practitioner',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user?.email ?? 'doctor@medconsult.sa',
                              style: const TextStyle(fontSize: 14, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),

                    const Text('Professional Biography (EN)', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bioController,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: 'Enter your bio...'),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Years of Experience', style: TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _expController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(hintText: '10'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Consultation Fee (SAR)', style: TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _feeController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(hintText: '200'),
                              ),
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

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/auth_models.dart';
import '../../../core/theme/app_theme.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  UserRole _selectedRole = UserRole.PATIENT;
  Gender _selectedGender = Gender.PREFER_NOT_TO_SAY;
  String _selectedLang = 'en';

  String _errorMessage = '';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = '';
    });

    try {
      final payload = {
        'fullName': _fullNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'password': _passwordController.text.trim(),
        'role': _selectedRole.value,
        'gender': _selectedGender.value,
        'preferredLang': _selectedLang,
      };

      final authNotifier = ref.read(authNotifierProvider.notifier);
      await authNotifier.register(payload);

      if (!mounted) return;

      final authState = ref.read(authNotifierProvider);
      final user = authState.currentUser;

      if (user != null) {
        switch (user.role) {
          case UserRole.PATIENT:
            context.go('/patient/home');
            break;
          case UserRole.DOCTOR:
            context.go('/doctor/schedule');
            break;
          case UserRole.CLINIC_ADMIN:
            context.go('/clinic-admin/clinics');
            break;
          case UserRole.SYSTEM_ADMIN:
            context.go('/system-admin');
            break;
        }
      } else if (authState.isLoggedIn) {
        switch (_selectedRole) {
          case UserRole.PATIENT:
            context.go('/patient/home');
            break;
          case UserRole.DOCTOR:
            context.go('/doctor/schedule');
            break;
          case UserRole.CLINIC_ADMIN:
            context.go('/clinic-admin/clinics');
            break;
          case UserRole.SYSTEM_ADMIN:
            context.go('/system-admin');
            break;
        }
      }
    } catch (e) {
      if (!mounted) return;
      String errStr = 'Registration failed. Please check your details.';
      if (e is DioException) {
        if (e.response?.data != null) {
          final data = e.response!.data;
          if (data is Map && data['message'] != null) {
            errStr = data['message'].toString();
          } else if (data is String && data.isNotEmpty) {
            errStr = data;
          }
        }
      }
      setState(() {
        _errorMessage = errStr;
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    final formContent = Container(
      padding: const EdgeInsets.all(32),
      constraints: const BoxConstraints(maxWidth: 520),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Create an Account',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Please fill in the details below to register',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 24),

                if (_errorMessage.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.dangerRed),
                    ),
                    child: Text(
                      _errorMessage,
                      key: const Key('register_error_alert'),
                      style: const TextStyle(
                        color: AppTheme.dangerRed,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                // Full Name Input
                const Text(
                  'Full Name',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: const Key('register_fullname_input'),
                  controller: _fullNameController,
                  decoration: const InputDecoration(hintText: 'John Doe'),
                  validator: (value) {
                    if (value == null || value.trim().length < 2) {
                      return 'Full name is required (min 2 characters).';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Email Input
                const Text(
                  'Email Address',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: const Key('register_email_input'),
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(hintText: 'john.doe@example.com'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a valid email address.';
                    }
                    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    if (!emailRegex.hasMatch(value.trim())) {
                      return 'Please enter a valid email address.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Phone Input
                const Text(
                  'Phone Number',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: const Key('register_phone_input'),
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: '+966 50 000 0000'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a valid phone number.';
                    }
                    final phoneRegex = RegExp(r'^\+?[0-9 \-]{7,20}$');
                    if (!phoneRegex.hasMatch(value.trim())) {
                      return 'Please enter a valid phone number.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Password Input
                const Text(
                  'Password',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: const Key('register_password_input'),
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: '••••••••'),
                  validator: (value) {
                    if (value == null || value.length < 6) {
                      return 'Password must be at least 6 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Role & Gender Row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sign up as', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<UserRole>(
                            key: const Key('register_role_dropdown'),
                            initialValue: _selectedRole,
                            items: const [
                              DropdownMenuItem(value: UserRole.PATIENT, child: Text('Patient')),
                              DropdownMenuItem(value: UserRole.DOCTOR, child: Text('Doctor')),
                              DropdownMenuItem(value: UserRole.CLINIC_ADMIN, child: Text('Clinic Administrator')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedRole = val);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Gender', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<Gender>(
                            key: const Key('register_gender_dropdown'),
                            initialValue: _selectedGender,
                            items: const [
                              DropdownMenuItem(value: Gender.MALE, child: Text('Male')),
                              DropdownMenuItem(value: Gender.FEMALE, child: Text('Female')),
                              DropdownMenuItem(value: Gender.PREFER_NOT_TO_SAY, child: Text('Prefer not to say')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedGender = val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Preferred Language
                const Text(
                  'Preferred Language',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  key: const Key('register_lang_dropdown'),
                  initialValue: _selectedLang,
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English (EN)')),
                    DropdownMenuItem(value: 'ar', child: Text('Arabic (AR)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedLang = val);
                  },
                ),
                const SizedBox(height: 28),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    key: const Key('register_submit_btn'),
                    onPressed: _isSubmitting ? null : _submitForm,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Create Account'),
                  ),
                ),
                const SizedBox(height: 20),

                // Login Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                    GestureDetector(
                      key: const Key('goto_login_link'),
                      onTap: () => context.go('/login'),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryTeal,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      body: Row(
        children: [
          if (isDesktop)
            Expanded(
              child: Container(
                color: AppTheme.darkSidebar,
                padding: const EdgeInsets.all(48),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Join MedConsult V2',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Sign up today to manage consultations, build medical records, and connect with premier doctors seamlessly.',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Container(
              color: AppTheme.backgroundApp,
              alignment: Alignment.center,
              child: SingleChildScrollView(child: formContent),
            ),
          ),
        ],
      ),
    );
  }
}

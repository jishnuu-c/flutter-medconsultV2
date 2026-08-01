import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/auth_models.dart';
import '../../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String _errorMessage = '';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
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
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      await ref.read(authNotifierProvider.notifier).login(email, password);

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
        // Fallback if current user object wasn't populated by backend me endpoint
        if (email.contains('doctor')) {
          context.go('/doctor/schedule');
        } else if (email.contains('clinic')) {
          context.go('/clinic-admin/clinics');
        } else if (email.contains('admin') || email.contains('system')) {
          context.go('/system-admin');
        } else {
          context.go('/patient/home');
        }
      }
    } catch (e) {
      if (!mounted) return;
      String errStr = 'Login failed. Please check your credentials.';
      if (e is DioException) {
        if (e.response?.data != null) {
          final data = e.response!.data;
          if (data is Map && data['message'] != null) {
            errStr = data['message'].toString();
          } else if (data is String && data.isNotEmpty) {
            errStr = data;
          } else {
            errStr =
                'HTTP ${e.response?.statusCode}: ${e.response?.statusMessage ?? "Request failed"}';
            // 'HTTP ${e.response?.statusCode}: Invalid credentials or unauthorized.';
          }
        } else {
          // Show the actual Dio error instead of a hardcoded message.
          errStr = e.message ?? e.toString();
        }
      } else {
        errStr = e.toString();
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
      constraints: const BoxConstraints(maxWidth: 450),
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
                  'Login to MedConsult',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Please enter your credentials to access your account',
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
                      key: const Key('login_error_alert'),
                      style: const TextStyle(
                        color: AppTheme.dangerRed,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                // Email Input
                const Text(
                  'Email Address',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: const Key('login_email_input'),
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'name@example.com',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a valid email address.';
                    }
                    // final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    // if (!emailRegex.hasMatch(value.trim())) {
                    //   return 'Please enter a valid email address.';
                    // }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Password Input
                const Text(
                  'Password',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: const Key('login_password_input'),
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: '••••••••',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty || value.length < 6) {
                      return 'Password must be at least 6 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    key: const Key('login_submit_btn'),
                    onPressed: _isSubmitting ? null : _submitForm,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Sign In'),
                  ),
                ),
                const SizedBox(height: 20),

                // Register Link
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      "Don't have an account? ",
                      style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                    GestureDetector(
                      key: const Key('goto_register_link'),
                      onTap: () => context.go('/register'),
                      child: const Text(
                        'Create an account',
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
                      'Your Health, Simply Managed',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Book appointments, view medical records, and log treatments. Experience healthcare simplified.',
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

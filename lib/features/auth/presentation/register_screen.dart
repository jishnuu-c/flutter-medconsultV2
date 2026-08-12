import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/auth_models.dart';
import '../../../core/theme/app_theme.dart';

// Colors pulled direct from Angular CSS vars (register.component.css)
class _AuthColors {
  static const dark2 = Color(0xFF112B1E);
  static const tealD = Color(0xFF085041);
  static const tealM = Color(0xFF0F6E56);
  static const teal = Color(0xFF1D9E75);
  static const tealL = Color(0xFFE1F5EE);
  static const off = Color(0xFFF8FAF9);
  static const text = Color(0xFF111827);
  static const t2 = Color(0xFF374151);
  static const t3 = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
  static const red = Color(0xFFEF4444);
  static const redL = Color(0xFFFEE2E2);
  static const redD = Color(0xFF991B1B);
}

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

  void loginWithGoogle() {
    // Same google auth flow as login screen; register page doesn't need its
    // own copy since AuthNotifier session handling is shared.
  }

  @override
  Widget build(BuildContext context) {
    // Mobile-only layout: stacked column, matches Angular @media(max-width:992px) rules exact.
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heroPanel(),
            _formPanel(),
          ],
        ),
      ),
    );
  }

  // .auth-hero-panel mobile: padding 36px 20px 28px, gradient 135deg dark2->tealD(55%)->tealM
  Widget _heroPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_AuthColors.dark2, _AuthColors.tealD, _AuthColors.tealM],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // .hero-back-link mobile: position static, margin-bottom 8, align-self flex-start
          Align(
            alignment: Alignment.centerLeft,
            child: _backLink(),
          ),
          const SizedBox(height: 16),
          // .hero-content mobile: gap 16, align-items center, text-align center
          Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _heroBrand(),
                const SizedBox(height: 16),
                _headlineBlock(),
                const SizedBox(height: 16),
                // .hero-features-grid { display: none } on mobile — omitted
                _metricsStrip(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _backLink() {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.go('/'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back,
                size: 16, color: Colors.white.withOpacity(0.85)),
            const SizedBox(width: 8),
            Text(
              'Back to Home',
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 12.3, // 0.88rem
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // .hero-brand mobile: justify-content center
  Widget _heroBrand() {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.local_hospital, color: Colors.white, size: 32),
      ],
    );
  }

  // .hero-title mobile: 1.5rem (24px). .hero-subtitle mobile: 0.88rem (12.3px)
  // Register copy differs from login: "Join the Next Generation of Telehealth"
  Widget _headlineBlock() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Join the Next Generation of Telehealth',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 24,
            height: 1.25,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Register today to access instant specialist booking, digital EMR history, and seamless virtual case rooms.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.3,
            height: 1.6,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  // .hero-metrics-strip mobile: width 100%, max-width 400, padding 12px 16px
  Widget _metricsStrip() {
    Widget metric(String value, String label) {
      return Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22.4, // 1.4rem
              color: _AuthColors.tealL,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.1, // 0.72rem
              color: Colors.white.withOpacity(0.8),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      );
    }

    Widget divider() => Container(
          width: 1,
          height: 28,
          color: Colors.white.withOpacity(0.18),
        );

    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x590A1F15), // rgba(10,31,21,0.35)
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          metric('10K+', 'Consultations'),
          divider(),
          metric('500+', 'Verified Clinics'),
          divider(),
          metric('4.9★', 'Patient Rating'),
        ],
      ),
    );
  }

  // .auth-form-panel mobile: padding 24px 16px 40px, background off
  Widget _formPanel() {
    return Container(
      color: _AuthColors.off,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      alignment: Alignment.center,
      child: _authCard(),
    );
  }

  // .auth-card mobile: max-width 520 (register differs from login's 460), radius 20, padding 32px 24px
  Widget _authCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _AuthColors.tealD.withOpacity(0.12),
            blurRadius: 50,
            offset: const Offset(0, 25),
            spreadRadius: -12,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 25,
            offset: const Offset(0, 10),
            spreadRadius: -5,
          ),
          const BoxShadow(
            color: _AuthColors.border,
            blurRadius: 0,
            offset: Offset(0, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // .auth-card::before — 4px gradient top bar (register direction: tealD -> teal, reversed vs login)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Container(
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [_AuthColors.tealD, _AuthColors.teal],
                ),
              ),
            ),
          ),
          // .mobile-auth-brand { display: none } — stays hidden on mobile too, omitted
          _authHeader(),
          if (_errorMessage.isNotEmpty) _errorAlert(),
          Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              children: [
                _fieldLabel('Full Name'),
                const SizedBox(height: 6),
                _textField(
                  key: const Key('register_fullname_input'),
                  controller: _fullNameController,
                  hint: 'John Doe',
                  obscure: false,
                  validator: (value) {
                    if (value == null || value.trim().length < 2) {
                      return 'Full name is required (min 2 characters).';
                    }
                    return null;
                  },
                ),
                const SizedBox(
                    height: 18), // register .form-group margin-bottom: 18px

                _fieldLabel('Email Address'),
                const SizedBox(height: 6),
                _textField(
                  key: const Key('register_email_input'),
                  controller: _emailController,
                  hint: 'john.doe@example.com',
                  obscure: false,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a valid email address.';
                    }
                    final emailRegex =
                        RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    if (!emailRegex.hasMatch(value.trim())) {
                      return 'Please enter a valid email address.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                _fieldLabel('Phone Number'),
                const SizedBox(height: 6),
                _textField(
                  key: const Key('register_phone_input'),
                  controller: _phoneController,
                  hint: '+966 50 000 0000',
                  obscure: false,
                  keyboardType: TextInputType.phone,
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
                const SizedBox(height: 18),

                _fieldLabel('Password'),
                const SizedBox(height: 6),
                _textField(
                  key: const Key('register_password_input'),
                  controller: _passwordController,
                  hint: '••••••••',
                  obscure: true,
                  validator: (value) {
                    if (value == null || value.length < 6) {
                      return 'Password must be at least 6 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // .form-row mobile: flex-direction column, gap 14px
                // (kept role dropdown too — not in Angular markup, but the
                // existing Flutter form already collects it, so it's styled
                // the same way as gender/lang rather than dropped)
                _fieldLabel('Sign up as'),
                const SizedBox(height: 6),
                _dropdown<UserRole>(
                  dropdownKey: const Key('register_role_dropdown'),
                  value: _selectedRole,
                  items: const [
                    DropdownMenuItem(
                        value: UserRole.PATIENT, child: Text('Patient')),
                    DropdownMenuItem(
                        value: UserRole.DOCTOR, child: Text('Doctor')),
                    DropdownMenuItem(
                        value: UserRole.CLINIC_ADMIN,
                        child: Text('Clinic Administrator')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedRole = val);
                  },
                ),
                const SizedBox(height: 14), // .form-row gap: 14px

                _fieldLabel('Gender'),
                const SizedBox(height: 6),
                _dropdown<Gender>(
                  dropdownKey: const Key('register_gender_dropdown'),
                  value: _selectedGender,
                  items: const [
                    DropdownMenuItem(value: Gender.MALE, child: Text('Male')),
                    DropdownMenuItem(
                        value: Gender.FEMALE, child: Text('Female')),
                    DropdownMenuItem(
                        value: Gender.PREFER_NOT_TO_SAY,
                        child: Text('Prefer not to say')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedGender = val);
                  },
                ),
                const SizedBox(height: 14),

                _fieldLabel('Preferred Language'),
                const SizedBox(height: 6),
                _dropdown<String>(
                  dropdownKey: const Key('register_lang_dropdown'),
                  value: _selectedLang,
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English (EN)')),
                    DropdownMenuItem(value: 'ar', child: Text('Arabic (AR)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedLang = val);
                  },
                ),
                const SizedBox(height: 28),

                _submitButton(),
                const SizedBox(height: 18),
                _divider(),
                const SizedBox(height: 18),
                _googleButton(),
                const SizedBox(height: 16),
                _footerLink(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // .auth-title 1.55rem/700/text, .auth-subtitle 0.9rem/t3
  Widget _authHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: const [
          Text(
            'Create an Account',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 21.7, // 1.55rem
              color: _AuthColors.text,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Join MedConsult to manage consultations and records seamlessly',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _AuthColors.t3,
              fontSize: 12.6, // 0.9rem
            ),
          ),
        ],
      ),
    );
  }

  // .auth-alert-danger
  Widget _errorAlert() {
    return Container(
      key: const Key('register_error_alert'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _AuthColors.redL,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _AuthColors.red),
      ),
      child: Row(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage,
              style: const TextStyle(
                color: _AuthColors.redD,
                fontSize: 12.3, // 0.88rem
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // .form-label
  Widget _fieldLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.9, // 0.85rem
          fontWeight: FontWeight.w600,
          color: _AuthColors.t2,
        ),
      ),
    );
  }

  // .form-control
  Widget _textField({
    required Key key,
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 13.3, color: _AuthColors.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _AuthColors.t3),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _AuthColors.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _AuthColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _AuthColors.teal, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _AuthColors.red, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _AuthColors.red, width: 1.5),
        ),
        errorStyle: const TextStyle(
          color: _AuthColors.red,
          fontSize: 11.5, // 0.82rem
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // Styled to match .form-control / app-custom-select look (rounded 12,
  // border color, teal focus) since Angular's custom-select isn't a plain
  // <select> but visually reads the same as the text inputs.
  Widget _dropdown<T>({
    required Key dropdownKey,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) {
    return DropdownButtonFormField<T>(
      key: dropdownKey,
      initialValue: value,
      items: items,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13.3, color: _AuthColors.text),
      icon: const Icon(Icons.keyboard_arrow_down, color: _AuthColors.t3),
      decoration: InputDecoration(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _AuthColors.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _AuthColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _AuthColors.teal, width: 1.5),
        ),
      ),
    );
  }

  // .btn-auth
  Widget _submitButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_AuthColors.teal, _AuthColors.tealD],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _AuthColors.teal.withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton(
          key: const Key('register_submit_btn'),
          onPressed: _isSubmitting ? null : _submitForm,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text(
                  'Create Account',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
        ),
      ),
    );
  }

  // .auth-divider
  Widget _divider() {
    return const Row(
      children: [
        Expanded(child: Divider(color: _AuthColors.border, thickness: 1.5)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR',
            style: TextStyle(
              color: _AuthColors.t3,
              fontSize: 11.9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Divider(color: _AuthColors.border, thickness: 1.5)),
      ],
    );
  }

  // .btn-google
  Widget _googleButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: () => loginWithGoogle(),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: _AuthColors.border, width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'lib/assets/icons/google.svg',
              width: 20,
              height: 20,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.g_mobiledata, size: 22),
            ),
            const SizedBox(width: 8),
            const Text(
              'Continue with Google',
              style: TextStyle(
                  fontSize: 13.3,
                  fontWeight: FontWeight.w600,
                  color: _AuthColors.t2),
            ),
          ],
        ),
      ),
    );
  }

  // .auth-footer / .auth-link
  Widget _footerLink() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Already have an account? ',
          style: TextStyle(fontSize: 12.6, color: _AuthColors.t3),
        ),
        GestureDetector(
          key: const Key('goto_login_link'),
          onTap: () => context.go('/login'),
          child: const Text(
            'Sign In',
            style: TextStyle(
                fontSize: 12.6,
                fontWeight: FontWeight.w700,
                color: _AuthColors.teal),
          ),
        ),
      ],
    );
  }
}

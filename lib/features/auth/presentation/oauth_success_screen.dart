import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/auth_models.dart';

// Flutter equivalent of Angular's oauth-success.component.ts.
// Backend redirects here (?token=...) after /oauth2/authorization/google
// completes. Same flow as AuthService.loginWithToken in Angular:
// saveSession(token) -> fetchCurrentUser() -> route by role.
class OauthSuccessScreen extends ConsumerStatefulWidget {
  final String? token;
  const OauthSuccessScreen({super.key, required this.token});

  @override
  ConsumerState<OauthSuccessScreen> createState() => _OauthSuccessScreenState();
}

class _OauthSuccessScreenState extends ConsumerState<OauthSuccessScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleToken());
  }

  Future<void> _handleToken() async {
    final token = widget.token;

    if (token == null || token.isEmpty) {
      setState(() => _error = 'Token not found in login callback.');
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) context.go('/login');
      });
      return;
    }

    try {
      final notifier = ref.read(authNotifierProvider.notifier);
      notifier.saveSession(token);
      await notifier.fetchCurrentUser();

      if (!mounted) return;

      final user = ref.read(authNotifierProvider).currentUser;
      if (user == null) {
        setState(() => _error = 'Authentication failed. Please try again.');
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) context.go('/login');
        });
        return;
      }

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
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Authentication failed. Please try again.');
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) context.go('/login');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error == null) const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_error ?? 'Signing you in...'),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/oauth_success_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/clinic_admin/presentation/clinic_dashboard_screen.dart';
import '../../features/clinic_admin/presentation/clinics_screen.dart';
import '../../features/clinic_admin/presentation/doctors_screen.dart';
import '../../features/doctor_dashboard/presentation/availability_screen.dart';
import '../../features/doctor_dashboard/presentation/caserooms_screen.dart';
import '../../features/doctor_dashboard/presentation/consultations_screen.dart';
import '../../features/doctor_dashboard/presentation/doctor_profile_screen.dart';
import '../../features/doctor_dashboard/presentation/doctor_patients_screen.dart';
import '../../features/doctor_dashboard/presentation/schedule_screen.dart';
import '../../features/landing/presentation/landing_screen.dart';
import '../../features/doctor_dashboard/presentation/appointments_history_screen.dart';
import '../../features/patient_dashboard/presentation/become_clinic_screen.dart';
import '../../features/patient_dashboard/presentation/become_doctor_screen.dart';
import '../../features/patient_dashboard/presentation/book_appointment_screen.dart';
import '../../features/patient_dashboard/presentation/patient_appointments_screen.dart';
import '../../features/patient_dashboard/presentation/patient_clinics_screen.dart';
import '../../features/patient_dashboard/presentation/clinic_detail_screen.dart';
import '../../features/patient_dashboard/presentation/patient_consultations_screen.dart';
import '../../features/patient_dashboard/presentation/patient_doctors_screen.dart';
import '../../features/patient_dashboard/presentation/patient_emr_screen.dart';
import '../../features/patient_dashboard/presentation/patient_health_profile_screen.dart';
import '../../features/patient_dashboard/presentation/patient_home_screen.dart';
import '../../features/patient_dashboard/presentation/patient_profile_screen.dart';
import '../../features/system_admin/presentation/system_admin_screen.dart';

import '../auth/auth_provider.dart';
import '../models/auth_models.dart';
import '../widgets/app_layout.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _RiverpodRefreshStream(ref),
    redirect: (BuildContext context, GoRouterState state) {
      final authState = ref.read(authNotifierProvider);

      if (!authState.isInitialized) {
        return null;
      }

      final isLoggedIn = authState.isLoggedIn;
      final location = state.uri.toString();
      final isAuthRoute = location == '/login' ||
          location.startsWith('/login?') ||
          location == '/register' ||
          location.startsWith('/register?');

      // 1. noAuthGuard logic for /login and /register
      if (isAuthRoute && isLoggedIn) {
        final user = authState.currentUser;
        // IMPORTANT: don't redirect until we actually know the role. Right
        // after login the token is set a beat before /users/me resolves and
        // currentUser is still null — redirecting on that null used to fall
        // into the `else` below and send EVERY role to /patient/home for a
        // split second, firing a patient-only API call (401) that force-
        // logged the user straight back out. Just stay put until it's known.
        if (user == null) {
          return null;
        }
        if (user.role == UserRole.PATIENT) {
          return '/patient/home';
        } else if (user.role == UserRole.DOCTOR) {
          return '/doctor/schedule';
        } else if (user.role == UserRole.CLINIC_ADMIN) {
          return '/clinic-admin/clinics';
        } else if (user.role == UserRole.SYSTEM_ADMIN) {
          return '/system-admin';
        } else {
          return '/patient/home';
        }
      }

      // 2. authGuard & roleGuard logic for protected section routes
      if (location.startsWith('/patient')) {
        if (!isLoggedIn)
          return '/login?returnUrl=${Uri.encodeComponent(location)}';
        if (authState.currentUser != null &&
            !authState.hasRole([UserRole.PATIENT])) return '/patient/home';
      }

      if (location.startsWith('/doctor')) {
        if (!isLoggedIn)
          return '/login?returnUrl=${Uri.encodeComponent(location)}';
        if (authState.currentUser != null &&
            !authState.hasRole([UserRole.DOCTOR])) return '/doctor/schedule';
      }

      if (location.startsWith('/clinic-admin')) {
        if (!isLoggedIn)
          return '/login?returnUrl=${Uri.encodeComponent(location)}';
        if (authState.currentUser != null &&
            !authState.hasRole([UserRole.CLINIC_ADMIN]))
          return '/clinic-admin/clinics';
      }

      if (location.startsWith('/system-admin')) {
        if (!isLoggedIn)
          return '/login?returnUrl=${Uri.encodeComponent(location)}';
        if (authState.currentUser != null &&
            !authState.hasRole([UserRole.SYSTEM_ADMIN])) return '/system-admin';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LandingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/oauth-success',
        builder: (context, state) => OauthSuccessScreen(
          token: state.uri.queryParameters['token'],
        ),
      ),

      // Protected Shell Routes with AppLayout
      ShellRoute(
        builder: (context, state, child) => AppLayout(child: child),
        routes: [
          // Patient Routes
          GoRoute(
            path: '/patient',
            redirect: (context, state) => '/patient/home',
          ),
          GoRoute(
            path: '/patient/home',
            builder: (context, state) => const PatientHomeScreen(),
          ),
          GoRoute(
            path: '/patient/doctors',
            builder: (context, state) => const PatientDoctorsScreen(),
          ),
          GoRoute(
            path: '/patient/clinics',
            builder: (context, state) => const PatientClinicsScreen(),
          ),
          GoRoute(
            path: '/patient/clinics/:id',
            builder: (context, state) => ClinicDetailScreen(
              clinicId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/patient/appointments',
            builder: (context, state) => const PatientAppointmentsScreen(),
          ),
          GoRoute(
            path: '/patient/profile',
            builder: (context, state) => const PatientProfileScreen(),
          ),
          GoRoute(
            path: '/patient/health-profile',
            builder: (context, state) => const PatientHealthProfileScreen(),
          ),
          GoRoute(
            path: '/patient/book-appointment',
            builder: (context, state) => const BookAppointmentScreen(),
          ),
          GoRoute(
            path: '/patient/emr',
            builder: (context, state) => const PatientEmrScreen(),
          ),
          GoRoute(
            path: '/patient/consultations',
            builder: (context, state) => const PatientConsultationsScreen(),
          ),
          GoRoute(
            path: '/patient/become-doctor',
            builder: (context, state) => const BecomeDoctorScreen(),
          ),
          GoRoute(
            path: '/patient/become-clinic',
            builder: (context, state) => const BecomeClinicScreen(),
          ),

          // Doctor Routes
          GoRoute(
            path: '/doctor',
            redirect: (context, state) => '/doctor/schedule',
          ),
          GoRoute(
            path: '/doctor/schedule',
            builder: (context, state) => const DoctorScheduleScreen(),
          ),
          GoRoute(
            path: '/doctor/profile',
            builder: (context, state) => const DoctorProfileScreen(),
          ),
          GoRoute(
            path: '/doctor/patients',
            builder: (context, state) => const DoctorPatientsScreen(),
          ),
          GoRoute(
            path: '/doctor/availability',
            builder: (context, state) => const DoctorAvailabilityScreen(),
          ),
          GoRoute(
            path: '/doctor/consultations',
            builder: (context, state) => const DoctorConsultationsScreen(),
          ),
          GoRoute(
            path: '/doctor/appointments-history',
            builder: (context, state) =>
                const DoctorAppointmentsHistoryScreen(),
          ),
          GoRoute(
            path: '/doctor/caserooms',
            builder: (context, state) => const DoctorCaseRoomsScreen(),
          ),

          // Clinic Admin Routes
          GoRoute(
            path: '/clinic-admin',
            redirect: (context, state) => '/clinic-admin/dashboard',
          ),
          GoRoute(
            path: '/clinic-admin/dashboard',
            builder: (context, state) => const ClinicDashboardScreen(),
          ),
          GoRoute(
            path: '/clinic-admin/clinics',
            builder: (context, state) => const ClinicsScreen(),
          ),
          GoRoute(
            path: '/clinic-admin/doctors',
            builder: (context, state) => const DoctorsScreen(),
          ),

          // System Admin Routes
          GoRoute(
            path: '/system-admin',
            builder: (context, state) => const SystemAdminScreen(),
          ),
        ],
      ),
    ],
  );
});

class _RiverpodRefreshStream extends ChangeNotifier {
  _RiverpodRefreshStream(Ref ref) {
    ref.listen<AuthState>(authNotifierProvider, (_, __) => notifyListeners());
  }
}

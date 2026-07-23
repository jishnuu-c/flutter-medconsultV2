import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medconsult_qa/core/auth/auth_provider.dart';
import 'package:medconsult_qa/core/models/auth_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthState & AuthNotifier Unit Tests', () {
    test('Initial AuthState is not logged in', () {
      final state = AuthState();
      expect(state.isLoggedIn, false);
      expect(state.currentUser, null);
      expect(state.token, null);
    });

    test('AuthState hasRole correctly evaluates user role', () {
      final patientUser = UserModel(
        id: '1',
        email: 'patient@test.com',
        fullName: 'Test Patient',
        role: UserRole.PATIENT,
      );

      final state = AuthState(token: 'valid_jwt_token', currentUser: patientUser);

      expect(state.isLoggedIn, true);
      expect(state.hasRole([UserRole.PATIENT]), true);
      expect(state.hasRole([UserRole.DOCTOR]), false);
      expect(state.hasRole([UserRole.CLINIC_ADMIN, UserRole.SYSTEM_ADMIN]), false);
    });

    test('AuthNotifier logout resets state', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = AuthNotifier(prefs: prefs);
      notifier.saveSession('test_token');
      expect(notifier.state.isLoggedIn, true);

      await notifier.logout();
      expect(notifier.state.isLoggedIn, false);
      expect(notifier.state.currentUser, null);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medconsult_qa/core/auth/auth_service.dart';
import 'package:medconsult_qa/core/models/auth_models.dart';
import 'package:medconsult_qa/features/auth/presentation/login_screen.dart';

class MockAuthService implements AuthService {
  bool loginCalled = false;
  String? passedEmail;
  String? passedPassword;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<AuthResponseDto> login(Map<String, dynamic> credentials) async {
    loginCalled = true;
    passedEmail = credentials['email'];
    passedPassword = credentials['password'];
    return AuthResponseDto(
      token: 'mock_jwt_token_123',
      user: UserModel(
        id: 'user-1',
        email: credentials['email'],
        fullName: 'Test Patient',
        role: UserRole.PATIENT,
      ),
    );
  }

  @override
  Future<UserModel> fetchCurrentUser() async {
    return UserModel(
      id: 'user-1',
      email: passedEmail ?? 'test@example.com',
      fullName: 'Test Patient',
      role: UserRole.PATIENT,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LoginScreen Widget Tests (QA Verification)', () {
    testWidgets('Verify field presence on LoginScreen', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check fields presence
      expect(find.byKey(const Key('login_email_input')), findsOneWidget);
      expect(find.byKey(const Key('login_password_input')), findsOneWidget);
      expect(find.byKey(const Key('login_submit_btn')), findsOneWidget);
      expect(find.text('Login to MedConsult'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('Verify validation error triggers on invalid form submission', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Sign In button without entering data
      await tester.tap(find.byKey(const Key('login_submit_btn')));
      await tester.pumpAndSettle();

      // Verify validation error messages
      expect(find.text('Please enter a valid email address.'), findsOneWidget);
      expect(find.text('Password must be at least 6 characters.'), findsOneWidget);
    });

    testWidgets('Verify mocked login call trigger on valid input', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockAuthService = MockAuthService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(mockAuthService),
          ],
          child: const MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter valid email and password
      await tester.enterText(find.byKey(const Key('login_email_input')), 'patient@example.com');
      await tester.enterText(find.byKey(const Key('login_password_input')), 'password123');
      await tester.pump();

      // Tap Sign In button
      await tester.tap(find.byKey(const Key('login_submit_btn')));
      await tester.pump();

      // Check mock service called
      expect(mockAuthService.loginCalled, true);
      expect(mockAuthService.passedEmail, 'patient@example.com');
      expect(mockAuthService.passedPassword, 'password123');
    });
  });
}

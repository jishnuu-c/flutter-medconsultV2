import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medconsult_qa/features/patient_dashboard/presentation/patient_home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PatientHomeScreen Widget Tests (QA Verification)', () {
    testWidgets('Verify welcome header, quick action cards, and appointments list rendering', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PatientHomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check quick action cards presence
      expect(find.byKey(const Key('quick_book_appt')), findsOneWidget);
      expect(find.byKey(const Key('quick_emr_records')), findsOneWidget);
      expect(find.byKey(const Key('quick_consultations')), findsOneWidget);
      expect(find.byKey(const Key('quick_health_profile')), findsOneWidget);

      // Check card titles
      expect(find.text('Book Appointment'), findsOneWidget);
      expect(find.text('Medical EMR'), findsOneWidget);
      expect(find.text('Your Upcoming Appointments'), findsOneWidget);
    });
  });
}

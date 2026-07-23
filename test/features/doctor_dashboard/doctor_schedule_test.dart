import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medconsult_qa/features/doctor_dashboard/presentation/schedule_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DoctorScheduleScreen Widget Tests (QA Verification)', () {
    testWidgets('Verify title, refresh button, and schedule cards rendering', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DoctorScheduleScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check title and button presence
      expect(find.text('Consultation Schedule'), findsOneWidget);
      expect(find.byKey(const Key('refresh_schedule_btn')), findsOneWidget);
      expect(find.text('Refresh Schedule'), findsOneWidget);

      // Check appointment cards presence
      expect(find.text('Sarah Ahmed'), findsOneWidget);
      expect(find.text('Mohammed Al-Harbi'), findsOneWidget);
    });
  });
}

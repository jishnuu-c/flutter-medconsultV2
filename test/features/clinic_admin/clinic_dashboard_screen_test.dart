import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medconsult_qa/features/clinic_admin/presentation/clinic_dashboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ClinicDashboardScreen QA Tests', () {
    testWidgets('Verify executive header, KPI metrics, queue and shortcuts render',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ClinicDashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header subtitle
      expect(
        find.text(
            'Real-time daily operations, appointment queues, doctor roster, and patient satisfaction'),
        findsOneWidget,
      );

      // Check KPI card titles
      expect(find.text("TODAY'S CONSULTATIONS"), findsOneWidget);
      expect(find.text('ASSIGNED DOCTORS'), findsOneWidget);
      expect(find.text('OPERATIONAL BRANCHES'), findsOneWidget);
      expect(find.text('PATIENT SATISFACTION'), findsOneWidget);

      // Check Queue section
      expect(find.text('Live Consultations & Appointments Queue'), findsOneWidget);
      expect(find.textContaining('Active'), findsWidgets);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);

      // Check Shortcuts
      expect(find.text('Facility Operations Shortcuts'), findsOneWidget);
      expect(find.text('Branch Locations'), findsOneWidget);
      expect(find.text('Doctor Placements'), findsWidgets);

      // Check Right Column sections
      expect(find.text('Doctor Roster'), findsOneWidget);
      expect(find.text('Patient Feedback'), findsOneWidget);
      expect(find.text('Cleanliness'), findsOneWidget);
      expect(find.text('Staff Courtesy'), findsOneWidget);
      expect(find.text('Wait Time'), findsOneWidget);
    });
  });
}

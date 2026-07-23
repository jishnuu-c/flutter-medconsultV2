import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medconsult_qa/features/clinic_admin/presentation/clinics_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ClinicsScreen Widget Tests (QA Verification)', () {
    testWidgets('Verify header title, button, and table rendering', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ClinicsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header and add button presence
      expect(find.text('Clinics Management'), findsOneWidget);
      expect(find.byKey(const Key('add_clinic_btn')), findsOneWidget);
      expect(find.text('Add New Clinic'), findsOneWidget);

      // Check data table column headers
      expect(find.text('Clinic Name'), findsOneWidget);
      expect(find.text('MOH License'), findsOneWidget);
      expect(find.text('Primary Phone'), findsOneWidget);
    });

    testWidgets('Verify Add New Clinic button opens dialog modal', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ClinicsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Add New Clinic button
      await tester.tap(find.byKey(const Key('add_clinic_btn')));
      await tester.pumpAndSettle();

      // Assert dialog title and fields appear
      expect(find.text('Add New Clinic'), findsWidgets);
      expect(find.text('Clinic Name (EN)'), findsOneWidget);
      expect(find.text('Clinic Name (AR)'), findsOneWidget);
      expect(find.text('MOH License Number'), findsOneWidget);
    });
  });
}

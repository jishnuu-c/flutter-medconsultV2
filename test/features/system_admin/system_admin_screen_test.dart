import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medconsult_qa/features/clinic_admin/data/doctor_models.dart';
import 'package:medconsult_qa/features/system_admin/data/reference_models.dart';
import 'package:medconsult_qa/features/system_admin/presentation/system_admin_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SystemAdminScreen QA Tests', () {
    testWidgets('Verify KPI Summary Cards, Tab Navigation, and Header Toolbar',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SystemAdminScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check KPI Card labels
      expect(find.text('REGISTERED PATIENTS'), findsOneWidget);
      expect(find.text('CLINIC FACILITIES'), findsOneWidget);
      expect(find.text('VERIFIED DOCTORS'), findsOneWidget);
      expect(find.text('MONTHLY VOLUME (SAR)'), findsOneWidget);

      // Check Title and Header Toolbar
      expect(find.text('Platform Reference Registries'), findsOneWidget);
      expect(find.text('+ Add Entry'), findsOneWidget);

      // Check Tabs
      expect(find.text('🇸🇦 Cities & Regions'), findsOneWidget);
      expect(find.text('🩺 Medical Specialties'), findsOneWidget);
      expect(find.text('🗣️ Spoken Languages'), findsOneWidget);
      expect(find.text('🛡️ Insurance Panels'), findsOneWidget);
      expect(find.text('👨‍⚕️ Doctors Roster'), findsOneWidget);
    });

    testWidgets('Verify responsive rendering on mobile viewport without overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SystemAdminScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure no layout exceptions were thrown
      expect(tester.takeException(), isNull);

      // Check that mobile screen rendered correctly
      expect(find.text('REGISTERED PATIENTS'), findsOneWidget);
      expect(find.text('+ Add Entry'), findsOneWidget);
    });

    test('DoctorTitle enum includes CONSULTANT and SPECIALIST', () {
      expect(DoctorTitle.fromString('CONSULTANT'), DoctorTitle.CONSULTANT);
      expect(DoctorTitle.fromString('SPECIALIST'), DoctorTitle.SPECIALIST);
      expect(DoctorTitle.fromString('DR'), DoctorTitle.DR);
      expect(DoctorTitle.fromString('PROF'), DoctorTitle.PROF);
      expect(DoctorTitle.fromString('UNKNOWN'), DoctorTitle.DR);
    });

    test('Reference Models serialization and parsing', () {
      final cityJson = {
        'cityId': 'c-1',
        'nameEn': 'Riyadh',
        'nameAr': 'الرياض',
        'countryCode': 'SA',
        'sortOrder': 1,
        'isActive': true,
      };
      final city = CityModel.fromJson(cityJson);
      expect(city.nameEn, 'Riyadh');
      expect(city.nameAr, 'الرياض');
      expect(city.sortOrder, 1);

      final specJson = {
        'specialtyId': 's-1',
        'code': 'CARD',
        'nameEn': 'Cardiology',
        'nameAr': 'أمراض القلب',
        'category': 'MEDICAL',
        'isActive': true,
        'sortOrder': 1,
      };
      final spec = SpecialtyModel.fromJson(specJson);
      expect(spec.code, 'CARD');
      expect(spec.category, 'MEDICAL');

      final insJson = {
        'providerId': 'i-1',
        'nameEn': 'Bupa Arabia',
        'nameAr': 'بوبا العربية',
        'logoUrl': '/uploads/bupa.png',
        'isActive': true,
      };
      final ins = InsuranceProviderModel.fromJson(insJson);
      expect(ins.nameEn, 'Bupa Arabia');
      expect(ins.logoUrl, '/uploads/bupa.png');
    });
  });
}

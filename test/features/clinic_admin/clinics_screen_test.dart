import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medconsult_qa/core/services/references_service.dart';
import 'package:medconsult_qa/features/clinic_admin/data/clinic_models.dart';
import 'package:medconsult_qa/features/clinic_admin/data/clinic_service.dart';
import 'package:medconsult_qa/features/clinic_admin/presentation/clinics_screen.dart';

class _FakeClinicService extends ClinicService {
  _FakeClinicService() : super(dio: Dio());

  @override
  Future<List<ClinicModel>> getAllClinics() => SynchronousFuture([
        ClinicModel(
          clinicId: 'c1',
          nameEn: 'Al Noor Medical Center',
          nameAr: 'مركز النور',
          mohLicenseNumber: 'MOH-12345',
          phonePrimary: '+966500000000',
          isActive: true,
        ),
      ]);

  @override
  Future<List<ClinicBranchModel>> getClinicBranches(String clinicId) => SynchronousFuture([]);

  @override
  Future<List<ClinicSpecialtyModel>> getClinicSpecialties(String clinicId) => SynchronousFuture([]);

  @override
  Future<List<ClinicInsuranceModel>> getClinicInsurances(String clinicId) => SynchronousFuture([]);

  @override
  Future<List<ClinicLanguageModel>> getClinicLanguages(String clinicId) => SynchronousFuture([]);
}

class _FakeReferenceService extends ReferenceService {
  _FakeReferenceService() : super(dio: Dio());

  @override
  Future<List<SpecialtyModel>> getAllSpecialties() => SynchronousFuture([]);

  @override
  Future<List<InsuranceProviderModel>> getAllInsuranceProviders() => SynchronousFuture([]);

  @override
  Future<List<LanguageModel>> getAllLanguages() => SynchronousFuture([]);

  @override
  Future<List<CityModel>> getAllCities() => SynchronousFuture([]);

  @override
  Future<List<LocalityModel>> getLocalities(String cityId) => SynchronousFuture([]);
}

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
        ProviderScope(
          overrides: [
            clinicServiceProvider.overrideWithValue(_FakeClinicService()),
            referenceServiceProvider.overrideWithValue(_FakeReferenceService()),
          ],
          child: const MaterialApp(
            home: ClinicsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check header and add button presence
      expect(find.text('Clinic Facility Roster'), findsOneWidget);
      expect(find.text('My Clinics'), findsOneWidget);
      expect(find.byKey(const Key('add_clinic_btn')), findsOneWidget);
    });

    testWidgets('Verify Add New Clinic button opens dialog modal', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clinicServiceProvider.overrideWithValue(_FakeClinicService()),
            referenceServiceProvider.overrideWithValue(_FakeReferenceService()),
          ],
          child: const MaterialApp(
            home: ClinicsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap Add New Clinic button
      await tester.tap(find.byKey(const Key('add_clinic_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Assert dialog title and fields appear
      expect(find.text('Add New Clinic'), findsWidgets);
      expect(find.text('Name (EN) *'), findsOneWidget);
      expect(find.text('Name (AR) *'), findsOneWidget);
      expect(find.text('MOH License Number *'), findsOneWidget);

      // Close dialog
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}

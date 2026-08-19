import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medconsult_qa/features/clinic_admin/data/doctor_models.dart';
import 'package:medconsult_qa/features/clinic_admin/presentation/doctors_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DoctorsScreen QA Tests', () {
    testWidgets('Verify Doctor Roster placement banner, search bar and empty state',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: DoctorsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header title & subtitle
      expect(find.textContaining('Doctor Roster'), findsWidgets);
      expect(
        find.textContaining(
            'Manage doctor roster placements across facility branches'),
        findsWidgets,
      );

      // Check assign doctor button
      expect(find.text('Assign Doctor'), findsWidgets);

      // Check search bar
      expect(find.byType(TextField), findsWidgets);
    });

    test('DoctorLeaveModel fromJson & toJson handles leaves correctly', () {
      final json = {
        'leaveId': 'l-101',
        'dcId': 'dc-202',
        'leaveType': 'ANNUAL',
        'startDate': '2026-04-01',
        'endDate': '2026-04-10',
        'isApproved': true,
        'notes': 'Attending medical conference',
        'createdAt': '2026-03-15T10:00:00Z',
      };

      final model = DoctorLeaveModel.fromJson(json);
      expect(model.leaveId, 'l-101');
      expect(model.dcId, 'dc-202');
      expect(model.leaveType, LeaveType.ANNUAL);
      expect(model.startDate, '2026-04-01');
      expect(model.endDate, '2026-04-10');
      expect(model.isApproved, isTrue);
      expect(model.notes, 'Attending medical conference');
      expect(model.createdAt, '2026-03-15T10:00:00Z');

      final serialized = model.toJson();
      expect(serialized['dcId'], 'dc-202');
      expect(serialized['leaveType'], 'ANNUAL');
      expect(serialized['isApproved'], isTrue);
      expect(serialized['notes'], 'Attending medical conference');
    });

    test('DoctorDetailResponse fromJson handles profile data correctly', () {
      final json = {
        'doctorId': 'doc-1',
        'userId': 'u-1',
        'email': 'sarah@clinic.com',
        'fullName': 'Dr. Sarah Connor',
        'mohRegistrationNumber': 'MOH-1002',
        'mohVerified': true,
        'title': 'DR',
        'experienceYears': 8,
        'overallRating': 4.9,
        'reviewCount': 42,
        'consultationFeeSar': 180.0,
        'isActive': true,
        'specialties': [
          {'id': 's-1', 'doctorId': 'doc-1', 'specialtyId': 'Cardiology', 'isPrimary': true}
        ],
        'languages': [
          {'id': 'lang-1', 'doctorId': 'doc-1', 'languageId': 'Arabic', 'proficiency': 'NATIVE'}
        ],
        'qualifications': [
          {'qualId': 'q-1', 'doctorId': 'doc-1', 'degree': 'MBBS', 'institution': 'King Saud University', 'country': 'Saudi Arabia', 'yearObtained': 2018}
        ]
      };

      final profile = DoctorDetailResponse.fromJson(json);
      expect(profile.doctorId, 'doc-1');
      expect(profile.fullName, 'Dr. Sarah Connor');
      expect(profile.specialties.length, 1);
      expect(profile.specialties.first.specialtyId, 'Cardiology');
      expect(profile.languages.length, 1);
      expect(profile.languages.first.languageId, 'Arabic');
      expect(profile.qualifications.length, 1);
      expect(profile.qualifications.first.degree, 'MBBS');
    });
  });
}


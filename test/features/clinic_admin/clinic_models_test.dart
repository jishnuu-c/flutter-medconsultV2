import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:medconsult_qa/features/clinic_admin/data/clinic_models.dart';

void main() {
  test('ClinicModel parses all 4 real backend clinic records successfully', () {
    const rawJson = '''[
      {"clinicId":"06c964c7-98e7-4cc1-a16a-b341e2144cbc","createdAt":"2026-07-24T11:44:10.089683","descriptionAr":"","descriptionEn":"drgh","email":"bingo415263@gmail.com","isActive":true,"logoUrl":"uploads/clinic/clinicLogo/4aa8ab1c-bfd2-4a03-815f-930db9de2a3c_active.png","mohLicenseNumber":"MOG-fgn","mohVerified":false,"mohVerifiedAt":null,"nameAr":"Bingo","nameEn":"Bingo","naphiesFacilityId":null,"overallRating":0.00,"phonePrimary":"9823568525252","phoneSecondary":"","reviewCount":0,"updatedAt":"2026-08-04T16:23:49.37635","website":null},
      {"clinicId":"1b745b74-b3a6-4e2d-b2f5-dd86ca24c5fa","createdAt":"2026-07-24T16:08:47.99731","descriptionAr":"rthbrtbhrftg","descriptionEn":"6dfghtrfhtrhrtg","email":"bingo415263@gmail.comg","isActive":true,"logoUrl":"uploads/clinic/clinicLogo/d080c6a5-4fc1-41e5-bfd7-7bd9e2b9baaa_Screenshot from 2026-06-10 11-20-52.png","mohLicenseNumber":"Lic-jhm","mohVerified":false,"mohVerifiedAt":null,"nameAr":"regrg","nameEn":"AL amimi clinic","naphiesFacilityId":null,"overallRating":0.00,"phonePrimary":"520752385","phoneSecondary":"7527525","reviewCount":0,"updatedAt":"2026-07-24T16:08:47.997316","website":""},
      {"clinicId":"3f4a1e9e-fe1e-4b0e-86e8-ed5921af090c","createdAt":"2026-07-21T12:54:37.55908","descriptionAr":"","descriptionEn":"asdvdfgbrf","email":"bing@gmail.com","isActive":true,"logoUrl":"uploads/clinic/clinicLogo/0b3ac9f2-39c8-4ab1-a471-14c29ed5dc4f_lulu_logo.jpg","mohLicenseNumber":"3sdfv","mohVerified":false,"mohVerifiedAt":null,"nameAr":"Bingo","nameEn":"Bingo","naphiesFacilityId":null,"overallRating":0.00,"phonePrimary":"34t4wtt4","phoneSecondary":"","reviewCount":0,"updatedAt":"2026-07-22T17:15:22.753681","website":null},
      {"clinicId":"619c2d32-9e46-4be5-aec7-9f3988a47a6d","createdAt":"2026-07-21T12:32:50.58176","descriptionAr":null,"descriptionEn":"sfffffff","email":"ae@1","isActive":true,"logoUrl":"uploads/clinic/clinicLogo/0835a6a1-68b4-462a-be99-03f0096eadb7_NESTO_LOGO.jpg","mohLicenseNumber":"23","mohVerified":false,"mohVerifiedAt":null,"nameAr":"fsfffffff","nameEn":"sffffff","naphiesFacilityId":null,"overallRating":5.00,"phonePrimary":"123456789","phoneSecondary":null,"reviewCount":0,"updatedAt":"2026-07-30T16:04:42.272488","website":null}
    ]''';

    final List decoded = jsonDecode(rawJson);
    final clinics = decoded.map((e) => ClinicModel.fromJson(e as Map<String, dynamic>)).toList();

    expect(clinics.length, equals(4));
    expect(clinics[0].nameEn, equals('Bingo'));
    expect(clinics[0].mohLicenseNumber, equals('MOG-fgn'));
    expect(clinics[1].nameEn, equals('AL amimi clinic'));
    expect(clinics[1].mohLicenseNumber, equals('Lic-jhm'));
    expect(clinics[2].nameEn, equals('Bingo'));
    expect(clinics[2].mohLicenseNumber, equals('3sdfv'));
    expect(clinics[3].nameEn, equals('sffffff'));
    expect(clinics[3].mohLicenseNumber, equals('23'));
  });
}

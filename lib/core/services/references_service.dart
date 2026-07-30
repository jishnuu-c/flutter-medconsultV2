import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';

// Mirrors reference.model.ts response DTOs (read-only subset needed by
// clinic-admin lookup dropdowns: specialties, insurance providers, languages).

class SpecialtyModel {
  final String specialtyId;
  final String nameEn;
  final String nameAr;

  SpecialtyModel(
      {required this.specialtyId, required this.nameEn, required this.nameAr});

  factory SpecialtyModel.fromJson(Map<String, dynamic> json) {
    return SpecialtyModel(
      specialtyId: json['specialtyId']?.toString() ?? '',
      nameEn: json['nameEn']?.toString() ?? '',
      nameAr: json['nameAr']?.toString() ?? '',
    );
  }
}

class InsuranceProviderModel {
  final String providerId;
  final String nameEn;
  final String nameAr;

  InsuranceProviderModel(
      {required this.providerId, required this.nameEn, required this.nameAr});

  factory InsuranceProviderModel.fromJson(Map<String, dynamic> json) {
    return InsuranceProviderModel(
      providerId: json['providerId']?.toString() ?? '',
      nameEn: json['nameEn']?.toString() ?? '',
      nameAr: json['nameAr']?.toString() ?? '',
    );
  }
}

class LanguageModel {
  final String languageId;
  final String nameEn;
  final String nameAr;

  LanguageModel(
      {required this.languageId, required this.nameEn, required this.nameAr});

  factory LanguageModel.fromJson(Map<String, dynamic> json) {
    return LanguageModel(
      languageId: json['languageId']?.toString() ?? '',
      nameEn: json['nameEn']?.toString() ?? '',
      nameAr: json['nameAr']?.toString() ?? '',
    );
  }
}

class ReferenceService {
  final Dio dio;

  ReferenceService({required this.dio});

  // ── Specialties ─────────────────────────────────────────────────────
  Future<List<SpecialtyModel>> getAllSpecialties() async {
    final res = await dio.get('/api/medconsult/specialties/all');
    final List list = res.data ?? [];
    return list.map((e) => SpecialtyModel.fromJson(e)).toList();
  }

  // ── Insurance Providers ─────────────────────────────────────────────
  Future<List<InsuranceProviderModel>> getAllInsuranceProviders() async {
    final res = await dio.get('/api/medconsult/insurance-providers/all');
    final List list = res.data ?? [];
    return list.map((e) => InsuranceProviderModel.fromJson(e)).toList();
  }

  // ── Languages ───────────────────────────────────────────────────────
  Future<List<LanguageModel>> getAllLanguages() async {
    final res = await dio.get('/api/medconsult/languages/all');
    final List list = res.data ?? [];
    return list.map((e) => LanguageModel.fromJson(e)).toList();
  }
}

final referenceServiceProvider = Provider<ReferenceService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return ReferenceService(dio: dio);
});

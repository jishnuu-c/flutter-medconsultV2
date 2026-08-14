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

class CityModel {
  final String cityId;
  final String nameEn;
  final String nameAr;

  CityModel({required this.cityId, required this.nameEn, required this.nameAr});

  factory CityModel.fromJson(Map<String, dynamic> json) {
    return CityModel(
      cityId: json['cityId']?.toString() ?? '',
      nameEn: json['nameEn']?.toString() ?? '',
      nameAr: json['nameAr']?.toString() ?? '',
    );
  }
}

// Mirrors reference.model.ts's LocalityResponseDto. Localities cascade from
// a selected city (used by the branch-location form's city -> locality
// dropdowns, same as clinics.component.ts's onCityChange/onCitySelectChange).
class LocalityModel {
  final String localityId;
  final String cityId;
  final String nameEn;
  final String nameAr;

  LocalityModel({
    required this.localityId,
    required this.cityId,
    required this.nameEn,
    required this.nameAr,
  });

  factory LocalityModel.fromJson(Map<String, dynamic> json) {
    return LocalityModel(
      localityId: json['localityId']?.toString() ?? '',
      cityId: json['cityId']?.toString() ?? '',
      nameEn: json['nameEn']?.toString() ?? '',
      nameAr: json['nameAr']?.toString() ?? '',
    );
  }
}

class ReferenceService {
  final Dio dio;

  ReferenceService({required this.dio});

  // ── Cities ──────────────────────────────────────────────────────────
  Future<List<CityModel>> getAllCities() async {
    final res = await dio.get('/api/medconsult/cities/all');
    final List list = res.data ?? [];
    return list.map((e) => CityModel.fromJson(e)).toList();
  }

  // ── Localities ──────────────────────────────────────────────────────
  // Mirrors reference.service.ts's getLocalities(cityId).
  Future<List<LocalityModel>> getLocalities(String cityId) async {
    final res = await dio.get('/api/medconsult/cities/$cityId/localities');
    final List list = res.data ?? [];
    return list.map((e) => LocalityModel.fromJson(e)).toList();
  }

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

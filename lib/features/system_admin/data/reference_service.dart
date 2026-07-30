import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import 'reference_models.dart';

class ReferenceService {
  final Dio dio;

  ReferenceService({required this.dio});

  // ── Cities ──────────────────────────────────────────────────────────
  Future<List<CityModel>> getAllCities() async {
    final res = await dio.get('/api/medconsult/cities/all');
    final List list = res.data ?? [];
    return list.map((e) => CityModel.fromJson(e)).toList();
  }

  Future<CityModel> addCity(Map<String, dynamic> data) async {
    final res = await dio.post('/api/medconsult/cities/add', data: data);
    return CityModel.fromJson(res.data);
  }

  Future<CityModel> updateCity(String id, Map<String, dynamic> data) async {
    final res = await dio.patch('/api/medconsult/cities/$id/edit', data: data);
    return CityModel.fromJson(res.data);
  }

  Future<void> deleteCity(String id) async {
    await dio.delete('/api/medconsult/cities/$id/delete');
  }

  // ── Localities ──────────────────────────────────────────────────────
  Future<List<LocalityModel>> getLocalities(String cityId) async {
    final res = await dio.get('/api/medconsult/cities/$cityId/localities');
    final List list = res.data ?? [];
    return list.map((e) => LocalityModel.fromJson(e)).toList();
  }

  Future<LocalityModel> addLocality(Map<String, dynamic> data) async {
    final res =
        await dio.post('/api/medconsult/cities/locality/add', data: data);
    return LocalityModel.fromJson(res.data);
  }

  Future<LocalityModel> updateLocality(
      String id, Map<String, dynamic> data) async {
    final res =
        await dio.patch('/api/medconsult/cities/locality/$id/edit', data: data);
    return LocalityModel.fromJson(res.data);
  }

  Future<void> deleteLocality(String id) async {
    await dio.delete('/api/medconsult/cities/locality/$id/delete');
  }

  // ── Languages ───────────────────────────────────────────────────────
  Future<List<LanguageModel>> getAllLanguages() async {
    final res = await dio.get('/api/medconsult/languages/all');
    final List list = res.data ?? [];
    return list.map((e) => LanguageModel.fromJson(e)).toList();
  }

  Future<LanguageModel> addLanguage(Map<String, dynamic> data) async {
    final res = await dio.post('/api/medconsult/languages/add', data: data);
    return LanguageModel.fromJson(res.data);
  }

  Future<LanguageModel> updateLanguage(
      String id, Map<String, dynamic> data) async {
    final res =
        await dio.patch('/api/medconsult/languages/$id/edit', data: data);
    return LanguageModel.fromJson(res.data);
  }

  Future<void> deleteLanguage(String id) async {
    await dio.delete('/api/medconsult/languages/$id/delete');
  }

  // ── Specialties ─────────────────────────────────────────────────────
  Future<List<SpecialtyModel>> getAllSpecialties() async {
    final res = await dio.get('/api/medconsult/specialties/all');
    final List list = res.data ?? [];
    return list.map((e) => SpecialtyModel.fromJson(e)).toList();
  }

  Future<SpecialtyModel> addSpecialty(Map<String, dynamic> data) async {
    final res =
        await dio.post('/api/medconsult/specialties/add-specialty', data: data);
    return SpecialtyModel.fromJson(res.data);
  }

  Future<SpecialtyModel> updateSpecialty(
      String id, Map<String, dynamic> data) async {
    final res =
        await dio.patch('/api/medconsult/specialties/$id/edit', data: data);
    return SpecialtyModel.fromJson(res.data);
  }

  Future<void> deleteSpecialty(String id) async {
    await dio.delete('/api/medconsult/specialties/$id/delete');
  }

  // ── SubSpecialties ──────────────────────────────────────────────────
  Future<List<SubSpecialtyModel>> getSubSpecialties(String specialtyId) async {
    final res = await dio
        .get('/api/medconsult/specialties/$specialtyId/sub-specialities');
    final List list = res.data ?? [];
    return list.map((e) => SubSpecialtyModel.fromJson(e)).toList();
  }

  Future<SubSpecialtyModel> addSubSpecialty(Map<String, dynamic> data) async {
    final res =
        await dio.post('/api/medconsult/specialties/sub/add', data: data);
    return SubSpecialtyModel.fromJson(res.data);
  }

  Future<SubSpecialtyModel> updateSubSpecialty(
      String id, Map<String, dynamic> data) async {
    final res =
        await dio.patch('/api/medconsult/specialties/sub/$id/edit', data: data);
    return SubSpecialtyModel.fromJson(res.data);
  }

  Future<void> deleteSubSpecialty(String id) async {
    await dio.delete('/api/medconsult/specialties/sub/$id/delete');
  }

  // ── Insurance Providers ─────────────────────────────────────────────
  Future<List<InsuranceProviderModel>> getAllInsuranceProviders() async {
    final res = await dio.get('/api/medconsult/insurance-providers/all');
    final List list = res.data ?? [];
    return list.map((e) => InsuranceProviderModel.fromJson(e)).toList();
  }

  Future<InsuranceProviderModel> addInsuranceProvider(
      Map<String, dynamic> data) async {
    final res = await dio
        .post('/api/medconsult/insurance-providers/add-provider', data: data);
    return InsuranceProviderModel.fromJson(res.data);
  }

  Future<InsuranceProviderModel> updateInsuranceProvider(
      String id, Map<String, dynamic> data) async {
    final res = await dio.put('/api/medconsult/insurance-providers/$id/update',
        data: data);
    return InsuranceProviderModel.fromJson(res.data);
  }

  Future<void> deleteInsuranceProvider(String id) async {
    await dio.delete('/api/medconsult/insurance-providers/delete/$id');
  }
}

final referenceServiceProvider = Provider<ReferenceService>((ref) {
  final dio = ref.watch(apiClientProvider);
  return ReferenceService(dio: dio);
});

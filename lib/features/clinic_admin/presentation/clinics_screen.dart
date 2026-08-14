import 'dart:async';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/references_service.dart';
import '../data/clinic_models.dart';
import '../data/clinic_service.dart';

// Brand colors matching the web design in the screenshots
const Color _kPrimaryGreen = Color(0xFF059669);
const Color _kPrimaryLight = Color(0xFFE6F4EA);
const Color _kAmber = Color(0xFFD97706);
const Color _kDangerRed = Color(0xFFDC2626);
const Color _kDangerLight = Color(0xFFFEE2E2);
const Color _kBorderColor = Color(0xFFE2E8F0);
const Color _kOffWhite = Color(0xFFF8FAFC);
const Color _kTextMain = Color(0xFF0F172A);
const Color _kTextMuted = Color(0xFF64748B);
const Color _kDotPink = Color(0xFFE11D48);

RoundedRectangleBorder _dialogShape() =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

double _dialogMaxHeight(BuildContext context, {double preferred = 640}) {
  final screenHeight = MediaQuery.of(context).size.height;
  return math.min(preferred, screenHeight * 0.88);
}

double _dialogWidth(BuildContext context, {double preferred = 640}) {
  final screenWidth = MediaQuery.of(context).size.width;
  return math.min(preferred, screenWidth - 32);
}

class ClinicsScreen extends ConsumerStatefulWidget {
  const ClinicsScreen({super.key});

  @override
  ConsumerState<ClinicsScreen> createState() => _ClinicsScreenState();
}

class _ClinicsScreenState extends ConsumerState<ClinicsScreen> {
  int _activeSubTab = 0; // 0=branches, 1=specialties, 2=insurances, 3=languages

  bool _isLoading = false;
  bool _isDetailLoading = false;
  List<ClinicModel> _clinics = [];
  ClinicModel? _selectedClinic;
  String _searchTerm = '';

  List<ClinicModel> get _filteredClinics {
    if (_searchTerm.trim().isEmpty) return _clinics;
    final q = _searchTerm.trim().toLowerCase();
    return _clinics
        .where((c) =>
            c.nameEn.toLowerCase().contains(q) ||
            c.mohLicenseNumber.toLowerCase().contains(q))
        .toList();
  }

  // Sub-items for selected clinic
  List<ClinicBranchModel> _branches = [];
  List<ClinicSpecialtyModel> _specialties = [];
  List<ClinicInsuranceModel> _insurances = [];
  List<ClinicLanguageModel> _languages = [];

  // Global lookup lists
  List<SpecialtyModel> _globalSpecialties = [];
  List<InsuranceProviderModel> _globalInsurances = [];
  List<LanguageModel> _globalLanguages = [];
  List<CityModel> _globalCities = [];

  @override
  void initState() {
    super.initState();
    _loadClinics();
    _loadReferenceData();
  }

  Future<void> _loadReferenceData() async {
    try {
      final specialties =
          await ref.read(referenceServiceProvider).getAllSpecialties();
      if (mounted) setState(() => _globalSpecialties = specialties);
    } catch (e) {
      debugPrint('[ManageClinics] getAllSpecialties failed: $e');
    }
    try {
      final insurances =
          await ref.read(referenceServiceProvider).getAllInsuranceProviders();
      if (mounted) setState(() => _globalInsurances = insurances);
    } catch (e) {
      debugPrint('[ManageClinics] getAllInsuranceProviders failed: $e');
    }
    try {
      final languages =
          await ref.read(referenceServiceProvider).getAllLanguages();
      if (mounted) setState(() => _globalLanguages = languages);
    } catch (e) {
      debugPrint('[ManageClinics] getAllLanguages failed: $e');
    }
    try {
      final cities = await ref.read(referenceServiceProvider).getAllCities();
      if (mounted) setState(() => _globalCities = cities);
    } catch (e) {
      debugPrint('[ManageClinics] getAllCities failed: $e');
    }
  }

  String _getSpecialtyName(String specialtyId) {
    final match = _globalSpecialties.where((s) => s.specialtyId == specialtyId);
    return match.isEmpty ? 'Unknown Specialty' : match.first.nameEn;
  }

  String _getInsuranceName(String providerId) {
    final match = _globalInsurances.where((i) => i.providerId == providerId);
    return match.isEmpty ? 'Unknown Provider' : match.first.nameEn;
  }

  String _getLanguageName(String languageId) {
    final match = _globalLanguages.where((l) => l.languageId == languageId);
    return match.isEmpty ? 'Unknown Language' : match.first.nameEn;
  }

  Future<void> _loadClinics() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref.read(clinicServiceProvider).getAllClinics();
      setState(() => _clinics = res);
      if (res.isNotEmpty) {
        if (_selectedClinic == null ||
            !res.any((c) => c.clinicId == _selectedClinic!.clinicId)) {
          await _selectClinic(res.first);
        } else {
          final updated =
              res.firstWhere((c) => c.clinicId == _selectedClinic!.clinicId);
          await _selectClinic(updated);
        }
      } else {
        setState(() {
          _selectedClinic = null;
          _branches = [];
          _specialties = [];
          _insurances = [];
          _languages = [];
        });
      }
    } catch (e) {
      debugPrint('[ManageClinics] getAllClinics failed: $e');
      if (mounted) _showError('Failed to load clinics: $e', retry: _loadClinics);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectClinic(ClinicModel clinic) async {
    setState(() {
      _selectedClinic = clinic;
      _isDetailLoading = true;
    });

    final service = ref.read(clinicServiceProvider);

    try {
      final branches = await service.getClinicBranches(clinic.clinicId);
      if (mounted) setState(() => _branches = branches);
    } catch (e) {
      debugPrint('[ManageClinics] getClinicBranches failed: $e');
      if (mounted) setState(() => _branches = []);
    }

    try {
      final specialties = await service.getClinicSpecialties(clinic.clinicId);
      if (mounted) setState(() => _specialties = specialties);
    } catch (e) {
      debugPrint('[ManageClinics] getClinicSpecialties failed: $e');
      if (mounted) setState(() => _specialties = []);
    }

    try {
      final insurances = await service.getClinicInsurances(clinic.clinicId);
      if (mounted) setState(() => _insurances = insurances);
    } catch (e) {
      debugPrint('[ManageClinics] getClinicInsurances failed: $e');
      if (mounted) setState(() => _insurances = []);
    }

    try {
      final languages = await service.getClinicLanguages(clinic.clinicId);
      if (mounted) setState(() => _languages = languages);
    } catch (e) {
      debugPrint('[ManageClinics] getClinicLanguages failed: $e');
      if (mounted) setState(() => _languages = []);
    }

    if (mounted) setState(() => _isDetailLoading = false);
  }

  void _showError(String message, {VoidCallback? retry}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _kDangerRed,
        duration: const Duration(seconds: 4),
        action: retry != null
            ? SnackBarAction(label: 'Retry', textColor: Colors.white, onPressed: retry)
            : null,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _kPrimaryGreen,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<List<dynamic>> _searchBranchLocation(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final dio = Dio();
    final encoded = Uri.encodeComponent(q);
    Future<List<dynamic>> run(String url) async {
      final res = await dio.get(url,
          options: Options(headers: {'Accept-Language': 'en'}));
      return (res.data is List) ? res.data as List : [];
    }

    try {
      final primary = await run(
          'https://nominatim.openstreetmap.org/search?format=json&q=$encoded&limit=10&addressdetails=1&countrycodes=sa');
      if (primary.isNotEmpty) return primary;
      return await run(
          'https://nominatim.openstreetmap.org/search?format=json&q=$encoded&limit=10&addressdetails=1');
    } catch (e) {
      debugPrint('[ManageClinics] location search failed: $e');
      return [];
    }
  }

  // ── Dialogs ─────────────────────────────────────────────────────────────

  void _openClinicDialog(ClinicModel? clinic) {
    final isEdit = clinic != null;
    final nameEnController = TextEditingController(text: clinic?.nameEn ?? '');
    final nameArController = TextEditingController(text: clinic?.nameAr ?? '');
    final descEnController =
        TextEditingController(text: clinic?.descriptionEn ?? '');
    final emailController = TextEditingController(text: clinic?.email ?? '');
    final phoneController =
        TextEditingController(text: clinic?.phonePrimary ?? '');
    final mohController =
        TextEditingController(text: clinic?.mohLicenseNumber ?? '');
    final vatController = TextEditingController(text: clinic?.vatNumber ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: _dialogShape(),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isEdit ? 'Edit Clinic Facility' : 'Add New Clinic Facility',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kTextMain),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: _kTextMuted, size: 20),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SizedBox(
          width: _dialogWidth(ctx, preferred: 560),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: _dialogMaxHeight(ctx)),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameEnController,
                    decoration: const InputDecoration(
                      labelText: 'Clinic Name (EN) *',
                      hintText: 'e.g. City Health Clinic',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameArController,
                    decoration: const InputDecoration(
                      labelText: 'Clinic Name (AR) *',
                      hintText: 'e.g. مجمع صحة المدينة الطبي',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descEnController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Overview Description',
                      hintText: 'Brief summary of clinic services',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: mohController,
                          decoration: const InputDecoration(
                            labelText: 'MOH License *',
                            hintText: 'MOH-12345',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: vatController,
                          decoration: const InputDecoration(
                            labelText: 'VAT Number',
                            hintText: '300000000000003',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Primary Phone *',
                            hintText: '+966 11 123 4567',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email Address',
                            hintText: 'info@clinic.com',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final nameEn = nameEnController.text.trim();
              final nameAr = nameArController.text.trim();
              final phone = phoneController.text.trim();
              final moh = mohController.text.trim();
              if (nameEn.isEmpty || nameAr.isEmpty || phone.isEmpty || moh.isEmpty) {
                _showError('Please fill all required clinic fields (*).');
                return;
              }
              final payload = {
                'nameEn': nameEn,
                'nameAr': nameAr,
                'descriptionEn': descEnController.text.trim(),
                'descriptionAr': descEnController.text.trim(),
                'email': emailController.text.trim(),
                'phonePrimary': phone,
                'mohLicenseNumber': moh,
                'vatNumber': vatController.text.trim(),
                'isActive': true,
              };
              try {
                if (isEdit) {
                  await ref
                      .read(clinicServiceProvider)
                      .updateClinic(clinic.clinicId, payload);
                } else {
                  await ref.read(clinicServiceProvider).createClinic(payload);
                }
                if (mounted) Navigator.pop(ctx);
                if (mounted) {
                  _showSuccess(isEdit
                      ? 'Clinic profile updated successfully.'
                      : 'Clinic created successfully.');
                }
                _loadClinics();
              } catch (e) {
                if (mounted) {
                  _showError(isEdit
                      ? 'Failed to update clinic: $e'
                      : 'Failed to create clinic: $e');
                }
              }
            },
            child: Text(isEdit ? 'Save Changes' : 'Create Clinic'),
          ),
        ],
      ),
    );
  }

  void _openBranchDialog(ClinicBranchModel? branch) {
    if (_selectedClinic == null) return;
    final isEdit = branch != null;
    final nameEnController =
        TextEditingController(text: branch?.branchNameEn ?? '');
    final nameArController =
        TextEditingController(text: branch?.branchNameAr ?? '');
    final address1Controller =
        TextEditingController(text: branch?.addressLine1 ?? '');
    final address2Controller =
        TextEditingController(text: branch?.addressLine2 ?? '');
    final phoneController = TextEditingController(text: branch?.phone ?? '');
    final emailController = TextEditingController(text: branch?.email ?? '');
    final latController =
        TextEditingController(text: branch?.latitude?.toStringAsFixed(6) ?? '24.713600');
    final lngController = TextEditingController(
        text: branch?.longitude?.toStringAsFixed(6) ?? '46.675300');
    final searchController = TextEditingController();
    bool isPrimary = branch?.isPrimary ?? false;
    String? cityId = branch?.cityId.isNotEmpty == true ? branch!.cityId : null;
    String? localityId = branch?.localityId;
    List<LocalityModel> localities = [];
    bool localitiesHydratedForEdit = false;
    List<dynamic> searchResults = [];
    bool isSearching = false;
    String? searchError;
    Timer? debounce;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (isEdit && cityId != null && !localitiesHydratedForEdit) {
            localitiesHydratedForEdit = true;
            ref
                .read(referenceServiceProvider)
                .getLocalities(cityId!)
                .then((data) {
              if (ctx.mounted) setDialogState(() => localities = data);
            }).catchError((_) {});
          }

          Future<void> onCityChanged(String? newCityId) async {
            setDialogState(() {
              cityId = newCityId;
              localityId = null;
              localities = [];
            });
            if (newCityId == null) return;
            try {
              final data = await ref
                  .read(referenceServiceProvider)
                  .getLocalities(newCityId);
              setDialogState(() => localities = data);
            } catch (_) {
              setDialogState(() => localities = []);
            }
          }

          void onSearchChanged(String value) {
            debounce?.cancel();
            if (value.trim().length < 2) {
              setDialogState(() {
                searchResults = [];
                searchError = null;
                isSearching = false;
              });
              return;
            }
            debounce = Timer(const Duration(milliseconds: 350), () async {
              setDialogState(() => isSearching = true);
              final results = await _searchBranchLocation(value);
              if (!ctx.mounted) return;
              setDialogState(() {
                isSearching = false;
                searchResults = results;
                searchError = results.isEmpty
                    ? 'No locations found matching your query. Try searching by city or landmark name.'
                    : null;
              });
            });
          }

          void selectSearchResult(dynamic r) {
            final lat = double.tryParse(r['lat']?.toString() ?? '');
            final lon = double.tryParse(r['lon']?.toString() ?? '');
            setDialogState(() {
              if (lat != null) latController.text = lat.toStringAsFixed(6);
              if (lon != null) lngController.text = lon.toStringAsFixed(6);
              searchResults = [];
              searchController.text = r['display_name']?.toString() ?? '';
            });
          }

          void useCurrentLocation() {
            setDialogState(() {
              latController.text = '24.713600';
              lngController.text = '46.675300';
              searchController.text = 'Riyadh, Saudi Arabia';
            });
          }

          final screenWidth = MediaQuery.of(context).size.width;
          final isCompact = screenWidth < 680;

          return AlertDialog(
            shape: _dialogShape(),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    isEdit ? 'Edit Clinic Branch Location' : 'Add Clinic Branch Location',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _kTextMain,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: _kTextMuted, size: 20),
                  tooltip: 'Close',
                  onPressed: () {
                    debounce?.cancel();
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
            content: SizedBox(
              width: _dialogWidth(context, preferred: 760),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: _dialogMaxHeight(context, preferred: 800)),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Row 1: Branch Names
                      if (isCompact) ...[
                        _buildField(
                          label: 'Branch Name (EN) *',
                          controller: nameEnController,
                          hintText: 'e.g. Downtown Clinic',
                        ),
                        const SizedBox(height: 12),
                        _buildField(
                          label: 'Branch Name (AR) *',
                          controller: nameArController,
                          hintText: 'e.g. فرع وسط المدينة',
                        ),
                      ] else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildField(
                                label: 'Branch Name (EN) *',
                                controller: nameEnController,
                                hintText: 'e.g. Downtown Clinic',
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _buildField(
                                label: 'Branch Name (AR) *',
                                controller: nameArController,
                                hintText: 'e.g. فرع وسط المدينة',
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),

                      // Row 2: City & Locality
                      if (isCompact) ...[
                        _buildDropdownField<String>(
                          label: 'City *',
                          value: cityId,
                          items: _globalCities
                              .map((c) => DropdownMenuItem(value: c.cityId, child: Text(c.nameEn)))
                              .toList(),
                          onChanged: onCityChanged,
                        ),
                        const SizedBox(height: 12),
                        _buildDropdownField<String>(
                          label: 'Locality / District *',
                          value: localityId,
                          items: localities
                              .map((l) => DropdownMenuItem(value: l.localityId, child: Text(l.nameEn)))
                              .toList(),
                          onChanged: cityId == null ? null : (v) => setDialogState(() => localityId = v),
                        ),
                      ] else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildDropdownField<String>(
                                label: 'City *',
                                value: cityId,
                                items: _globalCities
                                    .map((c) => DropdownMenuItem(value: c.cityId, child: Text(c.nameEn)))
                                    .toList(),
                                onChanged: onCityChanged,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _buildDropdownField<String>(
                                label: 'Locality / District *',
                                value: localityId,
                                items: localities
                                    .map((l) => DropdownMenuItem(value: l.localityId, child: Text(l.nameEn)))
                                    .toList(),
                                onChanged: cityId == null ? null : (v) => setDialogState(() => localityId = v),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),

                      // Row 3: Address Line 1
                      _buildField(
                        label: 'Address Line 1 *',
                        controller: address1Controller,
                        hintText: 'Street name, building number, or district',
                      ),
                      const SizedBox(height: 14),

                      // Row 4: Address Line 2
                      _buildField(
                        label: 'Address Line 2',
                        controller: address2Controller,
                        hintText: 'Apartment, suite, or landmark (optional)',
                      ),
                      const SizedBox(height: 14),

                      // Row 5: Phone & Email
                      if (isCompact) ...[
                        _buildField(
                          label: 'Branch Phone',
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          hintText: '+966 11 123 4567',
                        ),
                        const SizedBox(height: 12),
                        _buildField(
                          label: 'Branch Email',
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          hintText: 'branch@clinic.com',
                        ),
                      ] else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildField(
                                label: 'Branch Phone',
                                controller: phoneController,
                                keyboardType: TextInputType.phone,
                                hintText: '+966 11 123 4567',
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _buildField(
                                label: 'Branch Email',
                                controller: emailController,
                                keyboardType: TextInputType.emailAddress,
                                hintText: 'branch@clinic.com',
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),

                      // ── Map Location Box (matches screenshots 2 & 3) ──
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _kOffWhite,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _kBorderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('📍', style: TextStyle(fontSize: 16)),
                                    SizedBox(width: 6),
                                    Text(
                                      'Branch Location on Map *',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: _kTextMain,
                                      ),
                                    ),
                                  ],
                                ),
                                OutlinedButton.icon(
                                  onPressed: useCurrentLocation,
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    minimumSize: Size.zero,
                                    side: const BorderSide(color: _kBorderColor),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.gps_fixed, size: 14, color: _kDangerRed),
                                  label: const Text(
                                    'Use My Current Location',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kTextMain),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('💡', style: TextStyle(fontSize: 13)),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Click anywhere on the map or drag the marker pin to pinpoint the exact branch location.',
                                    style: TextStyle(fontSize: 11, color: _kTextMuted),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Search bar with explicit Search button
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: searchController,
                                    decoration: InputDecoration(
                                      hintText: 'Search location on map (e.g., Al Olaya, Riyadh)...',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      prefixIcon: const Icon(Icons.search, size: 18, color: _kTextMuted),
                                      suffixIcon: isSearching
                                          ? const Padding(
                                              padding: EdgeInsets.all(10),
                                              child: SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(strokeWidth: 2)),
                                            )
                                          : null,
                                    ),
                                    onSubmitted: (v) => onSearchChanged(v),
                                    onChanged: onSearchChanged,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: _kPrimaryGreen,
                                    elevation: 0,
                                    side: const BorderSide(color: _kPrimaryGreen),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.search, size: 16),
                                  label: const Text('Search', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  onPressed: () => onSearchChanged(searchController.text),
                                ),
                              ],
                            ),
                            if (searchError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(searchError!,
                                    style: const TextStyle(fontSize: 11, color: _kDangerRed)),
                              ),
                            if (searchResults.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                constraints: const BoxConstraints(maxHeight: 160),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: _kBorderColor),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4)],
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: searchResults.length,
                                  itemBuilder: (context, i) {
                                    final r = searchResults[i];
                                    return ListTile(
                                      dense: true,
                                      leading: const Icon(Icons.place_outlined, size: 18, color: _kPrimaryGreen),
                                      title: Text(
                                        r['display_name']?.toString() ?? '',
                                        style: const TextStyle(fontSize: 12),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onTap: () => selectSearchResult(r),
                                    );
                                  },
                                ),
                              ),
                            const SizedBox(height: 12),

                            // Stylized Map Canvas Container
                            _InteractiveBranchMap(
                              lat: double.tryParse(latController.text) ?? 24.7136,
                              lng: double.tryParse(lngController.text) ?? 46.6753,
                              onLocationSelected: (newLat, newLng) {
                                setDialogState(() {
                                  latController.text = newLat.toStringAsFixed(6);
                                  lngController.text = newLng.toStringAsFixed(6);
                                });
                              },
                            ),

                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Latitude: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kTextMuted)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: _kBorderColor),
                                      ),
                                      child: Text(
                                        latController.text.isEmpty ? '0.000000' : latController.text,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: _kPrimaryGreen,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Longitude: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kTextMuted)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: _kBorderColor),
                                      ),
                                      child: Text(
                                        lngController.text.isEmpty ? '0.000000' : lngController.text,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: _kPrimaryGreen,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Primary checkbox
                      InkWell(
                        onTap: () => setDialogState(() => isPrimary = !isPrimary),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Checkbox(
                                value: isPrimary,
                                activeColor: _kPrimaryGreen,
                                onChanged: (val) => setDialogState(() => isPrimary = val ?? false),
                              ),
                              const Text(
                                'Set as Primary Branch',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _kTextMain),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () {
                  debounce?.cancel();
                  Navigator.pop(ctx);
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  side: const BorderSide(color: _kBorderColor),
                ),
                child: const Text('Cancel', style: TextStyle(color: _kTextMain, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: () async {
                  final lat = double.tryParse(latController.text.trim());
                  final lng = double.tryParse(lngController.text.trim());
                  final emailText = emailController.text.trim();
                  final emailValid = emailText.isEmpty ||
                      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(emailText);

                  if (nameEnController.text.trim().isEmpty ||
                      nameArController.text.trim().isEmpty ||
                      cityId == null ||
                      localityId == null ||
                      address1Controller.text.trim().isEmpty ||
                      lat == null ||
                      lat < -90 ||
                      lat > 90 ||
                      lng == null ||
                      lng < -180 ||
                      lng > 180 ||
                      !emailValid) {
                    _showError('Please fill all required branch fields with valid values.');
                    return;
                  }
                  final payload = {
                    'branchNameEn': nameEnController.text.trim(),
                    'branchNameAr': nameArController.text.trim(),
                    'cityId': cityId,
                    'localityId': localityId,
                    'addressLine1': address1Controller.text.trim(),
                    'addressLine2': address2Controller.text.trim(),
                    'latitude': lat,
                    'longitude': lng,
                    'phone': phoneController.text.trim(),
                    'email': emailText,
                    'isPrimary': isPrimary,
                    'isActive': true,
                  };
                  try {
                    if (isEdit) {
                      await ref
                          .read(clinicServiceProvider)
                          .updateClinicBranch(branch.branchId, payload);
                    } else {
                      await ref.read(clinicServiceProvider).createClinicBranch(
                          _selectedClinic!.clinicId, payload);
                    }
                    debounce?.cancel();
                    if (mounted) Navigator.pop(ctx);
                    if (mounted) {
                      _showSuccess(isEdit
                          ? 'Branch updated successfully.'
                          : 'Branch created successfully.');
                    }
                    _selectClinic(_selectedClinic!);
                  } catch (e) {
                    if (mounted) _showError('Failed to save branch: $e');
                  }
                },
                child: Text(isEdit ? 'Save Changes' : 'Save Branch', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _buildField({
    required String label,
    required TextEditingController controller,
    String? hintText,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kTextMain),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hintText,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  static Widget _buildDropdownField<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kTextMain),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<T>(
          initialValue: value,
          isDense: true,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          items: items,
          onChanged: onChanged,
        ),
      ],
    );
  }

  static const _dayNames = {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  };

  void _openHoursDialog(ClinicBranchModel branch) {
    List<ClinicOperatingHourModel> hoursForm = [];
    bool loading = true;
    bool saving = false;

    Future<void> load(void Function(void Function()) setDialogState) async {
      try {
        final existing = await ref
            .read(clinicServiceProvider)
            .getBranchHours(branch.branchId);
        final days = [1, 2, 3, 4, 5, 6, 7];
        final built = days.map((day) {
          final match = existing.where((h) => h.dayOfWeek == day);
          final found = match.isEmpty ? null : match.first;
          return ClinicOperatingHourModel(
            branchId: branch.branchId,
            dayOfWeek: day,
            isClosed: found?.isClosed ?? false,
            openTime: found?.openTime ?? '09:00',
            closeTime: found?.closeTime ?? '17:00',
            breakStart: found?.breakStart ?? '',
            breakEnd: found?.breakEnd ?? '',
          );
        }).toList();
        setDialogState(() {
          hoursForm = built;
          loading = false;
        });
      } catch (e) {
        setDialogState(() => loading = false);
        if (mounted) _showError('Failed to load branch hours: $e');
      }
    }

    String? normalizeTime(String? t) {
      if (t == null || t.isEmpty) return null;
      return t.length == 5 ? '$t:00' : t;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (loading && hoursForm.isEmpty) {
            load(setDialogState);
          }
          return AlertDialog(
            shape: _dialogShape(),
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Operating Hours - ${branch.branchNameEn}',
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: _kTextMain),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: _kTextMuted, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            content: SizedBox(
              width: _dialogWidth(context, preferred: 560),
              height: loading ? 120 : _dialogMaxHeight(context, preferred: 480),
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      itemCount: hoursForm.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final h = hoursForm[index];
                        final openCtrl =
                            TextEditingController(text: h.openTime);
                        final closeCtrl =
                            TextEditingController(text: h.closeTime);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    width: 100,
                                    child: Text(
                                      _dayNames[h.dayOfWeek] ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ),
                                  Checkbox(
                                    value: h.isClosed,
                                    activeColor: _kPrimaryGreen,
                                    onChanged: (val) => setDialogState(() {
                                      hoursForm[index] =
                                          ClinicOperatingHourModel(
                                        branchId: h.branchId,
                                        dayOfWeek: h.dayOfWeek,
                                        isClosed: val ?? false,
                                        openTime: h.openTime,
                                        closeTime: h.closeTime,
                                        breakStart: h.breakStart,
                                        breakEnd: h.breakEnd,
                                      );
                                    }),
                                  ),
                                  const Text('Closed',
                                      style: TextStyle(fontSize: 12)),
                                ],
                              ),
                              if (!h.isClosed)
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: openCtrl,
                                        decoration: const InputDecoration(
                                            labelText: 'Open (HH:mm)',
                                            isDense: true),
                                        onChanged: (val) => hoursForm[index] =
                                            ClinicOperatingHourModel(
                                          branchId: h.branchId,
                                          dayOfWeek: h.dayOfWeek,
                                          isClosed: h.isClosed,
                                          openTime: val,
                                          closeTime: h.closeTime,
                                          breakStart: h.breakStart,
                                          breakEnd: h.breakEnd,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: closeCtrl,
                                        decoration: const InputDecoration(
                                            labelText: 'Close (HH:mm)',
                                            isDense: true),
                                        onChanged: (val) => hoursForm[index] =
                                            ClinicOperatingHourModel(
                                          branchId: h.branchId,
                                          dayOfWeek: h.dayOfWeek,
                                          isClosed: h.isClosed,
                                          openTime: h.openTime,
                                          closeTime: val,
                                          breakStart: h.breakStart,
                                          breakEnd: h.breakEnd,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: saving
                    ? null
                    : () async {
                        setDialogState(() => saving = true);
                        final dtos = hoursForm
                            .map((h) => {
                                  'branchId': h.branchId,
                                  'dayOfWeek': h.dayOfWeek,
                                  'isClosed': h.isClosed,
                                  'openTime': normalizeTime(h.openTime),
                                  'closeTime': normalizeTime(h.closeTime),
                                  'breakStart': normalizeTime(h.breakStart),
                                  'breakEnd': normalizeTime(h.breakEnd),
                                })
                            .toList();
                        try {
                          await ref
                              .read(clinicServiceProvider)
                              .updateBranchHours(branch.branchId, dtos);
                          if (mounted) Navigator.pop(ctx);
                          if (mounted) {
                            _showSuccess('Branch hours updated successfully.');
                          }
                        } catch (e) {
                          setDialogState(() => saving = false);
                          if (mounted) {
                            _showError('Failed to update branch hours: $e');
                          }
                        }
                      },
                child: Text(saving ? 'Saving...' : 'Save Hours'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openSpecialtyDialog() {
    if (_selectedClinic == null) return;
    String? selectedSpecialtyId = _globalSpecialties.isNotEmpty
        ? _globalSpecialties.first.specialtyId
        : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: _dialogShape(),
          title: const Text('Link Medical Specialty',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          content: SizedBox(
            width: _dialogWidth(context, preferred: 440),
            child: DropdownButtonFormField<String>(
              initialValue: selectedSpecialtyId,
              decoration: const InputDecoration(labelText: 'Select Specialty *'),
              items: _globalSpecialties
                  .map((s) => DropdownMenuItem(
                      value: s.specialtyId, child: Text(s.nameEn)))
                  .toList(),
              onChanged: (val) => setDialogState(() => selectedSpecialtyId = val),
            ),
          ),
          actions: [
            OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryGreen,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (selectedSpecialtyId == null) return;
                try {
                  await ref
                      .read(clinicServiceProvider)
                      .addClinicSpecialty(
                          _selectedClinic!.clinicId, selectedSpecialtyId!);
                  if (mounted) Navigator.pop(ctx);
                  if (mounted) _showSuccess('Specialty linked successfully.');
                  _selectClinic(_selectedClinic!);
                } catch (e) {
                  if (mounted) _showError('Failed to link specialty: $e');
                }
              },
              child: const Text('Link Specialty'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteSpecialty(String specialtyId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: _dialogShape(),
        title: const Text('Unlink Specialty?'),
        content: const Text('Are you sure you want to remove this specialty from this clinic?'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kDangerRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(clinicServiceProvider)
          .deleteClinicSpecialty(_selectedClinic!.clinicId, specialtyId);
      _showSuccess('Specialty unlinked successfully.');
      _selectClinic(_selectedClinic!);
    } catch (e) {
      _showError('Failed to unlink specialty: $e');
    }
  }

  void _openInsuranceDialog() {
    if (_selectedClinic == null) return;
    String? selectedProviderId = _globalInsurances.isNotEmpty
        ? _globalInsurances.first.providerId
        : null;
    final networkClassController = TextEditingController(text: 'General');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: _dialogShape(),
          title: const Text('Link Insurance Network',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          content: SizedBox(
            width: _dialogWidth(context, preferred: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedProviderId,
                  decoration: const InputDecoration(labelText: 'Insurance Provider *'),
                  items: _globalInsurances
                      .map((p) => DropdownMenuItem(
                          value: p.providerId, child: Text(p.nameEn)))
                      .toList(),
                  onChanged: (val) => setDialogState(() => selectedProviderId = val),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: networkClassController,
                  decoration: const InputDecoration(
                    labelText: 'Network Class',
                    hintText: 'e.g. VIP, Gold, General',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryGreen,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (selectedProviderId == null) return;
                try {
                  await ref
                      .read(clinicServiceProvider)
                      .addClinicInsurance(
                          _selectedClinic!.clinicId, selectedProviderId!, {
                    'networkClass': networkClassController.text.trim(),
                    'isActive': true,
                  });
                  if (mounted) Navigator.pop(ctx);
                  if (mounted) _showSuccess('Insurance linked successfully.');
                  _selectClinic(_selectedClinic!);
                } catch (e) {
                  if (mounted) _showError('Failed to link insurance: $e');
                }
              },
              child: const Text('Link Provider'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteInsurance(String providerId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: _dialogShape(),
        title: const Text('Unlink Insurance?'),
        content: const Text('Are you sure you want to remove this insurance provider?'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kDangerRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(clinicServiceProvider)
          .deleteClinicInsurance(_selectedClinic!.clinicId, providerId);
      _showSuccess('Insurance unlinked successfully.');
      _selectClinic(_selectedClinic!);
    } catch (e) {
      _showError('Failed to unlink insurance: $e');
    }
  }

  void _openLanguageDialog() {
    if (_selectedClinic == null) return;
    String? selectedLanguageId = _globalLanguages.isNotEmpty
        ? _globalLanguages.first.languageId
        : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: _dialogShape(),
          title: const Text('Link Supported Language',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          content: SizedBox(
            width: _dialogWidth(context, preferred: 440),
            child: DropdownButtonFormField<String>(
              initialValue: selectedLanguageId,
              decoration: const InputDecoration(labelText: 'Select Language *'),
              items: _globalLanguages
                  .map((l) => DropdownMenuItem(
                      value: l.languageId, child: Text(l.nameEn)))
                  .toList(),
              onChanged: (val) => setDialogState(() => selectedLanguageId = val),
            ),
          ),
          actions: [
            OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryGreen,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (selectedLanguageId == null) return;
                try {
                  await ref
                      .read(clinicServiceProvider)
                      .addClinicLanguage(
                          _selectedClinic!.clinicId, selectedLanguageId!);
                  if (mounted) Navigator.pop(ctx);
                  if (mounted) _showSuccess('Language linked successfully.');
                  _selectClinic(_selectedClinic!);
                } catch (e) {
                  if (mounted) _showError('Failed to link language: $e');
                }
              },
              child: const Text('Link Language'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteLanguage(String languageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: _dialogShape(),
        title: const Text('Unlink Language?'),
        content: const Text('Are you sure you want to remove this language?'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kDangerRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(clinicServiceProvider)
          .deleteClinicLanguage(_selectedClinic!.clinicId, languageId);
      _showSuccess('Language unlinked successfully.');
      _selectClinic(_selectedClinic!);
    } catch (e) {
      _showError('Failed to unlink language: $e');
    }
  }

  void _deleteClinic(String clinicId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: _dialogShape(),
        title: const Text('Delete Clinic Facility?'),
        content: const Text('Are you sure you want to delete this clinic facility record? This cannot be undone.'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kDangerRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(clinicServiceProvider).deleteClinic(clinicId);
      _showSuccess('Clinic deleted successfully.');
      _loadClinics();
    } catch (e) {
      _showError('Failed to delete clinic: $e');
    }
  }

  void _deleteBranch(String branchId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: _dialogShape(),
        title: const Text('Delete Branch Location?'),
        content: const Text('Are you sure you want to delete this clinic branch location?'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kDangerRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(clinicServiceProvider).deleteClinicBranch(branchId);
      _showSuccess('Branch deleted successfully.');
      _selectClinic(_selectedClinic!);
    } catch (e) {
      _showError('Failed to delete branch: $e');
    }
  }

  // ── UI Components ────────────────────────────────────────────────────────

  Widget _buildSidebarCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'My Clinics',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _kTextMain,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _kPrimaryLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_filteredClinics.length} Listed',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _kPrimaryGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search by name or license...',
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18, color: _kTextMuted),
            ),
            onChanged: (v) => setState(() => _searchTerm = v),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredClinics.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _loadClinics,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text('No clinics found.',
                                    style: TextStyle(color: _kTextMuted, fontSize: 13)),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadClinics,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _filteredClinics.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final clinic = _filteredClinics[index];
                            final selected =
                                _selectedClinic?.clinicId == clinic.clinicId;

                            return InkWell(
                              onTap: () => _selectClinic(clinic),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: selected ? _kPrimaryLight.withValues(alpha: 0.3) : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected ? _kPrimaryGreen : _kBorderColor,
                                    width: selected ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: _kOffWhite,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: _kBorderColor),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Text('🏥', style: TextStyle(fontSize: 20)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            clinic.nameEn,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: _kPrimaryGreen,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'MOH: ${clinic.mohLicenseNumber.isEmpty ? 'N/A' : clinic.mohLicenseNumber}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: _kTextMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        minimumSize: Size.zero,
                                        side: const BorderSide(color: _kBorderColor),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      ),
                                      onPressed: () => _selectClinic(clinic),
                                      child: const Text(
                                        'Manage',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kTextMain),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicHeaderCard(ClinicModel clinic, bool isMobile) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x04000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildClinicAvatarBox(),
                    const SizedBox(width: 12),
                    Expanded(child: _buildClinicHeaderInfo(clinic)),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: _kAmber),
                          foregroundColor: _kAmber,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit Profile', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () => _openClinicDialog(clinic),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: _kDangerRed, size: 20),
                      tooltip: 'Delete Clinic Facility',
                      onPressed: () => _deleteClinic(clinic.clinicId),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildClinicAvatarBox(),
                const SizedBox(width: 16),
                Expanded(child: _buildClinicHeaderInfo(clinic)),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _kAmber),
                    foregroundColor: _kAmber,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit Profile', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _openClinicDialog(clinic),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: _kDangerRed, size: 20),
                  tooltip: 'Delete Clinic Facility',
                  onPressed: () => _deleteClinic(clinic.clinicId),
                ),
              ],
            ),
    );
  }

  Widget _buildClinicAvatarBox() {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: _kOffWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorderColor),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Text('🏥', style: TextStyle(fontSize: 26)),
          Positioned(
            bottom: 2,
            left: 2,
            right: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 1),
              decoration: BoxDecoration(
                color: _kDangerRed,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: const Text(
                'ACTIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 7,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClinicHeaderInfo(ClinicModel clinic) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${clinic.nameEn} (${clinic.nameAr})',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: _kTextMain,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          clinic.descriptionEn?.isNotEmpty == true ? clinic.descriptionEn! : 'No overview description provided',
          style: const TextStyle(fontSize: 12, color: _kTextMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kPrimaryLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'MOH: ${clinic.mohLicenseNumber.isEmpty ? 'N/A' : clinic.mohLicenseNumber}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _kPrimaryGreen,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.phone, size: 13, color: _kDangerRed),
                const SizedBox(width: 4),
                Text(
                  clinic.phonePrimary.isEmpty ? 'N/A' : clinic.phonePrimary,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kTextMain),
                ),
              ],
            ),
            if (clinic.email != null && clinic.email!.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.email_outlined, size: 13, color: _kTextMuted),
                  const SizedBox(width: 4),
                  Text(
                    clinic.email!,
                    style: const TextStyle(fontSize: 12, color: _kTextMuted),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTabsBar() {
    final tabs = [
      ('🏢 Branches (${_branches.length})', 0),
      ('🩺 Specialties (${_specialties.length})', 1),
      ('🛡️ Insurance (${_insurances.length})', 2),
      ('🗣️ Languages (${_languages.length})', 3),
    ];

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorderColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs.map((t) {
            final active = _activeSubTab == t.$2;
            return InkWell(
              onTap: () => setState(() => _activeSubTab = t.$2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: active ? _kPrimaryGreen : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Text(
                  t.$1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                    color: active ? _kPrimaryGreen : _kTextMuted,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBranchesTab(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Facility Branch Locations',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _kPrimaryGreen,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Branch', style: TextStyle(fontSize: 12)),
              onPressed: () => _openBranchDialog(null),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _branches.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🏢', style: TextStyle(fontSize: 32)),
                      SizedBox(height: 8),
                      Text('No branch locations added yet.',
                          style: TextStyle(color: _kTextMuted, fontSize: 13)),
                    ],
                  ),
                )
              : isMobile
                  ? ListView.separated(
                      itemCount: _branches.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _buildMobileBranchCard(_branches[i]),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: math.max(constraints.maxWidth, 720),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _kBorderColor),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Table(
                                  columnWidths: const {
                                    0: FlexColumnWidth(1.4),
                                    1: FlexColumnWidth(2.0),
                                    2: FlexColumnWidth(1.2),
                                    3: FlexColumnWidth(0.9),
                                    4: IntrinsicColumnWidth(),
                                  },
                                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                  children: [
                                    TableRow(
                                      decoration: const BoxDecoration(color: _kOffWhite),
                                      children: [
                                        _tableHeaderCell('BRANCH NAME'),
                                        _tableHeaderCell('ADDRESS'),
                                        _tableHeaderCell('CONTACT PHONE'),
                                        _tableHeaderCell('TYPE'),
                                        _tableHeaderCell('ACTIONS'),
                                      ],
                                    ),
                                    ..._branches.map((b) => _buildBranchTableRow(b)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _tableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: _kTextMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  TableRow _buildBranchTableRow(ClinicBranchModel b) {
    return TableRow(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kBorderColor)),
      ),
      children: [
        // Name with pink dot
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: _kDotPink,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  b.branchNameEn,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kTextMain),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // Address
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Text(
            b.addressLine1,
            style: const TextStyle(fontSize: 12, color: _kTextMain),
          ),
        ),
        // Phone
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Text(
            b.phone?.isNotEmpty == true ? b.phone! : 'N/A',
            style: const TextStyle(fontSize: 12, color: _kTextMuted),
          ),
        ),
        // Type
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: b.isPrimary ? _kPrimaryLight : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              b.isPrimary ? 'Primary' : 'Branch',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: b.isPrimary ? _kPrimaryGreen : _kTextMuted,
              ),
            ),
          ),
        ),
        // Actions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kAmber),
                  foregroundColor: _kAmber,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.edit_outlined, size: 13),
                label: const Text('Edit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                onPressed: () => _openBranchDialog(b),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kAmber),
                  foregroundColor: _kAmber,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.access_time, size: 13),
                label: const Text('Hours', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                onPressed: () => _openHoursDialog(b),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kDangerRed),
                  foregroundColor: _kDangerRed,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Delete', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                onPressed: () => _deleteBranch(b.branchId),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileBranchCard(ClinicBranchModel b) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: _kDotPink, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  b.branchNameEn,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kTextMain),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: b.isPrimary ? _kPrimaryLight : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  b.isPrimary ? 'Primary' : 'Branch',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: b.isPrimary ? _kPrimaryGreen : _kTextMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(b.addressLine1, style: const TextStyle(fontSize: 12, color: _kTextMain)),
          const SizedBox(height: 2),
          Text('Phone: ${b.phone?.isNotEmpty == true ? b.phone! : "N/A"}',
              style: const TextStyle(fontSize: 11, color: _kTextMuted)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _kAmber),
                    foregroundColor: _kAmber,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 12),
                  label: const Text('Edit', style: TextStyle(fontSize: 11)),
                  onPressed: () => _openBranchDialog(b),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _kAmber),
                    foregroundColor: _kAmber,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  icon: const Icon(Icons.access_time, size: 12),
                  label: const Text('Hours', style: TextStyle(fontSize: 11)),
                  onPressed: () => _openHoursDialog(b),
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kDangerRed),
                  foregroundColor: _kDangerRed,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: const Text('Delete', style: TextStyle(fontSize: 11)),
                onPressed: () => _deleteBranch(b.branchId),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialtiesTab(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Offered Medical Specialties',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _kPrimaryGreen,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Link Specialty', style: TextStyle(fontSize: 12)),
              onPressed: _openSpecialtyDialog,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _specialties.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  alignment: Alignment.center,
                  child: const Text('No specialties linked to this clinic.',
                      style: TextStyle(color: _kTextMuted, fontSize: 13)),
                )
              : GridView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: isMobile ? 400 : 280,
                    mainAxisExtent: 52,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _specialties.length,
                  itemBuilder: (context, idx) {
                    final s = _specialties[idx];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _kOffWhite,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kBorderColor),
                      ),
                      child: Row(
                        children: [
                          const Text('🩺', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _getSpecialtyName(s.specialtyId),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kTextMain),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.close, size: 16, color: _kDangerRed),
                            tooltip: 'Unlink',
                            onPressed: () => _deleteSpecialty(s.specialtyId),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildInsurancesTab(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Accepted Insurance Networks',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _kPrimaryGreen,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Link Provider', style: TextStyle(fontSize: 12)),
              onPressed: _openInsuranceDialog,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _insurances.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  alignment: Alignment.center,
                  child: const Text('No insurance providers linked to this clinic.',
                      style: TextStyle(color: _kTextMuted, fontSize: 13)),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _insurances.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final ins = _insurances[idx];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _kOffWhite,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kBorderColor),
                      ),
                      child: Row(
                        children: [
                          const Text('🛡️', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _getInsuranceName(ins.providerId),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _kTextMain),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: _kBorderColor),
                                      ),
                                      child: Text(
                                        ins.networkClass.isEmpty ? 'General' : ins.networkClass,
                                        style: const TextStyle(fontSize: 10, color: _kTextMuted),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: ins.isActive ? _kPrimaryLight : _kDangerLight,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        ins.isActive ? 'Active' : 'Suspended',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: ins.isActive ? _kPrimaryGreen : _kDangerRed,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: _kDangerRed, size: 18),
                            tooltip: 'Unlink',
                            onPressed: () => _deleteInsurance(ins.providerId),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLanguagesTab(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Supported Languages',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _kPrimaryGreen,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Link Language', style: TextStyle(fontSize: 12)),
              onPressed: _openLanguageDialog,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _languages.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  alignment: Alignment.center,
                  child: const Text('No languages linked to this clinic.',
                      style: TextStyle(color: _kTextMuted, fontSize: 13)),
                )
              : GridView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: isMobile ? 400 : 220,
                    mainAxisExtent: 50,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _languages.length,
                  itemBuilder: (context, idx) {
                    final lang = _languages[idx];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _kOffWhite,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kBorderColor),
                      ),
                      child: Row(
                        children: [
                          const Text('🗣️', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _getLanguageName(lang.languageId),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kTextMain),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.close, size: 16, color: _kDangerRed),
                            tooltip: 'Unlink',
                            onPressed: () => _deleteLanguage(lang.languageId),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDetailPanel({required bool isMobile}) {
    if (_selectedClinic == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorderColor),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(32),
        child: const Text(
          'Select a clinic facility from the list to manage its locations and details.',
          style: TextStyle(color: _kTextMuted, fontSize: 14),
        ),
      );
    }
    final clinic = _selectedClinic!;

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildClinicHeaderCard(clinic, true),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kBorderColor),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x04000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTabsBar(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    height: 480,
                    child: _isDetailLoading
                        ? const Center(child: CircularProgressIndicator())
                        : switch (_activeSubTab) {
                            0 => _buildBranchesTab(true),
                            1 => _buildSpecialtiesTab(true),
                            2 => _buildInsurancesTab(true),
                            _ => _buildLanguagesTab(true),
                          },
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildClinicHeaderCard(clinic, false),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kBorderColor),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x04000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTabsBar(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: _isDetailLoading
                        ? const Center(child: CircularProgressIndicator())
                        : switch (_activeSubTab) {
                            0 => _buildBranchesTab(false),
                            1 => _buildSpecialtiesTab(false),
                            2 => _buildInsurancesTab(false),
                            _ => _buildLanguagesTab(false),
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kOffWhite,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 920;
            return Padding(
              padding: EdgeInsets.all(isMobile ? 14 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Header Banner
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('🏥', style: TextStyle(fontSize: 20)),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Clinic Facility Roster',
                                    style: TextStyle(
                                      fontSize: isMobile ? 18 : 20,
                                      fontWeight: FontWeight.bold,
                                      color: _kPrimaryGreen,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Configure clinic locations, operating hours, medical specialties, and insurance networks',
                              style: TextStyle(fontSize: 12, color: _kTextMuted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimaryGreen,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 12 : 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(
                          isMobile ? 'Add' : 'Add Clinic',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _openClinicDialog(null),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Main Content: Split layout on Desktop, Scrollable stack on Mobile
                  Expanded(
                    child: isMobile
                        ? SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 320,
                                  width: double.infinity,
                                  child: _buildSidebarCard(),
                                ),
                                const SizedBox(height: 16),
                                _buildDetailPanel(isMobile: true),
                              ],
                            ),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 320, child: _buildSidebarCard()),
                              const SizedBox(width: 18),
                              Expanded(
                                child: _buildDetailPanel(isMobile: false),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Interactive Map Component matching screenshots 2 & 3 ───────────────────

class _InteractiveBranchMap extends StatefulWidget {
  final double lat;
  final double lng;
  final Function(double, double) onLocationSelected;

  const _InteractiveBranchMap({
    required this.lat,
    required this.lng,
    required this.onLocationSelected,
  });

  @override
  State<_InteractiveBranchMap> createState() => _InteractiveBranchMapState();
}

class _InteractiveBranchMapState extends State<_InteractiveBranchMap> {
  int _zoomLevel = 12;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFD6E4F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background stylized map tiles
          Positioned.fill(
            child: GestureDetector(
              onTapDown: (details) {
                final RenderBox box = context.findRenderObject() as RenderBox;
                final localPos = details.localPosition;
                final normalizedX = (localPos.dx / box.size.width) - 0.5;
                final normalizedY = (localPos.dy / box.size.height) - 0.5;

                // Adjust lat/lng offset based on tap
                final newLat = (widget.lat - (normalizedY * (10.0 / _zoomLevel))).clamp(-90.0, 90.0);
                final newLng = (widget.lng + (normalizedX * (15.0 / _zoomLevel))).clamp(-180.0, 180.0);
                widget.onLocationSelected(newLat, newLng);
              },
              child: CustomPaint(
                painter: _MapCanvasPainter(),
              ),
            ),
          ),

          // Center Location Pin with pulsing aura
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: 3,
                      ),
                      const BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 3)),
                    ],
                  ),
                  child: const Icon(Icons.location_on, size: 24, color: Colors.white),
                ),
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E3A8A),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),

          // Zoom Controls on top left
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorderColor),
                boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: () => setState(() => _zoomLevel = math.min(18, _zoomLevel + 1)),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Icon(Icons.add, size: 16, color: _kTextMain),
                    ),
                  ),
                  const Divider(height: 1, color: _kBorderColor),
                  InkWell(
                    onTap: () => setState(() => _zoomLevel = math.max(2, _zoomLevel - 1)),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Icon(Icons.remove, size: 16, color: _kTextMain),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Attribution on bottom right
          Positioned(
            bottom: 6,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _kBorderColor.withValues(alpha: 0.6)),
              ),
              child: const Text(
                '═ Leaflet | © OpenStreetMap contributors © CARTO',
                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w500, color: _kTextMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapCanvasPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Ocean/Water background
    final waterPaint = Paint()..color = const Color(0xFFD3E4F4);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), waterPaint);

    // Landmass contour
    final landPaint = Paint()..color = const Color(0xFFF3F1EC);
    final path = Path();
    path.moveTo(0, size.height * 0.35);
    path.quadraticBezierTo(size.width * 0.22, size.height * 0.12, size.width * 0.48, size.height * 0.28);
    path.quadraticBezierTo(size.width * 0.72, size.height * 0.42, size.width, size.height * 0.22);
    path.lineTo(size.width, size.height * 0.88);
    path.quadraticBezierTo(size.width * 0.65, size.height * 0.98, size.width * 0.32, size.height * 0.78);
    path.lineTo(0, size.height * 0.82);
    path.close();
    canvas.drawPath(path, landPaint);

    // Urban/District areas
    final urbanPaint = Paint()..color = const Color(0xFFE8E5DC);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(size.width * 0.5, size.height * 0.52), width: size.width * 0.45, height: size.height * 0.42),
        const Radius.circular(16),
      ),
      urbanPaint,
    );

    // Highway roads
    final highwayPaint = Paint()
      ..color = const Color(0xFFFED7AA)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    final hPath1 = Path();
    hPath1.moveTo(0, size.height * 0.5);
    hPath1.cubicTo(size.width * 0.3, size.height * 0.45, size.width * 0.6, size.height * 0.55, size.width, size.height * 0.48);
    canvas.drawPath(hPath1, highwayPaint);

    final hPath2 = Path();
    hPath2.moveTo(size.width * 0.5, 0);
    hPath2.cubicTo(size.width * 0.48, size.height * 0.35, size.width * 0.52, size.height * 0.65, size.width * 0.48, size.height);
    canvas.drawPath(hPath2, highwayPaint);

    // Street grid lines
    final streetPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.6;
    for (double x = 30; x < size.width; x += 36) {
      canvas.drawLine(Offset(x, size.height * 0.25), Offset(x, size.height * 0.8), streetPaint);
    }
    for (double y = size.height * 0.3; y < size.height * 0.8; y += 30) {
      canvas.drawLine(Offset(size.width * 0.15, y), Offset(size.width * 0.85, y), streetPaint);
    }

    // Grid coordinates
    final coordPaint = Paint()
      ..color = const Color(0xFF94A3B8).withValues(alpha: 0.25)
      ..strokeWidth = 0.8;
    for (double x = 0; x < size.width; x += 60) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), coordPaint);
    }
    for (double y = 0; y < size.height; y += 60) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), coordPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

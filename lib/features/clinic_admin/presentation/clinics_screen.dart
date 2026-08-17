import 'dart:async';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/references_service.dart';
import '../../../core/widgets/app_layout.dart';
import '../data/clinic_models.dart';
import '../data/clinic_service.dart';

// Brand colors and tokens matching Angular theme
const Color _kPrimaryTeal = Color(0xFF0D9488);
const Color _kPrimaryTealDark = Color(0xFF0F766E);
const Color _kPrimaryTealLight = Color(0xFFCCFBF1);
const Color _kPrimaryTealPale = Color(0xFFF0FDFA);
const Color _kAmber = Color(0xFFD97706);
const Color _kAmberLight = Color(0xFFFEF3C7);
const Color _kDangerRed = Color(0xFFDC2626);
const Color _kDangerLight = Color(0xFFFEE2E2);
const Color _kSuccessGreen = Color(0xFF16A34A);
const Color _kSuccessLight = Color(0xFFDCFCE7);
const Color _kInfoBlue = Color(0xFF2563EB);
const Color _kInfoLight = Color(0xFFDBEAFE);
const Color _kBorderColor = Color(0xFFE2E8F0);
const Color _kOffWhite = Color(0xFFF8FAFC);
const Color _kTextMain = Color(0xFF0F172A);
const Color _kTextMuted = Color(0xFF64748B);

RoundedRectangleBorder _dialogShape() =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

double _dialogMaxHeight(BuildContext context, {double preferred = 860}) {
  final mediaQuery = MediaQuery.of(context);
  final availableHeight = mediaQuery.size.height - mediaQuery.viewInsets.bottom;
  return math.min(preferred, availableHeight * 0.94);
}

double _dialogWidth(BuildContext context, {double preferred = 800}) {
  final screenWidth = MediaQuery.of(context).size.width;
  if (screenWidth < 600) return screenWidth - 16;
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
            c.nameAr.toLowerCase().contains(q) ||
            c.mohLicenseNumber.toLowerCase().contains(q))
        .toList();
  }

  // Sub-items for selected clinic
  List<ClinicBranchModel> _branches = [];
  List<ClinicSpecialtyModel> _specialties = [];
  List<ClinicInsuranceModel> _insurances = [];
  List<ClinicLanguageModel> _languages = [];

  // Operating Hours Map for branches
  final Map<String, List<ClinicOperatingHourModel>> _branchHoursMap = {};
  final Set<String> _expandedBranchScheduleIds = {};

  // Global lookup lists & Localities cache
  List<SpecialtyModel> _globalSpecialties = [];
  List<InsuranceProviderModel> _globalInsurances = [];
  List<LanguageModel> _globalLanguages = [];
  List<CityModel> _globalCities = [];
  final Map<String, List<LocalityModel>> _localitiesByCity = {};

  @override
  void initState() {
    super.initState();
    _loadClinics();
    _loadReferenceData();
  }

  @override
  void dispose() {
    if (ref.read(hideAppLayoutBarsProvider)) {
      Future.microtask(() {
        ref.read(hideAppLayoutBarsProvider.notifier).state = false;
      });
    }
    super.dispose();
  }

  Future<void> _loadReferenceData() async {
    try {
      final specialties =
          await ref.read(referenceServiceProvider).getAllSpecialties();
      if (mounted) setState(() => _globalSpecialties = specialties);
    } catch (e) {
      debugPrint('[Clinics] getAllSpecialties failed: $e');
    }
    try {
      final insurances =
          await ref.read(referenceServiceProvider).getAllInsuranceProviders();
      if (mounted) setState(() => _globalInsurances = insurances);
    } catch (e) {
      debugPrint('[Clinics] getAllInsuranceProviders failed: $e');
    }
    try {
      final languages =
          await ref.read(referenceServiceProvider).getAllLanguages();
      if (mounted) setState(() => _globalLanguages = languages);
    } catch (e) {
      debugPrint('[Clinics] getAllLanguages failed: $e');
    }
    try {
      final cities = await ref.read(referenceServiceProvider).getAllCities();
      if (mounted) setState(() => _globalCities = cities);
    } catch (e) {
      debugPrint('[Clinics] getAllCities failed: $e');
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

  String _getCityName(String cityId) {
    final match = _globalCities.where((c) => c.cityId == cityId);
    return match.isEmpty ? '' : match.first.nameEn;
  }

  String _getLocalityName(String cityId, String? localityId) {
    if (localityId == null || localityId.isEmpty) return '';
    final list = _localitiesByCity[cityId];
    if (list == null) return '';
    final match = list.where((l) => l.localityId == localityId);
    return match.isEmpty ? '' : match.first.nameEn;
  }

  String _getLogoUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('data:') ||
        path.startsWith('blob:')) {
      return path;
    }
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$kBaseUrl$cleanPath';
  }

  Future<void> _loadClinics() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref.read(clinicServiceProvider).getAllClinics();
      if (!mounted) return;
      setState(() => _clinics = res);
      if (res.isNotEmpty) {
        final isDesktop = MediaQuery.of(context).size.width >= 920;
        if (_selectedClinic != null &&
            res.any((c) => c.clinicId == _selectedClinic!.clinicId)) {
          final updated =
              res.firstWhere((c) => c.clinicId == _selectedClinic!.clinicId);
          await _selectClinic(updated);
        } else if (isDesktop) {
          await _selectClinic(res.first);
        }
      } else {
        setState(() {
          _selectedClinic = null;
          _branches = [];
          _specialties = [];
          _insurances = [];
          _languages = [];
        });
        ref.read(hideAppLayoutBarsProvider.notifier).state = false;
      }
    } catch (e) {
      debugPrint('[Clinics] getAllClinics failed: $e');
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
      if (mounted) {
        setState(() => _branches = branches);
        _loadAllBranchHours(branches);
        _preloadBranchLocalities(branches);
      }
    } catch (e) {
      debugPrint('[Clinics] getClinicBranches failed: $e');
      if (mounted) setState(() => _branches = []);
    }

    try {
      final specialties = await service.getClinicSpecialties(clinic.clinicId);
      if (mounted) setState(() => _specialties = specialties);
    } catch (e) {
      debugPrint('[Clinics] getClinicSpecialties failed: $e');
      if (mounted) setState(() => _specialties = []);
    }

    try {
      final insurances = await service.getClinicInsurances(clinic.clinicId);
      if (mounted) setState(() => _insurances = insurances);
    } catch (e) {
      debugPrint('[Clinics] getClinicInsurances failed: $e');
      if (mounted) setState(() => _insurances = []);
    }

    try {
      final languages = await service.getClinicLanguages(clinic.clinicId);
      if (mounted) setState(() => _languages = languages);
    } catch (e) {
      debugPrint('[Clinics] getClinicLanguages failed: $e');
      if (mounted) setState(() => _languages = []);
    }

    if (mounted) setState(() => _isDetailLoading = false);
  }

  void _preloadBranchLocalities(List<ClinicBranchModel> branches) {
    for (final b in branches) {
      if (b.cityId.isNotEmpty && !_localitiesByCity.containsKey(b.cityId)) {
        ref
            .read(referenceServiceProvider)
            .getLocalities(b.cityId)
            .then((data) {
          if (mounted) {
            setState(() => _localitiesByCity[b.cityId] = data);
          }
        }).catchError((_) {});
      }
    }
  }

  void _loadAllBranchHours(List<ClinicBranchModel> branches) {
    for (final b in branches) {
      ref.read(clinicServiceProvider).getBranchHours(b.branchId).then((hours) {
        if (mounted) {
          setState(() {
            _branchHoursMap[b.branchId] = hours;
          });
        }
      }).catchError((e) {
        debugPrint('[Clinics] getBranchHours failed for ${b.branchId}: $e');
      });
    }
  }

  void _toggleScheduleExpand(String branchId) {
    setState(() {
      if (_expandedBranchScheduleIds.contains(branchId)) {
        _expandedBranchScheduleIds.remove(branchId);
      } else {
        _expandedBranchScheduleIds.add(branchId);
      }
    });
  }

  List<ClinicOperatingHourModel> _getBranchHoursList(String branchId) {
    final hours = _branchHoursMap[branchId] ?? [];
    const days = [0, 1, 2, 3, 4, 5, 6];
    return days.map((day) {
      final match = hours.where((h) => h.dayOfWeek == day);
      if (match.isNotEmpty) return match.first;
      return ClinicOperatingHourModel(
        branchId: branchId,
        dayOfWeek: day,
        isClosed: day == 5, // Friday default closed
        openTime: '08:00',
        closeTime: '22:00',
        breakStart: '',
        breakEnd: '',
      );
    }).toList();
  }

  static String _getDayName(int dayOfWeek) {
    switch (dayOfWeek) {
      case 0:
        return 'Sunday';
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      default:
        return 'Day';
    }
  }

  ({
    bool isOpen,
    String label,
    Color badgeColor,
    Color badgeBgColor,
    String currentHoursText
  }) _getBranchStatus(String branchId) {
    final hours = _branchHoursMap[branchId];
    if (hours == null || hours.isEmpty) {
      return (
        isOpen: false,
        label: 'Hours Not Configured',
        badgeColor: _kTextMuted,
        badgeBgColor: const Color(0xFFF1F5F9),
        currentHoursText: 'N/A'
      );
    }

    final now = DateTime.now();
    final currentDay = now.weekday % 7; // 0=Sun..6=Sat
    final currentHour = now.hour;
    final currentMinute = now.minute;
    final currentTimeStr =
        '${currentHour.toString().padLeft(2, '0')}:${currentMinute.toString().padLeft(2, '0')}';

    final match = hours.where((h) => h.dayOfWeek == currentDay);
    final todayHour = match.isNotEmpty ? match.first : null;

    if (todayHour == null ||
        todayHour.isClosed ||
        todayHour.openTime.isEmpty ||
        todayHour.closeTime.isEmpty) {
      return (
        isOpen: false,
        label: 'Closed Today',
        badgeColor: _kDangerRed,
        badgeBgColor: _kDangerLight,
        currentHoursText: 'Closed'
      );
    }

    final openClean = todayHour.openTime.length >= 5
        ? todayHour.openTime.substring(0, 5)
        : todayHour.openTime;
    final closeClean = todayHour.closeTime.length >= 5
        ? todayHour.closeTime.substring(0, 5)
        : todayHour.closeTime;

    // Check break time
    if (todayHour.breakStart != null &&
        todayHour.breakEnd != null &&
        todayHour.breakStart!.isNotEmpty &&
        todayHour.breakEnd!.isNotEmpty) {
      final breakStartClean = todayHour.breakStart!.length >= 5
          ? todayHour.breakStart!.substring(0, 5)
          : todayHour.breakStart!;
      final breakEndClean = todayHour.breakEnd!.length >= 5
          ? todayHour.breakEnd!.substring(0, 5)
          : todayHour.breakEnd!;

      if (currentTimeStr.compareTo(breakStartClean) >= 0 &&
          currentTimeStr.compareTo(breakEndClean) < 0) {
        return (
          isOpen: false,
          label: 'On Break (until $breakEndClean)',
          badgeColor: _kAmber,
          badgeBgColor: _kAmberLight,
          currentHoursText: '$openClean - $closeClean'
        );
      }
    }

    if (currentTimeStr.compareTo(openClean) >= 0 &&
        currentTimeStr.compareTo(closeClean) < 0) {
      return (
        isOpen: true,
        label: 'Open (until $closeClean)',
        badgeColor: _kSuccessGreen,
        badgeBgColor: _kSuccessLight,
        currentHoursText: '$openClean - $closeClean'
      );
    } else if (currentTimeStr.compareTo(openClean) < 0) {
      return (
        isOpen: false,
        label: 'Closed (Opens at $openClean)',
        badgeColor: _kTextMuted,
        badgeBgColor: const Color(0xFFF1F5F9),
        currentHoursText: '$openClean - $closeClean'
      );
    } else {
      return (
        isOpen: false,
        label: 'Closed for the day',
        badgeColor: _kTextMuted,
        badgeBgColor: const Color(0xFFF1F5F9),
        currentHoursText: '$openClean - $closeClean'
      );
    }
  }

  void _showError(String message, {VoidCallback? retry}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _kDangerRed,
        duration: const Duration(seconds: 4),
        action: retry != null
            ? SnackBarAction(
                label: 'Retry', textColor: Colors.white, onPressed: retry)
            : null,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _kPrimaryTeal,
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
      try {
        final res = await dio.get(
          url,
          options: Options(
            headers: {
              'User-Agent': 'MedConsult/2.0 (medical.qa@medconsult.com)',
              'Accept-Language': 'en',
            },
            sendTimeout: const Duration(seconds: 6),
            receiveTimeout: const Duration(seconds: 6),
          ),
        );
        return (res.data is List) ? res.data as List : [];
      } catch (e) {
        debugPrint('[Clinics] Nominatim search query error ($url): $e');
        return [];
      }
    }

    try {
      final primary = await run(
          'https://nominatim.openstreetmap.org/search?format=json&q=$encoded&limit=10&addressdetails=1&countrycodes=sa');
      if (primary.isNotEmpty) return primary;
      return await run(
          'https://nominatim.openstreetmap.org/search?format=json&q=$encoded&limit=10&addressdetails=1');
    } catch (e) {
      debugPrint('[Clinics] location search exception: $e');
      return [];
    }
  }

  // ── Dialog 1: Add / Edit Clinic ──────────────────────────────────────────

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
    String? selectedLogoPath;
    String? selectedLogoName;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isNarrow = MediaQuery.of(context).size.width < 540;

          return AlertDialog(
            shape: _dialogShape(),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    isEdit ? 'Edit Clinic Profile' : 'Add New Clinic',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: _kTextMain),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: _kTextMuted, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            content: SizedBox(
              width: _dialogWidth(ctx, preferred: 700),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: _dialogMaxHeight(ctx)),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isNarrow) ...[
                        _buildDialogField(
                          label: 'Name (EN) *',
                          controller: nameEnController,
                          hintText: 'E.g. Al Noor Medical Center',
                        ),
                        const SizedBox(height: 10),
                        _buildDialogField(
                          label: 'Name (AR) *',
                          controller: nameArController,
                          hintText: 'مركز النور الطبي',
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: _buildDialogField(
                                label: 'Name (EN) *',
                                controller: nameEnController,
                                hintText: 'E.g. Al Noor Medical Center',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildDialogField(
                                label: 'Name (AR) *',
                                controller: nameArController,
                                hintText: 'مركز النور الطبي',
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),

                      // Logo Upload
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Clinic Logo Upload',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _kTextMain),
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () async {
                              final result = await FilePicker.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: [
                                  'png',
                                  'jpg',
                                  'jpeg',
                                  'webp',
                                  'svg'
                                ],
                              );
                              if (result != null &&
                                  result.files.single.path != null) {
                                setDialogState(() {
                                  selectedLogoPath = result.files.single.path;
                                  selectedLogoName = result.files.single.name;
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: _kOffWhite,
                                border: Border.all(color: _kBorderColor),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Text('📷',
                                      style: TextStyle(fontSize: 16)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      selectedLogoName ??
                                          (clinic?.logoUrl?.isNotEmpty == true
                                              ? 'Current: ${clinic!.logoUrl!.split("/").last}'
                                              : 'Choose logo image...'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: selectedLogoName != null
                                            ? _kPrimaryTeal
                                            : _kTextMuted,
                                        fontWeight: selectedLogoName != null
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (selectedLogoPath != null)
                                    GestureDetector(
                                      onTap: () => setDialogState(() {
                                        selectedLogoPath = null;
                                        selectedLogoName = null;
                                      }),
                                      child: const Icon(Icons.close,
                                          size: 16, color: _kDangerRed),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      _buildDialogField(
                        label: 'Description (EN)',
                        controller: descEnController,
                        maxLines: 2,
                        hintText: 'Brief clinic description',
                      ),
                      const SizedBox(height: 10),

                      if (isNarrow) ...[
                        _buildDialogField(
                          label: 'Primary Phone *',
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          hintText: '+966 11 000 0000',
                        ),
                        const SizedBox(height: 10),
                        _buildDialogField(
                          label: 'Email',
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          hintText: 'info@clinic.com',
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: _buildDialogField(
                                label: 'Primary Phone *',
                                controller: phoneController,
                                keyboardType: TextInputType.phone,
                                hintText: '+966 11 000 0000',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildDialogField(
                                label: 'Email',
                                controller: emailController,
                                keyboardType: TextInputType.emailAddress,
                                hintText: 'info@clinic.com',
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),

                      if (isNarrow) ...[
                        _buildDialogField(
                          label: 'MOH License Number *',
                          controller: mohController,
                          hintText: 'MOH-123456',
                        ),
                        const SizedBox(height: 10),
                        _buildDialogField(
                          label: 'VAT Registration Number',
                          controller: vatController,
                          hintText: '300000000000003',
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: _buildDialogField(
                                label: 'MOH License Number *',
                                controller: mohController,
                                hintText: 'MOH-123456',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildDialogField(
                                label: 'VAT Registration Number',
                                controller: vatController,
                                hintText: '300000000000003',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimaryTeal,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final nameEn = nameEnController.text.trim();
                  final nameAr = nameArController.text.trim();
                  final phone = phoneController.text.trim();
                  final moh = mohController.text.trim();
                  if (nameEn.isEmpty ||
                      nameAr.isEmpty ||
                      phone.isEmpty ||
                      moh.isEmpty) {
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
                      await ref.read(clinicServiceProvider).updateClinic(
                            clinic.clinicId,
                            payload,
                            logoFilePath: selectedLogoPath,
                          );
                    } else {
                      await ref.read(clinicServiceProvider).createClinic(
                            payload,
                            logoFilePath: selectedLogoPath,
                          );
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      _showSuccess(isEdit
                          ? 'Clinic profile updated successfully.'
                          : 'Clinic created successfully.');
                    }
                    _loadClinics();
                  } catch (e) {
                    if (mounted) {
                      _showError(isEdit
                          ? 'Failed to update clinic profile: $e'
                          : 'Failed to create clinic: $e');
                    }
                  }
                },
                child: Text(isEdit ? 'Save Profile' : 'Create Clinic'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Dialog 2: Add / Edit Branch ──────────────────────────────────────────

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
    final latController = TextEditingController(
        text: branch?.latitude?.toStringAsFixed(6) ?? '24.713600');
    final lngController = TextEditingController(
        text: branch?.longitude?.toStringAsFixed(6) ?? '46.675300');
    final searchController = TextEditingController();
    bool isPrimary = branch?.isPrimary ?? false;
    String? cityId =
        (branch?.cityId ?? '').isNotEmpty ? branch!.cityId : null;
    String? localityId = branch?.localityId;
    List<LocalityModel> localities = [];
    bool localitiesHydrated = false;
    List<dynamic> searchResults = [];
    bool isSearching = false;
    String? searchError;
    Timer? debounce;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (cityId != null && !localitiesHydrated) {
            localitiesHydrated = true;
            if (_localitiesByCity.containsKey(cityId)) {
              localities = _localitiesByCity[cityId!]!;
            } else {
              ref
                  .read(referenceServiceProvider)
                  .getLocalities(cityId!)
                  .then((data) {
                _localitiesByCity[cityId!] = data;
                if (ctx.mounted) setDialogState(() => localities = data);
              }).catchError((_) {});
            }
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
              _localitiesByCity[newCityId] = data;
              if (ctx.mounted) setDialogState(() => localities = data);
            } catch (_) {
              if (ctx.mounted) setDialogState(() => localities = []);
            }
          }

          void selectSearchResult(dynamic r) {
            final lat = double.tryParse(r['lat']?.toString() ?? '');
            final lon = double.tryParse(r['lon']?.toString() ?? '');
            if (lat != null && lon != null) {
              setDialogState(() {
                latController.text = lat.toStringAsFixed(6);
                lngController.text = lon.toStringAsFixed(6);
                searchResults = [];
                searchError = null;
                searchController.text = r['display_name']?.toString() ?? '';
              });
              FocusScope.of(ctx).unfocus();
            }
          }

          void executeSearch(String value) {
            debounce?.cancel();
            if (value.trim().isEmpty) return;
            setDialogState(() {
              isSearching = true;
              searchError = null;
            });
            FocusScope.of(ctx).unfocus();

            _searchBranchLocation(value).then((results) {
              if (!ctx.mounted) return;
              setDialogState(() {
                isSearching = false;
                searchResults = results;
                if (results.isNotEmpty) {
                  selectSearchResult(results.first);
                } else {
                  searchError =
                      'No locations found matching your query. Try searching by city or landmark name.';
                }
              });
            });
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
            debounce = Timer(const Duration(milliseconds: 400), () async {
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

          void useCurrentLocation() {
            setDialogState(() {
              latController.text = '24.713600';
              lngController.text = '46.675300';
              searchController.text = 'Riyadh, Saudi Arabia';
              searchResults = [];
              searchError = null;
            });
            FocusScope.of(ctx).unfocus();
            if (mounted) _showSuccess('Location set to current position.');
          }

          final isCompact = MediaQuery.of(context).size.width < 600;

          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.opaque,
            child: AlertDialog(
              shape: _dialogShape(),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 12,
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              actionsPadding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      isEdit
                          ? 'Edit Branch Location'
                          : 'Add Branch Location',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: _kTextMain,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: _kTextMuted, size: 20),
                    onPressed: () {
                      debounce?.cancel();
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: _dialogWidth(context, preferred: 840),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: _dialogMaxHeight(context, preferred: 880)),
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Branch Names
                        if (isCompact) ...[
                          _buildDialogField(
                            label: 'Branch Name (EN) *',
                            controller: nameEnController,
                            hintText: 'Main Branch - Olaya',
                          ),
                          const SizedBox(height: 10),
                          _buildDialogField(
                            label: 'Branch Name (AR) *',
                            controller: nameArController,
                            hintText: 'الفرع الرئيسي - العليا',
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: _buildDialogField(
                                  label: 'Branch Name (EN) *',
                                  controller: nameEnController,
                                  hintText: 'Main Branch - Olaya',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildDialogField(
                                  label: 'Branch Name (AR) *',
                                  controller: nameArController,
                                  hintText: 'الفرع الرئيسي - العليا',
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),

                        // City & Locality
                        if (isCompact) ...[
                          _buildDropdownField<String>(
                            label: 'City *',
                            value: cityId,
                            items: _globalCities
                                .map((c) => DropdownMenuItem(
                                    value: c.cityId, child: Text(c.nameEn)))
                                .toList(),
                            onChanged: onCityChanged,
                          ),
                          const SizedBox(height: 10),
                          _buildDropdownField<String>(
                            label: 'Locality / District *',
                            value: localityId,
                            items: localities
                                .map((l) => DropdownMenuItem(
                                    value: l.localityId, child: Text(l.nameEn)))
                                .toList(),
                            onChanged: cityId == null
                                ? null
                                : (v) => setDialogState(() => localityId = v),
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: _buildDropdownField<String>(
                                  label: 'City *',
                                  value: cityId,
                                  items: _globalCities
                                      .map((c) => DropdownMenuItem(
                                          value: c.cityId,
                                          child: Text(c.nameEn)))
                                      .toList(),
                                  onChanged: onCityChanged,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildDropdownField<String>(
                                  label: 'Locality / District *',
                                  value: localityId,
                                  items: localities
                                      .map((l) => DropdownMenuItem(
                                          value: l.localityId,
                                          child: Text(l.nameEn)))
                                      .toList(),
                                  onChanged: cityId == null
                                      ? null
                                      : (v) => setDialogState(
                                          () => localityId = v),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),

                        _buildDialogField(
                          label: 'Address Line 1 *',
                          controller: address1Controller,
                          hintText: 'King Fahd Road, Building 10',
                        ),
                        const SizedBox(height: 10),

                        _buildDialogField(
                          label: 'Address Line 2',
                          controller: address2Controller,
                          hintText: 'Floor 2, Suite 204',
                        ),
                        const SizedBox(height: 10),

                        if (isCompact) ...[
                          _buildDialogField(
                            label: 'Branch Phone',
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            hintText: '+966 11 123 4567',
                          ),
                          const SizedBox(height: 10),
                          _buildDialogField(
                            label: 'Branch Email',
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            hintText: 'branch@clinic.com',
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: _buildDialogField(
                                  label: 'Branch Phone',
                                  controller: phoneController,
                                  keyboardType: TextInputType.phone,
                                  hintText: '+966 11 123 4567',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildDialogField(
                                  label: 'Branch Email',
                                  controller: emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  hintText: 'branch@clinic.com',
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),

                        // Interactive Map Location Picker Section
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _kOffWhite,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _kBorderColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('📍', style: TextStyle(fontSize: 14)),
                                      SizedBox(width: 6),
                                      Text(
                                        'Branch Location on Map *',
                                        style: TextStyle(
                                          fontSize: 12,
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
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      side: const BorderSide(
                                          color: _kPrimaryTeal),
                                      foregroundColor: _kPrimaryTeal,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(6)),
                                    ),
                                    icon: const Icon(Icons.my_location,
                                        size: 12),
                                    label: const Text(
                                      'Use My Location',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('💡', style: TextStyle(fontSize: 12)),
                                  SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Type a city/place and tap Search, or tap anywhere on the map to position the pin.',
                                      style: TextStyle(
                                          fontSize: 11, color: _kTextMuted),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Map Search Bar
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: searchController,
                                      textInputAction: TextInputAction.search,
                                      decoration: InputDecoration(
                                        hintText: 'Search city, town, or landmark...',
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 8),
                                        prefixIcon: const Icon(Icons.search,
                                            size: 16, color: _kTextMuted),
                                        suffixIcon: isSearching
                                            ? const Padding(
                                                padding: EdgeInsets.all(8),
                                                child: SizedBox(
                                                    width: 14,
                                                    height: 14,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2)),
                                              )
                                            : null,
                                      ),
                                      onSubmitted: (v) => executeSearch(v),
                                      onChanged: onSearchChanged,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF64748B),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      minimumSize: Size.zero,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(6)),
                                    ),
                                    onPressed: () => executeSearch(
                                        searchController.text),
                                    child: const Text('Search',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              if (searchError != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(searchError!,
                                      style: const TextStyle(
                                          fontSize: 11, color: _kDangerRed)),
                                ),
                              if (searchResults.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  constraints:
                                      const BoxConstraints(maxHeight: 140),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: _kBorderColor),
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Color(0x0A000000),
                                          blurRadius: 4)
                                    ],
                                  ),
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: searchResults.length,
                                    itemBuilder: (context, i) {
                                      final r = searchResults[i];
                                      return ListTile(
                                        dense: true,
                                        leading: const Icon(Icons.place,
                                            size: 16, color: _kPrimaryTeal),
                                        title: Text(
                                          r['display_name']?.toString() ?? '',
                                          style: const TextStyle(fontSize: 11),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: () => selectSearchResult(r),
                                      );
                                    },
                                  ),
                                ),
                              const SizedBox(height: 8),

                              // Real OpenStreetMap Leaflet Canvas Container
                              _RealBranchMap(
                                lat: double.tryParse(latController.text) ??
                                    24.7136,
                                lng: double.tryParse(lngController.text) ??
                                    46.6753,
                                onLocationSelected: (newLat, newLng) {
                                  FocusScope.of(context).unfocus();
                                  setDialogState(() {
                                    latController.text =
                                        newLat.toStringAsFixed(6);
                                    lngController.text =
                                        newLng.toStringAsFixed(6);
                                  });
                                },
                              ),
                              const SizedBox(height: 8),

                              // Coordinates display bar
                              Wrap(
                                spacing: 12,
                                runSpacing: 6,
                                alignment: WrapAlignment.spaceBetween,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text('Latitude: ',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _kTextMuted)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border:
                                              Border.all(color: _kBorderColor),
                                        ),
                                        child: Text(
                                          latController.text.isEmpty
                                              ? 'Not Selected'
                                              : latController.text,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: _kPrimaryTeal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text('Longitude: ',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _kTextMuted)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border:
                                              Border.all(color: _kBorderColor),
                                        ),
                                        child: Text(
                                          lngController.text.isEmpty
                                              ? 'Not Selected'
                                              : lngController.text,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: _kPrimaryTeal,
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
                        const SizedBox(height: 12),

                        // Set as Primary Branch Checkbox
                        InkWell(
                          onTap: () =>
                              setDialogState(() => isPrimary = !isPrimary),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: isPrimary,
                                  activeColor: _kPrimaryTeal,
                                  onChanged: (val) => setDialogState(
                                      () => isPrimary = val ?? false),
                                ),
                                const Text(
                                  'Set as Primary Branch',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: _kTextMain),
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
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimaryTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
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
                      _showError(
                          'Please fill all required branch fields with valid values (*).');
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
                      if (ctx.mounted) Navigator.pop(ctx);
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
                  child: Text(isEdit ? 'Save Branch' : 'Add Branch'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Dialog 6: Edit Branch Operating Hours ───────────────────────────────

  void _openHoursDialog(ClinicBranchModel branch) {
    List<ClinicOperatingHourModel> hoursForm = [];
    bool loading = true;
    bool saving = false;

    Future<void> load(void Function(void Function()) setDialogState) async {
      try {
        final existing = await ref
            .read(clinicServiceProvider)
            .getBranchHours(branch.branchId);
        const days = [0, 1, 2, 3, 4, 5, 6];
        final built = days.map((day) {
          final match = existing.where((h) => h.dayOfWeek == day);
          final found = match.isNotEmpty ? match.first : null;
          return ClinicOperatingHourModel(
            branchId: branch.branchId,
            dayOfWeek: day,
            isClosed: found?.isClosed ?? (day == 5),
            openTime: found?.openTime != null && found!.openTime.length >= 5
                ? found.openTime.substring(0, 5)
                : '08:00',
            closeTime: found?.closeTime != null && found!.closeTime.length >= 5
                ? found.closeTime.substring(0, 5)
                : '22:00',
            breakStart: found?.breakStart != null && found!.breakStart!.length >= 5
                ? found.breakStart!.substring(0, 5)
                : '',
            breakEnd: found?.breakEnd != null && found!.breakEnd!.length >= 5
                ? found.breakEnd!.substring(0, 5)
                : '',
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

    void applyPreset(
        String preset, void Function(void Function()) setDialogState) {
      setDialogState(() {
        if (preset == 'standard') {
          // Sun - Thu: 08:00 - 22:00, Fri: Closed, Sat: 09:00 - 17:00
          hoursForm = hoursForm.map((h) {
            if (h.dayOfWeek >= 0 && h.dayOfWeek <= 4) {
              return ClinicOperatingHourModel(
                branchId: h.branchId,
                dayOfWeek: h.dayOfWeek,
                isClosed: false,
                openTime: '08:00',
                closeTime: '22:00',
                breakStart: '',
                breakEnd: '',
              );
            } else if (h.dayOfWeek == 5) {
              return ClinicOperatingHourModel(
                branchId: h.branchId,
                dayOfWeek: h.dayOfWeek,
                isClosed: true,
                openTime: '',
                closeTime: '',
                breakStart: '',
                breakEnd: '',
              );
            } else {
              return ClinicOperatingHourModel(
                branchId: h.branchId,
                dayOfWeek: h.dayOfWeek,
                isClosed: false,
                openTime: '09:00',
                closeTime: '17:00',
                breakStart: '',
                breakEnd: '',
              );
            }
          }).toList();
        } else if (preset == '24_7') {
          hoursForm = hoursForm
              .map((h) => ClinicOperatingHourModel(
                    branchId: h.branchId,
                    dayOfWeek: h.dayOfWeek,
                    isClosed: false,
                    openTime: '00:00',
                    closeTime: '23:59',
                    breakStart: '',
                    breakEnd: '',
                  ))
              .toList();
        } else if (preset == 'business') {
          // Sun - Thu: 09:00 - 17:00, Fri - Sat: Closed
          hoursForm = hoursForm.map((h) {
            if (h.dayOfWeek >= 0 && h.dayOfWeek <= 4) {
              return ClinicOperatingHourModel(
                branchId: h.branchId,
                dayOfWeek: h.dayOfWeek,
                isClosed: false,
                openTime: '09:00',
                closeTime: '17:00',
                breakStart: '',
                breakEnd: '',
              );
            } else {
              return ClinicOperatingHourModel(
                branchId: h.branchId,
                dayOfWeek: h.dayOfWeek,
                isClosed: true,
                openTime: '',
                closeTime: '',
                breakStart: '',
                breakEnd: '',
              );
            }
          }).toList();
        }
      });
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
          final isNarrow = MediaQuery.of(context).size.width < 600;

          return AlertDialog(
            shape: _dialogShape(),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.access_time, size: 17, color: _kPrimaryTeal),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Edit Branch Operating Hours',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _kTextMain),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Facility Branch: ${branch.branchNameEn}',
                        style: const TextStyle(fontSize: 11, color: _kTextMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: _kTextMuted, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            content: SizedBox(
              width: _dialogWidth(context, preferred: 780),
              height: loading ? 140 : _dialogMaxHeight(context, preferred: 600),
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Presets Box
                          Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: _kOffWhite,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: _kBorderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Quick Schedule Presets:',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _kPrimaryTeal),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        side: const BorderSide(
                                            color: _kBorderColor),
                                        backgroundColor: Colors.white,
                                      ),
                                      onPressed: () => applyPreset(
                                          'standard', setDialogState),
                                      child: const Text(
                                        '🏥 Standard (Sun-Thu 8am-10pm, Sat 9am-5pm, Fri Closed)',
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            color: _kTextMain,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        side: const BorderSide(
                                            color: _kBorderColor),
                                        backgroundColor: Colors.white,
                                      ),
                                      onPressed: () =>
                                          applyPreset('24_7', setDialogState),
                                      child: const Text(
                                        '🚨 24/7 Continuous Emergency Care',
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            color: _kTextMain,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        side: const BorderSide(
                                            color: _kBorderColor),
                                        backgroundColor: Colors.white,
                                      ),
                                      onPressed: () =>
                                          applyPreset('business', setDialogState),
                                      child: const Text(
                                        '🏢 Office Hours (Sun-Thu 9am-5pm)',
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            color: _kTextMain,
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Horizontally scrollable Hours Table on mobile
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 560),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: _kBorderColor),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Table(
                                  columnWidths: const {
                                    0: FixedColumnWidth(100),
                                    1: FixedColumnWidth(70),
                                    2: FixedColumnWidth(95),
                                    3: FixedColumnWidth(95),
                                    4: FixedColumnWidth(95),
                                    5: FixedColumnWidth(95),
                                  },
                                  defaultVerticalAlignment:
                                      TableCellVerticalAlignment.middle,
                                  children: [
                                    const TableRow(
                                      decoration: BoxDecoration(color: _kOffWhite),
                                      children: [
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 8),
                                          child: Text('DAY OF WEEK',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: _kTextMuted)),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 8),
                                          child: Text('CLOSED?',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: _kTextMuted)),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 8),
                                          child: Text('OPEN TIME',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: _kTextMuted)),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 8),
                                          child: Text('CLOSE TIME',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: _kTextMuted)),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 8),
                                          child: Text('BREAK START',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: _kTextMuted)),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 8),
                                          child: Text('BREAK END',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: _kTextMuted)),
                                        ),
                                      ],
                                    ),
                                    ...hoursForm.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final h = entry.value;
                                      return TableRow(
                                        decoration: BoxDecoration(
                                          color: h.isClosed
                                              ? const Color(0xFFFAFAFA)
                                              : Colors.white,
                                          border: const Border(
                                              top: BorderSide(
                                                  color: _kBorderColor)),
                                        ),
                                        children: [
                                          // Day Name
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 8),
                                            child: Text(
                                              _getDayName(h.dayOfWeek),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: _kPrimaryTeal,
                                              ),
                                            ),
                                          ),
                                          // Closed Checkbox
                                          Center(
                                            child: Checkbox(
                                              value: h.isClosed,
                                              activeColor: _kDangerRed,
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
                                          ),
                                          // Open Time
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 6),
                                            child: TextFormField(
                                              initialValue: h.openTime,
                                              enabled: !h.isClosed,
                                              style: const TextStyle(fontSize: 11),
                                              decoration: InputDecoration(
                                                isDense: true,
                                                hintText: '08:00',
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6, vertical: 6),
                                                filled: h.isClosed,
                                                fillColor: const Color(0xFFF1F5F9),
                                              ),
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
                                          // Close Time
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 6),
                                            child: TextFormField(
                                              initialValue: h.closeTime,
                                              enabled: !h.isClosed,
                                              style: const TextStyle(fontSize: 11),
                                              decoration: InputDecoration(
                                                isDense: true,
                                                hintText: '22:00',
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6, vertical: 6),
                                                filled: h.isClosed,
                                                fillColor: const Color(0xFFF1F5F9),
                                              ),
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
                                          // Break Start
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 6),
                                            child: TextFormField(
                                              initialValue: h.breakStart,
                                              enabled: !h.isClosed,
                                              style: const TextStyle(fontSize: 11),
                                              decoration: InputDecoration(
                                                isDense: true,
                                                hintText: '13:00',
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6, vertical: 6),
                                                filled: h.isClosed,
                                                fillColor: const Color(0xFFF1F5F9),
                                              ),
                                              onChanged: (val) => hoursForm[index] =
                                                  ClinicOperatingHourModel(
                                                branchId: h.branchId,
                                                dayOfWeek: h.dayOfWeek,
                                                isClosed: h.isClosed,
                                                openTime: h.openTime,
                                                closeTime: h.closeTime,
                                                breakStart: val,
                                                breakEnd: h.breakEnd,
                                              ),
                                            ),
                                          ),
                                          // Break End
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 6),
                                            child: TextFormField(
                                              initialValue: h.breakEnd,
                                              enabled: !h.isClosed,
                                              style: const TextStyle(fontSize: 11),
                                              decoration: InputDecoration(
                                                isDense: true,
                                                hintText: '14:00',
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6, vertical: 6),
                                                filled: h.isClosed,
                                                fillColor: const Color(0xFFF1F5F9),
                                              ),
                                              onChanged: (val) => hoursForm[index] =
                                                  ClinicOperatingHourModel(
                                                branchId: h.branchId,
                                                dayOfWeek: h.dayOfWeek,
                                                isClosed: h.isClosed,
                                                openTime: h.openTime,
                                                closeTime: h.closeTime,
                                                breakStart: h.breakStart,
                                                breakEnd: val,
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            actions: [
              if (isNarrow) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Changes apply to patient booking slots & open status.',
                      style: TextStyle(fontSize: 10.5, color: _kTextMuted),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPrimaryTeal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
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
                                            'openTime': (!h.isClosed &&
                                                    h.openTime.isNotEmpty)
                                                ? (normalizeTime(h.openTime) ??
                                                    '08:00:00')
                                                : '00:00:00',
                                            'closeTime': (!h.isClosed &&
                                                    h.closeTime.isNotEmpty)
                                                ? (normalizeTime(h.closeTime) ??
                                                    '22:00:00')
                                                : '00:00:00',
                                            'breakStart': (!h.isClosed &&
                                                    h.breakStart != null &&
                                                    h.breakStart!.isNotEmpty)
                                                ? normalizeTime(h.breakStart)
                                                : null,
                                            'breakEnd': (!h.isClosed &&
                                                    h.breakEnd != null &&
                                                    h.breakEnd!.isNotEmpty)
                                                ? normalizeTime(h.breakEnd)
                                                : null,
                                          })
                                      .toList();
                                  try {
                                    final updated = await ref
                                        .read(clinicServiceProvider)
                                        .updateBranchHours(branch.branchId, dtos);
                                    if (mounted) {
                                      setState(() {
                                        _branchHoursMap[branch.branchId] =
                                            updated;
                                      });
                                    }
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (mounted) {
                                      _showSuccess(
                                          'Branch hours updated successfully.');
                                    }
                                  } catch (e) {
                                    setDialogState(() => saving = false);
                                    if (mounted) {
                                      _showError(
                                          'Failed to update branch hours: $e');
                                    }
                                  }
                                },
                          child: Text(saving ? 'Saving...' : 'Save Hours'),
                        ),
                      ],
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Changes will apply to patient booking slots and branch open status.',
                        style: TextStyle(fontSize: 11, color: _kTextMuted),
                      ),
                    ),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPrimaryTeal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
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
                                            'openTime': (!h.isClosed &&
                                                    h.openTime.isNotEmpty)
                                                ? (normalizeTime(h.openTime) ??
                                                    '08:00:00')
                                                : '00:00:00',
                                            'closeTime': (!h.isClosed &&
                                                    h.closeTime.isNotEmpty)
                                                ? (normalizeTime(h.closeTime) ??
                                                    '22:00:00')
                                                : '00:00:00',
                                            'breakStart': (!h.isClosed &&
                                                    h.breakStart != null &&
                                                    h.breakStart!.isNotEmpty)
                                                ? normalizeTime(h.breakStart)
                                                : null,
                                            'breakEnd': (!h.isClosed &&
                                                    h.breakEnd != null &&
                                                    h.breakEnd!.isNotEmpty)
                                                ? normalizeTime(h.breakEnd)
                                                : null,
                                          })
                                      .toList();
                                  try {
                                    final updated = await ref
                                        .read(clinicServiceProvider)
                                        .updateBranchHours(branch.branchId, dtos);
                                    if (mounted) {
                                      setState(() {
                                        _branchHoursMap[branch.branchId] =
                                            updated;
                                      });
                                    }
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (mounted) {
                                      _showSuccess(
                                          'Branch hours updated successfully.');
                                    }
                                  } catch (e) {
                                    setDialogState(() => saving = false);
                                    if (mounted) {
                                      _showError(
                                          'Failed to update branch hours: $e');
                                    }
                                  }
                                },
                          child: Text(
                              saving ? 'Saving...' : 'Save Operating Hours'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ── Dialog 3: Link Specialty ─────────────────────────────────────────────

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
            child: _buildDropdownField<String>(
              label: 'Choose Specialty *',
              value: selectedSpecialtyId,
              items: _globalSpecialties
                  .map((s) => DropdownMenuItem(
                      value: s.specialtyId,
                      child: Text(s.nameEn, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (val) =>
                  setDialogState(() => selectedSpecialtyId = val),
            ),
          ),
          actions: [
            OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryTeal,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (selectedSpecialtyId == null) return;
                try {
                  await ref.read(clinicServiceProvider).addClinicSpecialty(
                      _selectedClinic!.clinicId, selectedSpecialtyId!);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) _showSuccess('Specialty linked to clinic.');
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
        content: const Text(
            'Are you sure you want to unlink this specialty from the clinic?'),
        actions: [
          OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kDangerRed, foregroundColor: Colors.white),
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
      _showSuccess('Specialty unlinked.');
      _selectClinic(_selectedClinic!);
    } catch (e) {
      _showError('Failed to unlink specialty: $e');
    }
  }

  // ── Dialog 4: Link Insurance ─────────────────────────────────────────────

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
          title: const Text('Associate Insurance Provider',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          content: SizedBox(
            width: _dialogWidth(context, preferred: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDropdownField<String>(
                  label: 'Insurance Provider *',
                  value: selectedProviderId,
                  items: _globalInsurances
                      .map((p) => DropdownMenuItem(
                          value: p.providerId,
                          child:
                              Text(p.nameEn, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => selectedProviderId = val),
                ),
                const SizedBox(height: 12),
                _buildDialogField(
                  label: 'Network Class *',
                  controller: networkClassController,
                  hintText: 'E.g. VIP, Class A, Gold',
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryTeal,
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
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    _showSuccess('Insurance provider associated.');
                  }
                  _selectClinic(_selectedClinic!);
                } catch (e) {
                  if (mounted) _showError('Failed to link insurance: $e');
                }
              },
              child: const Text('Associate Provider'),
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
        title: const Text('Unlink Insurance Provider?'),
        content: const Text(
            'Are you sure you want to unlink this insurance provider?'),
        actions: [
          OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kDangerRed, foregroundColor: Colors.white),
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
      _showSuccess('Insurance unlinked.');
      _selectClinic(_selectedClinic!);
    } catch (e) {
      _showError('Failed to unlink insurance: $e');
    }
  }

  // ── Dialog 5: Link Language ──────────────────────────────────────────────

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
            child: _buildDropdownField<String>(
              label: 'Choose Language *',
              value: selectedLanguageId,
              items: _globalLanguages
                  .map((l) => DropdownMenuItem(
                      value: l.languageId,
                      child: Text(l.nameEn, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (val) =>
                  setDialogState(() => selectedLanguageId = val),
            ),
          ),
          actions: [
            OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryTeal,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (selectedLanguageId == null) return;
                try {
                  await ref.read(clinicServiceProvider).addClinicLanguage(
                      _selectedClinic!.clinicId, selectedLanguageId!);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) _showSuccess('Language linked to clinic.');
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
        content: const Text(
            'Are you sure you want to unlink this language from the clinic?'),
        actions: [
          OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kDangerRed, foregroundColor: Colors.white),
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
      _showSuccess('Language unlinked.');
      _selectClinic(_selectedClinic!);
    } catch (e) {
      _showError('Failed to unlink language: $e');
    }
  }

  void _deleteBranch(String branchId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: _dialogShape(),
        title: const Text('Delete Branch?'),
        content: const Text('Are you sure you want to remove this branch?'),
        actions: [
          OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _kDangerRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(clinicServiceProvider).deleteClinicBranch(branchId);
      _showSuccess('Branch removed.');
      _selectClinic(_selectedClinic!);
    } catch (e) {
      _showError('Failed to delete branch: $e');
    }
  }

  // ── Helper Form Widgets ──────────────────────────────────────────────────

  static Widget _buildDialogField({
    required String label,
    required TextEditingController controller,
    String? hintText,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: _kTextMain),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hintText,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: _kTextMain),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<T>(
          initialValue: value,
          isDense: true,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          items: items,
          onChanged: onChanged,
        ),
      ],
    );
  }

  // ── UI Sections ──────────────────────────────────────────────────────────

  Widget _buildSidebarCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorderColor),
        boxShadow: const [
          BoxShadow(
              color: Color(0x04000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(14),
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
                    color: _kTextMain),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kPrimaryTealLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_filteredClinics.length} Listed',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _kPrimaryTealDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search by name or license...',
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18, color: _kTextMuted),
            ),
            onChanged: (v) => setState(() => _searchTerm = v),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredClinics.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _loadClinics,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 20),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 24),
                              decoration: BoxDecoration(
                                color: _kOffWhite,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _kBorderColor),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('🏥', style: TextStyle(fontSize: 30)),
                                  SizedBox(height: 8),
                                  Text(
                                    'No matching clinics found.',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _kTextMain),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Try adjusting your search terms or click "+ Add Clinic".',
                                    style: TextStyle(
                                        fontSize: 11, color: _kTextMuted),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
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
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final clinic = _filteredClinics[index];
                            final selected =
                                _selectedClinic?.clinicId == clinic.clinicId;
                            final logoUrl = _getLogoUrl(clinic.logoUrl);

                            return InkWell(
                              onTap: () => _selectClinic(clinic),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? _kPrimaryTealPale
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: selected
                                        ? _kPrimaryTeal
                                        : _kBorderColor,
                                    width: selected ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: _kOffWhite,
                                        borderRadius: BorderRadius.circular(6),
                                        border:
                                            Border.all(color: _kBorderColor),
                                      ),
                                      alignment: Alignment.center,
                                      clipBehavior: Clip.antiAlias,
                                      child: logoUrl.isNotEmpty
                                          ? Image.network(
                                              logoUrl,
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, __, ___) =>
                                                  const Text('🏥',
                                                      style: TextStyle(
                                                          fontSize: 18)),
                                            )
                                          : const Text('🏥',
                                              style: TextStyle(fontSize: 18)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            clinic.nameEn,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: _kPrimaryTealDark,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'MOH: ${clinic.mohLicenseNumber.isEmpty ? 'N/A' : clinic.mohLicenseNumber}',
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              color: _kTextMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        minimumSize: Size.zero,
                                        side: const BorderSide(
                                            color: _kBorderColor),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(6)),
                                      ),
                                      onPressed: () => _selectClinic(clinic),
                                      child: const Text(
                                        'Manage',
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: _kTextMain),
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

  Widget _buildClinicHeaderCard(ClinicModel clinic) {
    final logoUrl = _getLogoUrl(clinic.logoUrl);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 620;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorderColor),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x04000000), blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo 54x54 on mobile / 60x60 on desktop
                  Container(
                    width: isNarrow ? 52 : 60,
                    height: isNarrow ? 52 : 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kBorderColor),
                    ),
                    alignment: Alignment.center,
                    clipBehavior: Clip.antiAlias,
                    child: logoUrl.isNotEmpty
                        ? Image.network(
                            logoUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const Text('🏥', style: TextStyle(fontSize: 24)),
                          )
                        : const Text('🏥', style: TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              clinic.nameEn,
                              style: TextStyle(
                                fontSize: isNarrow ? 14.5 : 16,
                                fontWeight: FontWeight.bold,
                                color: _kTextMain,
                              ),
                            ),
                            if (clinic.nameAr.isNotEmpty)
                              Text(
                                '(${clinic.nameAr})',
                                style: const TextStyle(
                                    fontSize: 11.5, color: _kTextMuted),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          clinic.descriptionEn?.isNotEmpty == true
                              ? clinic.descriptionEn!
                              : 'No overview description provided.',
                          style: const TextStyle(
                              fontSize: 11.5, color: _kTextMuted),
                          softWrap: true,
                        ),
                      ],
                    ),
                  ),
                  if (!isNarrow) ...[
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _kBorderColor),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Text('✏️', style: TextStyle(fontSize: 12)),
                      label: const Text('Edit Profile',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _kTextMain)),
                      onPressed: () => _openClinicDialog(clinic),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),

              // Badges & Actions Wrap
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: _kPrimaryTealLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'MOH: ${clinic.mohLicenseNumber.isEmpty ? 'N/A' : clinic.mohLicenseNumber}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: _kPrimaryTealDark,
                      ),
                    ),
                  ),
                  if (clinic.vatNumber?.isNotEmpty == true)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: _kInfoLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'VAT: ${clinic.vatNumber}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: _kInfoBlue,
                        ),
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('📞', style: TextStyle(fontSize: 11)),
                      const SizedBox(width: 3),
                      Text(
                        clinic.phonePrimary.isEmpty
                            ? 'N/A'
                            : clinic.phonePrimary,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _kTextMain),
                      ),
                    ],
                  ),
                  if (clinic.email?.isNotEmpty == true)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('✉️', style: TextStyle(fontSize: 11)),
                        const SizedBox(width: 3),
                        Text(
                          clinic.email!,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _kTextMain),
                        ),
                      ],
                    ),
                  if (isNarrow)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _kBorderColor),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Text('✏️', style: TextStyle(fontSize: 11)),
                      label: const Text('Edit Profile',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _kTextMain)),
                      onPressed: () => _openClinicDialog(clinic),
                    ),
                ],
              ),
            ],
          ),
        );
      },
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: active ? _kPrimaryTeal : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Text(
                  t.$1,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                    color: active ? _kPrimaryTeal : _kTextMuted,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Sub-Tab 1: Branches Rich Grid ────────────────────────────────────────

  Widget _buildBranchesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Facility Branches',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _kPrimaryTealDark,
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    'Manage branches, coordinates & hours',
                    style: TextStyle(fontSize: 10.5, color: _kTextMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryTeal,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add Branch',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: () => _openBranchDialog(null),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _branches.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _kOffWhite,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kBorderColor),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🏢', style: TextStyle(fontSize: 30)),
                      const SizedBox(height: 6),
                      const Text('No branch locations added yet.',
                          style: TextStyle(
                              color: _kTextMain,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => _openBranchDialog(null),
                        child: const Text('+ Add First Branch',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _branches.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) =>
                      _buildBranchFacilityCard(_branches[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildBranchFacilityCard(ClinicBranchModel b) {
    final status = _getBranchStatus(b.branchId);
    final isExpanded = _expandedBranchScheduleIds.contains(b.branchId);
    final cityName = _getCityName(b.cityId);
    final localityName = _getLocalityName(b.cityId, b.localityId);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorderColor),
        boxShadow: const [
          BoxShadow(
              color: Color(0x03000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branch Card Header with responsive wrap
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: _kOffWhite,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _kPrimaryTealLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.location_city,
                      color: _kPrimaryTeal, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            b.branchNameEn,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _kTextMain,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: b.isPrimary
                                  ? _kSuccessLight
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              b.isPrimary
                                  ? 'Primary Facility'
                                  : 'Secondary Branch',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: b.isPrimary
                                    ? _kSuccessGreen
                                    : _kTextMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (b.branchNameAr.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            b.branchNameAr,
                            style: const TextStyle(
                                fontSize: 11, color: _kTextMuted),
                          ),
                        ),
                      const SizedBox(height: 4),
                      // Live Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: status.badgeBgColor,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          status.label,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: status.badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Branch Card Body
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Location details with full visibility
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📍', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${b.addressLine1}${b.addressLine2?.isNotEmpty == true ? ', ${b.addressLine2}' : ''}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _kTextMain),
                            softWrap: true,
                          ),
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 6,
                            runSpacing: 5,
                            children: [
                              if (cityName.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _kInfoLight,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(cityName,
                                      style: const TextStyle(
                                          fontSize: 10, color: _kInfoBlue)),
                                ),
                              if (localityName.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _kPrimaryTealLight,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(localityName,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: _kPrimaryTealDark)),
                                ),
                              if (b.latitude != null && b.longitude != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'GPS: ${b.latitude!.toStringAsFixed(3)}, ${b.longitude!.toStringAsFixed(3)}',
                                    style: const TextStyle(
                                        fontSize: 10, color: _kTextMuted),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Phone & Email row
                if (b.phone?.isNotEmpty == true || b.email?.isNotEmpty == true)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📞', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            if (b.phone?.isNotEmpty == true)
                              Text(
                                b.phone!,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: _kTextMain),
                              ),
                            if (b.email?.isNotEmpty == true)
                              Text(
                                '✉️ ${b.email}',
                                style: const TextStyle(
                                    fontSize: 11.5, color: _kTextMuted),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),

                // Operating Hours Schedule Box with zero overflow
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _kOffWhite,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kBorderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: () => _toggleScheduleExpand(b.branchId),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time,
                                size: 14, color: _kPrimaryTeal),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'Operating Hours',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _kPrimaryTealDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isExpanded
                                  ? 'Hide ▲'
                                  : '7-Day Schedule ▼',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _kPrimaryTeal),
                            ),
                          ],
                        ),
                      ),
                      if (isExpanded) ...[
                        const Divider(height: 14),
                        ..._getBranchHoursList(b.branchId).map((h) {
                          final hasBreak = (h.breakStart?.isNotEmpty == true &&
                              h.breakEnd?.isNotEmpty == true);
                          final openStr = h.openTime.length >= 5
                              ? h.openTime.substring(0, 5)
                              : h.openTime;
                          final closeStr = h.closeTime.length >= 5
                              ? h.closeTime.substring(0, 5)
                              : h.closeTime;
                          final breakStartStr = (hasBreak &&
                                  h.breakStart!.length >= 5)
                              ? h.breakStart!.substring(0, 5)
                              : (h.breakStart ?? '');
                          final breakEndStr =
                              (hasBreak && h.breakEnd!.length >= 5)
                                  ? h.breakEnd!.substring(0, 5)
                                  : (h.breakEnd ?? '');

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _getDayName(h.dayOfWeek),
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: _kTextMain),
                                ),
                                const SizedBox(width: 8),
                                if (h.isClosed)
                                  const Text('Closed',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: _kDangerRed))
                                else
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '$openStr - $closeStr',
                                          style: const TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: _kTextMain),
                                          textAlign: TextAlign.end,
                                        ),
                                        if (hasBreak)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 1),
                                            child: Text(
                                              'Break: $breakStartStr - $breakEndStr',
                                              style: const TextStyle(
                                                  fontSize: 10.5,
                                                  color: _kAmber,
                                                  fontWeight: FontWeight.w500),
                                              textAlign: TextAlign.end,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Branch Card Footer Actions with responsive layout
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: _kBorderColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimaryTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.access_time, size: 14),
                  label: const Text('Set Operating Hours',
                      style: TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.bold)),
                  onPressed: () => _openHoursDialog(b),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          side: const BorderSide(color: _kBorderColor),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                        ),
                        icon: const Icon(Icons.edit_outlined,
                            size: 13, color: _kTextMain),
                        label: const Text('Edit',
                            style: TextStyle(
                                fontSize: 11.5, color: _kTextMain)),
                        onPressed: () => _openBranchDialog(b),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      style: IconButton.styleFrom(
                        side: const BorderSide(color: _kDangerLight),
                        backgroundColor: _kDangerLight.withValues(alpha: 0.5),
                        padding: const EdgeInsets.all(6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Icon(Icons.delete_outline,
                          size: 16, color: _kDangerRed),
                      tooltip: 'Delete Branch',
                      onPressed: () => _deleteBranch(b.branchId),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sub-Tab 2: Specialties ───────────────────────────────────────────────

  Widget _buildSpecialtiesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Text(
                'Offered Medical Specialties',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: _kPrimaryTealDark,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryTeal,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Link Specialty',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: _openSpecialtyDialog,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _specialties.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _kOffWhite,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kBorderColor),
                  ),
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🩺', style: TextStyle(fontSize: 30)),
                      SizedBox(height: 6),
                      Text('No specialties linked to this clinic.',
                          style: TextStyle(color: _kTextMuted, fontSize: 12.5)),
                    ],
                  ),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _specialties.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final s = _specialties[idx];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kBorderColor),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x02000000),
                              blurRadius: 4,
                              offset: Offset(0, 1)),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _kPrimaryTealLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('🩺',
                                style: TextStyle(fontSize: 16)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _getSpecialtyName(s.specialtyId),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _kTextMain),
                              softWrap: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              side: const BorderSide(color: _kDangerRed),
                              foregroundColor: _kDangerRed,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6)),
                            ),
                            icon: const Icon(Icons.link_off, size: 13),
                            label: const Text('Unlink',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold)),
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

  // ── Sub-Tab 3: Insurances ────────────────────────────────────────────────

  Widget _buildInsurancesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Text(
                'Accepted Insurance Networks',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: _kPrimaryTealDark,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryTeal,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Link Provider',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: _openInsuranceDialog,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _insurances.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _kOffWhite,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kBorderColor),
                  ),
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🛡️', style: TextStyle(fontSize: 30)),
                      SizedBox(height: 6),
                      Text(
                          'No insurance providers linked to this clinic.',
                          style: TextStyle(color: _kTextMuted, fontSize: 12.5)),
                    ],
                  ),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _insurances.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final ins = _insurances[idx];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kBorderColor),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x02000000),
                              blurRadius: 4,
                              offset: Offset(0, 1)),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _kInfoLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('🛡️',
                                style: TextStyle(fontSize: 16)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _getInsuranceName(ins.providerId),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: _kPrimaryTealDark),
                                  softWrap: true,
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _kInfoLight,
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Class: ${ins.networkClass.isEmpty ? "General" : ins.networkClass}',
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: _kInfoBlue,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: ins.isActive
                                            ? _kSuccessLight
                                            : _kDangerLight,
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        ins.isActive
                                            ? 'Active Network'
                                            : 'Suspended',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: ins.isActive
                                              ? _kSuccessGreen
                                              : _kDangerRed,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: _kDangerRed),
                              foregroundColor: _kDangerRed,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6)),
                            ),
                            icon: const Icon(Icons.link_off, size: 13),
                            label: const Text('Unlink',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold)),
                            onPressed: () =>
                                _deleteInsurance(ins.providerId),
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

  // ── Sub-Tab 4: Languages ─────────────────────────────────────────────────

  Widget _buildLanguagesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Expanded(
              child: Text(
                'Supported Languages',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: _kPrimaryTealDark,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryTeal,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Link Language',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: _openLanguageDialog,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _languages.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _kOffWhite,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kBorderColor),
                  ),
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🗣️', style: TextStyle(fontSize: 30)),
                      SizedBox(height: 6),
                      Text('No languages linked to this clinic.',
                          style: TextStyle(color: _kTextMuted, fontSize: 12.5)),
                    ],
                  ),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _languages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final lang = _languages[idx];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kBorderColor),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x02000000),
                              blurRadius: 4,
                              offset: Offset(0, 1)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _kPrimaryTealLight,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('🗣️',
                                style: TextStyle(fontSize: 16)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _getLanguageName(lang.languageId),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _kTextMain),
                              softWrap: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              side: const BorderSide(color: _kDangerRed),
                              foregroundColor: _kDangerRed,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6)),
                            ),
                            icon: const Icon(Icons.link_off, size: 13),
                            label: const Text('Unlink',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold)),
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

  // ── Main Details Panel ───────────────────────────────────────────────────

  Widget _buildDetailPanel({bool isMobile = false}) {
    if (_selectedClinic == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorderColor),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🏥', style: TextStyle(fontSize: 34)),
            SizedBox(height: 10),
            Text(
              'Select a clinic facility from the roster to manage branches, specialties, and operating hours.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kTextMuted, fontSize: 12.5),
            ),
          ],
        ),
      );
    }

    final clinic = _selectedClinic!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Navigation header for mobile
        if (isMobile)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _kBorderColor),
                    backgroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.arrow_back, size: 14, color: _kTextMain),
                  label: const Text('Back to Clinics List',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: _kTextMain)),
                  onPressed: () {
                    setState(() => _selectedClinic = null);
                    ref.read(hideAppLayoutBarsProvider.notifier).state = false;
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Managing: ${clinic.nameEn}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _kPrimaryTealDark,
                    ),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        _buildClinicHeaderCard(clinic),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorderColor),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x04000000),
                    blurRadius: 6,
                    offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTabsBar(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _isDetailLoading
                        ? const Center(child: CircularProgressIndicator())
                        : switch (_activeSubTab) {
                            0 => _buildBranchesTab(),
                            1 => _buildSpecialtiesTab(),
                            2 => _buildInsurancesTab(),
                            _ => _buildLanguagesTab(),
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
            final isDetailViewOnMobile = isMobile && _selectedClinic != null;

            // Synchronize full screen mode with AppLayout on mobile only
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted &&
                  ref.read(hideAppLayoutBarsProvider) != isDetailViewOnMobile) {
                ref.read(hideAppLayoutBarsProvider.notifier).state =
                    isDetailViewOnMobile;
              }
            });

            if (isDetailViewOnMobile) {
              return Padding(
                padding: const EdgeInsets.all(10),
                child: _buildDetailPanel(isMobile: true),
              );
            }

            return Padding(
              padding: EdgeInsets.all(isMobile ? 10 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Banner
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
                                const Text('🏥',
                                    style: TextStyle(fontSize: 18)),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Clinic Facility Roster',
                                    style: TextStyle(
                                      fontSize: isMobile ? 16 : 19,
                                      fontWeight: FontWeight.bold,
                                      color: _kPrimaryTealDark,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Configure clinic locations, operating hours, medical specialties, and insurance networks',
                              style: TextStyle(
                                  fontSize: 11, color: _kTextMuted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        key: const Key('add_clinic_btn'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimaryTeal,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 10 : 14,
                            vertical: isMobile ? 7 : 9,
                          ),
                          minimumSize: Size.zero,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6)),
                        ),
                        icon: const Icon(Icons.add, size: 15),
                        label: Text(
                          isMobile ? 'Add' : 'Add Clinic',
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _openClinicDialog(null),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Content: 2-pane on desktop, single pane on mobile
                  Expanded(
                    child: isMobile
                        ? _buildSidebarCard()
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: 340,
                                child: _buildSidebarCard(),
                              ),
                              const SizedBox(width: 16),
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

// ── Real Interactive Leaflet / OpenStreetMap Map Component ────────────────

class _RealBranchMap extends StatefulWidget {
  final double lat;
  final double lng;
  final Function(double, double) onLocationSelected;

  const _RealBranchMap({
    required this.lat,
    required this.lng,
    required this.onLocationSelected,
  });

  @override
  State<_RealBranchMap> createState() => _RealBranchMapState();
}

class _RealBranchMapState extends State<_RealBranchMap> {
  final MapController _mapController = MapController();
  late double _currentLat;
  late double _currentLng;
  double _zoom = 14.0;

  @override
  void initState() {
    super.initState();
    _currentLat = widget.lat;
    _currentLng = widget.lng;
  }

  @override
  void didUpdateWidget(covariant _RealBranchMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lat != widget.lat || oldWidget.lng != widget.lng) {
      setState(() {
        _currentLat = widget.lat;
        _currentLng = widget.lng;
      });
      _mapController.move(
          LatLng(widget.lat, widget.lng), math.max(_zoom, 14.0));
    }
  }

  void _zoomIn() {
    setState(() {
      _zoom = math.min(18.0, _zoom + 1.0);
      _mapController.move(LatLng(_currentLat, _currentLng), _zoom);
    });
  }

  void _zoomOut() {
    setState(() {
      _zoom = math.max(3.0, _zoom - 1.0);
      _mapController.move(LatLng(_currentLat, _currentLng), _zoom);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(_currentLat, _currentLng),
              initialZoom: _zoom,
              minZoom: 2.0,
              maxZoom: 19.0,
              onTap: (tapPosition, point) {
                FocusScope.of(context).unfocus();
                setState(() {
                  _currentLat = point.latitude;
                  _currentLng = point.longitude;
                });
                widget.onLocationSelected(point.latitude, point.longitude);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.medconsult.qa',
                maxZoom: 19,
                panBuffer: 1,
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(_currentLat, _currentLng),
                    width: 44,
                    height: 52,
                    alignment: Alignment.topCenter,
                    child: Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        // Pulse Ring
                        Container(
                          width: 38,
                          height: 38,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _kPrimaryTeal.withValues(alpha: 0.25),
                          ),
                        ),
                        // Pin badge
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _kPrimaryTeal,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x40000000),
                                blurRadius: 6,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        // Pin Pointer Dot
                        Positioned(
                          bottom: 2,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: _kPrimaryTealDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Zoom Controls matching Leaflet
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kBorderColor),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x18000000),
                      blurRadius: 4,
                      offset: Offset(0, 2))
                ],
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: _zoomIn,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.add, size: 16, color: _kTextMain),
                    ),
                  ),
                  const Divider(height: 1, color: _kBorderColor),
                  InkWell(
                    onTap: _zoomOut,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.remove, size: 16, color: _kTextMain),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Attribution
          Positioned(
            bottom: 4,
            right: 6,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: _kBorderColor.withValues(alpha: 0.6)),
              ),
              child: const Text(
                '© OpenStreetMap contributors',
                style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w500,
                    color: _kTextMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

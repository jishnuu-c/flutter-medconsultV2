import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/localization/language_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/references_service.dart';
import '../../../core/utils/image_utils.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../clinic_admin/data/doctor_models.dart';
import '../../clinic_admin/data/clinic_service.dart';
import '../../clinic_admin/data/clinic_models.dart';

/// Turns a relative avatar path into an absolute URL.
String? _resolveAvatarUrl(String? raw) => resolveImageUrl(raw);

String _displayDoctorName(String fullName) {
  final trimmed = fullName.trim();
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('dr') ||
      lower.startsWith('doctor') ||
      lower.startsWith('prof') ||
      lower.startsWith('consultant') ||
      lower.startsWith('specialist') ||
      trimmed.startsWith('د.')) {
    return trimmed;
  }
  return 'Dr. $trimmed';
}

String _initialsOf(String name) {
  if (name.trim().isEmpty) return 'DR';
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
  return name.trim().substring(0, name.trim().length.clamp(0, 2)).toUpperCase();
}

class _Option {
  final String id;
  final String label;
  const _Option(this.id, this.label);
}

class _EnrichedDoctor {
  final DoctorModel doctor;
  final List<String> specialtyIds;
  final List<String> languageIds;
  final List<String> cityIds;
  final String initials;
  final Color avatarBg;
  final Color avatarFg;

  _EnrichedDoctor({
    required this.doctor,
    required this.specialtyIds,
    required this.languageIds,
    required this.cityIds,
    required this.initials,
    required this.avatarBg,
    required this.avatarFg,
  });
}

class PatientDoctorsScreen extends ConsumerStatefulWidget {
  const PatientDoctorsScreen({super.key});

  @override
  ConsumerState<PatientDoctorsScreen> createState() =>
      _PatientDoctorsScreenState();
}

class _C {
  static const avatarBg = [
    Color(0xFFE0F2FE),
    Color(0xFFF0FDFA),
    Color(0xFFEDE9FE),
    Color(0xFFFEF3C7),
    Color(0xFFECFDF5),
  ];
  static const avatarFg = [
    Color(0xFF0369A1),
    Color(0xFF0F766E),
    Color(0xFF6D28D9),
    Color(0xFFB45309),
    Color(0xFF047857),
  ];
}

class _PatientDoctorsScreenState extends ConsumerState<PatientDoctorsScreen> {
  bool _isLoading = false;
  List<_EnrichedDoctor> _doctors = [];
  List<SpecialtyModel> _specialties = [];
  List<LanguageModel> _languages = [];
  List<CityModel> _cities = [];
  final _searchController = TextEditingController();

  Set<String> _selectedSpecialtyIds = {};
  Set<String> _selectedCityIds = {};
  double _selectedRating = 0;
  String _selectedLanguageId = '';
  int _minExperience = 0;
  double _maxFee = 500;
  bool _showAdvancedFilters = false;

  @override
  void initState() {
    super.initState();
    _loadDoctors();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDoctors() async {
    setState(() => _isLoading = true);
    try {
      final referenceService = ref.read(referenceServiceProvider);
      final clinicService = ref.read(clinicServiceProvider);
      final doctorService = ref.read(doctorServiceProvider);

      final results = await Future.wait([
        referenceService
            .getAllSpecialties()
            .catchError((_) => <SpecialtyModel>[]),
        referenceService.getAllLanguages().catchError((_) => <LanguageModel>[]),
        referenceService.getAllCities().catchError((_) => <CityModel>[]),
        clinicService.getAllClinics().catchError((_) => <ClinicModel>[]),
        doctorService.getAllDoctors(),
      ]);

      final specialties = results[0] as List<SpecialtyModel>;
      final languages = results[1] as List<LanguageModel>;
      final cities = results[2] as List<CityModel>;
      final clinics = results[3] as List<ClinicModel>;
      final doctors = results[4] as List<DoctorModel>;

      final branchToCityId = <String, String>{};
      if (clinics.isNotEmpty) {
        final branchLists = await Future.wait(clinics.map((c) => clinicService
            .getClinicBranches(c.clinicId)
            .catchError((_) => <ClinicBranchModel>[])));
        for (final branches in branchLists) {
          for (final b in branches) {
            branchToCityId[b.branchId] = b.cityId;
          }
        }
      }

      final enriched =
          await Future.wait(doctors.asMap().entries.map((entry) async {
        final idx = entry.key;
        final doc = entry.value;
        final specs = await doctorService
            .getDoctorSpecialties(doc.doctorId)
            .catchError((_) => <DoctorSpecialtyModel>[]);
        final langs = await doctorService
            .getDoctorLanguages(doc.doctorId)
            .catchError((_) => <DoctorLanguageModel>[]);
        final docClinics = await doctorService
            .getDoctorClinics(doc.doctorId)
            .catchError((_) => <DoctorClinicModel>[]);
        final cityIds = docClinics
            .map((c) => branchToCityId[c.branchId])
            .whereType<String>()
            .toSet()
            .toList();

        return _EnrichedDoctor(
          doctor: doc,
          specialtyIds: specs.map((s) => s.specialtyId).toList(),
          languageIds: langs.map((l) => l.languageId).toList(),
          cityIds: cityIds,
          initials: _initialsOf(doc.fullName),
          avatarBg: _C.avatarBg[idx % _C.avatarBg.length],
          avatarFg: _C.avatarFg[idx % _C.avatarFg.length],
        );
      }));

      if (mounted) {
        setState(() {
          _specialties = specialties;
          _languages = languages;
          _cities = cities;
          _doctors = enriched;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load doctors: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<_EnrichedDoctor> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    return _doctors.where((e) {
      final d = e.doctor;
      if (q.isNotEmpty) {
        final matchesName = d.fullName.toLowerCase().contains(q);
        final matchesBio = (d.bioEn?.toLowerCase().contains(q) ?? false) ||
            (d.bioAr?.toLowerCase().contains(q) ?? false);
        if (!matchesName && !matchesBio) return false;
      }
      if (_selectedSpecialtyIds.isNotEmpty &&
          !e.specialtyIds.any(_selectedSpecialtyIds.contains)) {
        return false;
      }
      if (_selectedCityIds.isNotEmpty &&
          !e.cityIds.any(_selectedCityIds.contains)) {
        return false;
      }
      if (_selectedRating > 0 && d.overallRating < _selectedRating) {
        return false;
      }
      if (_selectedLanguageId.isNotEmpty &&
          !e.languageIds.contains(_selectedLanguageId)) {
        return false;
      }
      if (d.experienceYears < _minExperience) return false;
      if (_maxFee < 500 && d.consultationFeeSar > _maxFee) return false;
      return true;
    }).toList();
  }

  int get _activeFilterCount {
    var n = 0;
    n += _selectedSpecialtyIds.length;
    n += _selectedCityIds.length;
    if (_selectedRating > 0) n++;
    if (_selectedLanguageId.isNotEmpty) n++;
    if (_minExperience > 0) n++;
    if (_maxFee < 500) n++;
    return n;
  }

  List<_Option> get _specialtyOptions {
    final isAr = ref.watch(isArabicProvider);
    return _specialties
        .map((s) => _Option(
            s.specialtyId,
            isAr && s.nameAr.isNotEmpty
                ? s.nameAr
                : (s.nameEn.isNotEmpty ? s.nameEn : 'Specialty'.tr)))
        .toList();
  }

  List<_Option> get _cityOptions {
    final isAr = ref.watch(isArabicProvider);
    return _cities
        .map((c) => _Option(
            c.cityId,
            isAr && c.nameAr.isNotEmpty
                ? c.nameAr
                : (c.nameEn.isNotEmpty ? c.nameEn : 'City'.tr)))
        .toList();
  }

  List<_Option> get _languageOptions {
    final isAr = ref.watch(isArabicProvider);
    return _languages
        .map((l) => _Option(
            l.languageId,
            isAr && l.nameAr.isNotEmpty
                ? l.nameAr
                : (l.nameEn.isNotEmpty ? l.nameEn : 'Language'.tr)))
        .toList();
  }

  String _specialtyName(String id) {
    final isAr = ref.watch(isArabicProvider);
    final match = _specialties.where((s) => s.specialtyId == id);
    if (match.isEmpty) return 'Specialist'.tr;
    return isAr && match.first.nameAr.isNotEmpty
        ? match.first.nameAr
        : match.first.nameEn;
  }

  String _cityName(String id) {
    final isAr = ref.watch(isArabicProvider);
    final match = _cities.where((c) => c.cityId == id);
    if (match.isEmpty) return '';
    return isAr && match.first.nameAr.isNotEmpty
        ? match.first.nameAr
        : match.first.nameEn;
  }

  String _languageName(String id) {
    final isAr = ref.watch(isArabicProvider);
    final match = _languages.where((l) => l.languageId == id);
    if (match.isEmpty) return '';
    return isAr && match.first.nameAr.isNotEmpty
        ? match.first.nameAr
        : match.first.nameEn;
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _selectedSpecialtyIds = {};
      _selectedCityIds = {};
      _selectedRating = 0;
      _selectedLanguageId = '';
      _minExperience = 0;
      _maxFee = 500;
    });
  }

  void _viewDoctorDetails(_EnrichedDoctor doc) {
    context.push('/patient/doctors/${doc.doctor.doctorId}');
  }

  void _bookAppointment(_EnrichedDoctor doc) {
    context.go('/patient/book-appointment');
  }

  void _openMobileFilterDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => _MobileFilterDrawer(
          searchController: _searchController,
          specialtyOptions: _specialtyOptions,
          cityOptions: _cityOptions,
          languageOptions: _languageOptions,
          selectedSpecialtyIds: _selectedSpecialtyIds,
          selectedCityIds: _selectedCityIds,
          selectedRating: _selectedRating,
          selectedLanguageId: _selectedLanguageId,
          minExperience: _minExperience,
          maxFee: _maxFee,
          resultCount: _filtered.length,
          onSearchChanged: () => setSheetState(() {}),
          onSpecialtyChanged: (v) => setSheetState(() {
            setState(() => _selectedSpecialtyIds = v);
          }),
          onCityChanged: (v) => setSheetState(() {
            setState(() => _selectedCityIds = v);
          }),
          onRatingChanged: (v) => setSheetState(() {
            setState(() => _selectedRating = v);
          }),
          onLanguageChanged: (v) => setSheetState(() {
            setState(() => _selectedLanguageId = v);
          }),
          onExperienceChanged: (v) => setSheetState(() {
            setState(() => _minExperience = v);
          }),
          onFeeChanged: (v) => setSheetState(() {
            setState(() => _maxFee = v);
          }),
          onReset: () => setSheetState(() {
            _resetFilters();
          }),
          onShowResults: () => Navigator.of(sheetCtx).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 768;
    final crossAxisCount = width >= 1100 ? 3 : (width >= 768 ? 2 : 1);
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: AppTheme.backgroundApp,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryTeal,
          onRefresh: _loadDoctors,
          child: ListView(
            padding: EdgeInsets.all(isMobile ? 16 : 24),
            children: [
              // 1. Header Banner
              _HeaderBanner(isMobile: isMobile, count: filtered.length),
              const SizedBox(height: 16),

              // 2. Search & Quick Filters
              if (isMobile)
                _MobileSearchRow(
                  controller: _searchController,
                  activeFilterCount: _activeFilterCount,
                  specialties: _specialties,
                  selectedSpecialtyIds: _selectedSpecialtyIds,
                  onSelectSpecialty: (id) {
                    setState(() {
                      if (_selectedSpecialtyIds.contains(id)) {
                        _selectedSpecialtyIds.remove(id);
                      } else {
                        _selectedSpecialtyIds.add(id);
                      }
                    });
                  },
                  onClearAllSpecialties: () =>
                      setState(() => _selectedSpecialtyIds = {}),
                  onChanged: () => setState(() {}),
                  onFilterTap: _openMobileFilterDrawer,
                  selectedCityIds: _selectedCityIds,
                  selectedRating: _selectedRating,
                  selectedLanguageId: _selectedLanguageId,
                  specialtyName: _specialtyName,
                  cityName: _cityName,
                  languageName: _languageName,
                  onClearSpecialty: (id) => setState(
                      () => _selectedSpecialtyIds = {..._selectedSpecialtyIds}..remove(id)),
                  onClearCity: (id) => setState(
                      () => _selectedCityIds = {..._selectedCityIds}..remove(id)),
                  onClearRating: () => setState(() => _selectedRating = 0),
                  onClearLanguage: () =>
                      setState(() => _selectedLanguageId = ''),
                  onClearAll: _resetFilters,
                )
              else
                _DesktopFiltersPanel(
                  controller: _searchController,
                  onChanged: () => setState(() {}),
                  specialtyOptions: _specialtyOptions,
                  cityOptions: _cityOptions,
                  languageOptions: _languageOptions,
                  selectedSpecialtyIds: _selectedSpecialtyIds,
                  selectedCityIds: _selectedCityIds,
                  selectedRating: _selectedRating,
                  selectedLanguageId: _selectedLanguageId,
                  minExperience: _minExperience,
                  maxFee: _maxFee,
                  showAdvanced: _showAdvancedFilters,
                  onToggleAdvanced: () =>
                      setState(() => _showAdvancedFilters = !_showAdvancedFilters),
                  onSpecialtyChanged: (v) =>
                      setState(() => _selectedSpecialtyIds = v),
                  onCityChanged: (v) => setState(() => _selectedCityIds = v),
                  onRatingChanged: (v) => setState(() => _selectedRating = v),
                  onLanguageChanged: (v) =>
                      setState(() => _selectedLanguageId = v),
                  onExperienceChanged: (v) =>
                      setState(() => _minExperience = v),
                  onFeeChanged: (v) => setState(() => _maxFee = v),
                  onReset: _resetFilters,
                ),
              const SizedBox(height: 16),

              // 3. Doctors List / Grid
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryTeal),
                  ),
                )
              else if (filtered.isEmpty)
                _EmptyState(onReset: _resetFilters)
              else if (isMobile)
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 14),
                  itemBuilder: (context, i) {
                    final doc = filtered[i];
                    return _DoctorCard(
                      entry: doc,
                      displayName: _displayDoctorName(doc.doctor.fullName),
                      specialtyNames:
                          doc.specialtyIds.map(_specialtyName).toList(),
                      languageNames:
                          doc.languageIds.map(_languageName).toList(),
                      onViewProfile: () => _viewDoctorDetails(doc),
                      onBook: () => _bookAppointment(doc),
                    );
                  },
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisExtent: 360,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final doc = filtered[i];
                    return _DoctorCard(
                      entry: doc,
                      displayName: _displayDoctorName(doc.doctor.fullName),
                      specialtyNames:
                          doc.specialtyIds.map(_specialtyName).toList(),
                      languageNames:
                          doc.languageIds.map(_languageName).toList(),
                      onViewProfile: () => _viewDoctorDetails(doc),
                      onBook: () => _bookAppointment(doc),
                    );
                  },
                ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header Banner ──────────────────────────────────────────────────────
class _HeaderBanner extends StatelessWidget {
  final bool isMobile;
  final int count;
  const _HeaderBanner({required this.isMobile, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F766E), Color(0xFF115E59)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.medical_services_outlined, size: 12, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      'Specialist'.tr.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF14B8A6).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count ${'Doctors'.tr}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Browse Doctors'.tr,
            style: TextStyle(
              color: Colors.white,
              fontSize: isMobile ? 22 : 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Find and book consultations with certified medical specialists'.tr,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: isMobile ? 12 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mobile Search & Quick Specialty Row ───────────────────────────────────
class _MobileSearchRow extends StatelessWidget {
  final TextEditingController controller;
  final int activeFilterCount;
  final List<SpecialtyModel> specialties;
  final Set<String> selectedSpecialtyIds;
  final ValueChanged<String> onSelectSpecialty;
  final VoidCallback onClearAllSpecialties;
  final VoidCallback onChanged;
  final VoidCallback onFilterTap;
  final Set<String> selectedCityIds;
  final double selectedRating;
  final String selectedLanguageId;
  final String Function(String) specialtyName;
  final String Function(String) cityName;
  final String Function(String) languageName;
  final ValueChanged<String> onClearSpecialty;
  final ValueChanged<String> onClearCity;
  final VoidCallback onClearRating;
  final VoidCallback onClearLanguage;
  final VoidCallback onClearAll;

  const _MobileSearchRow({
    required this.controller,
    required this.activeFilterCount,
    required this.specialties,
    required this.selectedSpecialtyIds,
    required this.onSelectSpecialty,
    required this.onClearAllSpecialties,
    required this.onChanged,
    required this.onFilterTap,
    required this.selectedCityIds,
    required this.selectedRating,
    required this.selectedLanguageId,
    required this.specialtyName,
    required this.cityName,
    required this.languageName,
    required this.onClearSpecialty,
    required this.onClearCity,
    required this.onClearRating,
    required this.onClearLanguage,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceWhite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderGray.withOpacity(0.8)),
                ),
                child: TextField(
                  controller: controller,
                  onChanged: (_) => onChanged(),
                  decoration: InputDecoration(
                    hintText: 'Search doctor name or title...'.tr,
                    hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textMuted),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 16, color: AppTheme.textMuted),
                            onPressed: () {
                              controller.clear();
                              onChanged();
                            },
                          )
                        : null,
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: activeFilterCount > 0 ? AppTheme.primaryLightTeal : AppTheme.surfaceWhite,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onFilterTap,
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: activeFilterCount > 0
                          ? AppTheme.primaryTeal
                          : AppTheme.borderGray.withOpacity(0.8),
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.tune,
                        size: 16,
                        color: activeFilterCount > 0 ? AppTheme.primaryDarkTeal : AppTheme.textMain,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Filter'.tr,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: activeFilterCount > 0 ? AppTheme.primaryDarkTeal : AppTheme.textMain,
                        ),
                      ),
                      if (activeFilterCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryTeal,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$activeFilterCount',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        // Quick Specialty Filter Chips Carousel
        if (specialties.isNotEmpty) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildQuickPill(
                  label: 'All Types'.tr,
                  isSelected: selectedSpecialtyIds.isEmpty,
                  onTap: onClearAllSpecialties,
                ),
                for (final s in specialties.take(8))
                  _buildQuickPill(
                    label: specialtyName(s.specialtyId),
                    isSelected: selectedSpecialtyIds.contains(s.specialtyId),
                    onTap: () => onSelectSpecialty(s.specialtyId),
                  ),
              ],
            ),
          ),
        ],

        // Active Filter Chips
        if (activeFilterCount > 0) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final id in selectedSpecialtyIds)
                  _activeFilterChip('🩺 ${specialtyName(id)}', () => onClearSpecialty(id)),
                for (final id in selectedCityIds)
                  _activeFilterChip('📍 ${cityName(id)}', () => onClearCity(id)),
                if (selectedRating > 0)
                  _activeFilterChip('★ ${selectedRating.toStringAsFixed(1)}+', onClearRating),
                if (selectedLanguageId.isNotEmpty)
                  _activeFilterChip('🗣️ ${languageName(selectedLanguageId)}', onClearLanguage),
                TextButton(
                  onPressed: onClearAll,
                  child: Text('Clear All'.tr,
                      style: const TextStyle(color: AppTheme.dangerRed, fontWeight: FontWeight.bold, fontSize: 11.5)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQuickPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryTeal : AppTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppTheme.primaryTeal : AppTheme.borderGray.withOpacity(0.8),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _activeFilterChip(String label, VoidCallback onRemove) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDFA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF99F6E4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF0F766E), fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 13, color: Color(0xFF0F766E)),
          ),
        ],
      ),
    );
  }
}

// ── Desktop Filters Panel ────────────────────────────────────────────────
class _DesktopFiltersPanel extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;
  final List<_Option> specialtyOptions;
  final List<_Option> cityOptions;
  final List<_Option> languageOptions;
  final Set<String> selectedSpecialtyIds;
  final Set<String> selectedCityIds;
  final double selectedRating;
  final String selectedLanguageId;
  final int minExperience;
  final double maxFee;
  final bool showAdvanced;
  final VoidCallback onToggleAdvanced;
  final ValueChanged<Set<String>> onSpecialtyChanged;
  final ValueChanged<Set<String>> onCityChanged;
  final ValueChanged<double> onRatingChanged;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<int> onExperienceChanged;
  final ValueChanged<double> onFeeChanged;
  final VoidCallback onReset;

  const _DesktopFiltersPanel({
    required this.controller,
    required this.onChanged,
    required this.specialtyOptions,
    required this.cityOptions,
    required this.languageOptions,
    required this.selectedSpecialtyIds,
    required this.selectedCityIds,
    required this.selectedRating,
    required this.selectedLanguageId,
    required this.minExperience,
    required this.maxFee,
    required this.showAdvanced,
    required this.onToggleAdvanced,
    required this.onSpecialtyChanged,
    required this.onCityChanged,
    required this.onRatingChanged,
    required this.onLanguageChanged,
    required this.onExperienceChanged,
    required this.onFeeChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.8)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: (_) => onChanged(),
                  decoration: InputDecoration(
                    hintText: 'Search by doctor name or bio...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: AppTheme.backgroundApp,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: onToggleAdvanced,
                icon: Icon(showAdvanced ? Icons.expand_less : Icons.tune, size: 16),
                label: const Text('Filters'),
              ),
              if (selectedSpecialtyIds.isNotEmpty ||
                  selectedCityIds.isNotEmpty ||
                  selectedRating > 0 ||
                  selectedLanguageId.isNotEmpty) ...[
                const SizedBox(width: 8),
                TextButton(onPressed: onReset, child: const Text('Reset')),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Doctor Card (Mobile Optimized) ─────────────────────────────────────────
class _DoctorCard extends StatelessWidget {
  final _EnrichedDoctor entry;
  final String displayName;
  final List<String> specialtyNames;
  final List<String> languageNames;
  final VoidCallback onViewProfile;
  final VoidCallback onBook;

  const _DoctorCard({
    required this.entry,
    required this.displayName,
    required this.specialtyNames,
    required this.languageNames,
    required this.onViewProfile,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    final doctor = entry.doctor;
    final avatarUrl = _resolveAvatarUrl(doctor.avatarUrl);
    final primarySpecialty = specialtyNames.isNotEmpty ? specialtyNames.first : 'Specialist';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Info Row: Avatar + Title + Rating
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onViewProfile,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: entry.avatarBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0F766E).withOpacity(0.2), width: 1.5),
                  ),
                  child: ClipOval(
                    child: avatarUrl != null
                        ? Image.network(
                            avatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                entry.initials,
                                style: TextStyle(color: entry.avatarFg, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              entry.initials,
                              style: TextStyle(color: entry.avatarFg, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: onViewProfile,
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textMain,
                              ),
                            ),
                          ),
                        ),
                        if (doctor.mohVerified)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.verified, size: 16, color: Color(0xFF0D9488)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      primarySpecialty,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.primaryTeal),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, size: 12, color: Color(0xFFD97706)),
                              const SizedBox(width: 3),
                              Text(
                                '${doctor.overallRating}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '(${doctor.reviewCount})',
                                style: const TextStyle(fontSize: 10, color: Color(0xFFB45309)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${doctor.experienceYears} ${'Years Experience'.tr}',
                          style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Detail Badges
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.payments_outlined, size: 15, color: Color(0xFF059669)),
                  const SizedBox(width: 4),
                  Text(
                    '${doctor.consultationFeeSar.toStringAsFixed(0)} ${'SAR'.tr}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                  ),
                ],
              ),
              if (languageNames.isNotEmpty)
                Text(
                  '🗣️ ${languageNames.take(2).join(', ')}',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onViewProfile,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: const BorderSide(color: AppTheme.borderGray),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('View Profile'.tr, style: const TextStyle(fontSize: 12.5, color: AppTheme.textMain)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onBook,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.calendar_month, size: 14),
                  label: Text('Book'.tr, style: const TextStyle(fontSize: 12.5)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onReset;
  const _EmptyState({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.8)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
            child: const Icon(Icons.search_off, size: 32, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 12),
          Text('No medical experts match your search query.'.tr, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Try adjusting your search filters or click below to clear all preferences.'.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onReset, child: Text('Clear All'.tr)),
        ],
      ),
    );
  }
}

// ── Mobile Filter Drawer ─────────────────────────────────────────────────
class _MobileFilterDrawer extends StatelessWidget {
  final TextEditingController searchController;
  final List<_Option> specialtyOptions;
  final List<_Option> cityOptions;
  final List<_Option> languageOptions;
  final Set<String> selectedSpecialtyIds;
  final Set<String> selectedCityIds;
  final double selectedRating;
  final String selectedLanguageId;
  final int minExperience;
  final double maxFee;
  final int resultCount;
  final VoidCallback onSearchChanged;
  final ValueChanged<Set<String>> onSpecialtyChanged;
  final ValueChanged<Set<String>> onCityChanged;
  final ValueChanged<double> onRatingChanged;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<int> onExperienceChanged;
  final ValueChanged<double> onFeeChanged;
  final VoidCallback onReset;
  final VoidCallback onShowResults;

  const _MobileFilterDrawer({
    required this.searchController,
    required this.specialtyOptions,
    required this.cityOptions,
    required this.languageOptions,
    required this.selectedSpecialtyIds,
    required this.selectedCityIds,
    required this.selectedRating,
    required this.selectedLanguageId,
    required this.minExperience,
    required this.maxFee,
    required this.resultCount,
    required this.onSearchChanged,
    required this.onSpecialtyChanged,
    required this.onCityChanged,
    required this.onRatingChanged,
    required this.onLanguageChanged,
    required this.onExperienceChanged,
    required this.onFeeChanged,
    required this.onReset,
    required this.onShowResults,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(color: AppTheme.borderGray, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Filter Specialists', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text('Medical Specialty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: specialtyOptions.map((s) {
                        final isSel = selectedSpecialtyIds.contains(s.id);
                        return ChoiceChip(
                          label: Text(s.label),
                          selected: isSel,
                          selectedColor: AppTheme.primaryLightTeal,
                          labelStyle: TextStyle(
                            color: isSel ? AppTheme.primaryDarkTeal : AppTheme.textSecondary,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                          onSelected: (val) {
                            final next = Set<String>.from(selectedSpecialtyIds);
                            if (val) {
                              next.add(s.id);
                            } else {
                              next.remove(s.id);
                            }
                            onSpecialtyChanged(next);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    const Text('Minimum Rating', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [0.0, 3.0, 4.0, 4.5].map((r) {
                        final isSel = selectedRating == r;
                        return ChoiceChip(
                          label: Text(r == 0 ? 'Any' : '$r★+'),
                          selected: isSel,
                          selectedColor: AppTheme.primaryLightTeal,
                          labelStyle: TextStyle(
                            color: isSel ? AppTheme.primaryDarkTeal : AppTheme.textSecondary,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                          onSelected: (_) => onRatingChanged(r),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Min Experience', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('$minExperience yrs', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryTeal)),
                      ],
                    ),
                    Slider(
                      value: minExperience.toDouble(),
                      min: 0,
                      max: 30,
                      divisions: 30,
                      activeColor: AppTheme.primaryTeal,
                      onChanged: (v) => onExperienceChanged(v.round()),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Max Fee', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('${maxFee.toStringAsFixed(0)} SAR', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryTeal)),
                      ],
                    ),
                    Slider(
                      value: maxFee,
                      min: 50,
                      max: 500,
                      divisions: 45,
                      activeColor: AppTheme.primaryTeal,
                      onChanged: onFeeChanged,
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(top: BorderSide(color: AppTheme.borderGray)),
                ),
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: onReset,
                      child: const Text('Reset All'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onShowResults,
                        child: Text('Show Results ($resultCount)'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Doctor Profile Bottom Sheet ──────────────────────────────────────────
class _DoctorProfileSheet extends ConsumerStatefulWidget {
  final String doctorId;
  final _EnrichedDoctor fallback;
  final String Function(String) specialtyName;
  final String Function(String) languageName;
  final VoidCallback onBook;

  const _DoctorProfileSheet({
    required this.doctorId,
    required this.fallback,
    required this.specialtyName,
    required this.languageName,
    required this.onBook,
  });

  @override
  ConsumerState<_DoctorProfileSheet> createState() => _DoctorProfileSheetState();
}

class _DoctorProfileSheetState extends ConsumerState<_DoctorProfileSheet> {
  DoctorDetailResponse? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await ref
          .read(doctorServiceProvider)
          .getDoctorProfile(widget.doctorId);
      if (mounted) setState(() => _detail = detail);
    } catch (_) {}
    finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doctor = _detail ?? widget.fallback.doctor;
    final displayName = _displayDoctorName(doctor.fullName);
    final initials = _initialsOf(doctor.fullName);
    final avatarUrl = _resolveAvatarUrl(doctor.avatarUrl);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                decoration: BoxDecoration(color: AppTheme.borderGray, borderRadius: BorderRadius.circular(2)),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: widget.fallback.avatarBg,
                          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl == null
                              ? Text(initials, style: TextStyle(color: widget.fallback.avatarFg, fontWeight: FontWeight.bold, fontSize: 18))
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(displayName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text(
                                doctor.mohVerified ? '✓ MOH Verified License' : 'Verification In Review',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: doctor.mohVerified ? AppTheme.primaryTeal : AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    // Quick Stats Strip
                    Row(
                      children: [
                        Expanded(child: _statItem('Experience', '${doctor.experienceYears} Years', Icons.work_outline)),
                        Expanded(child: _statItem('Rating', '${doctor.overallRating} ★', Icons.star_border)),
                        Expanded(child: _statItem('Fee', '${doctor.consultationFeeSar.toStringAsFixed(0)} SAR', Icons.payments_outlined)),
                      ],
                    ),
                    const SizedBox(height: 18),

                    if (_loading)
                      const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
                    else ...[
                      if (doctor.bioEn != null && doctor.bioEn!.isNotEmpty) ...[
                        const Text('Professional Bio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 6),
                        Text(doctor.bioEn!, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4)),
                        const SizedBox(height: 16),
                      ],

                      if (_detail != null && _detail!.clinics.isNotEmpty) ...[
                        const Text('Associated Clinics', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 8),
                        ..._detail!.clinics.map((c) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.backgroundApp,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.local_hospital_outlined, size: 18, color: AppTheme.primaryTeal),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(c.clinicNameEn ?? 'Clinic', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ],
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.borderGray)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onBook,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: const Text('Book Consultation Now'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundApp,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryTeal),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}

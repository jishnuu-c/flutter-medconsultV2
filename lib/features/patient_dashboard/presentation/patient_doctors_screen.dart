import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/references_service.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../clinic_admin/data/doctor_models.dart';
import '../../clinic_admin/data/clinic_service.dart';
import '../../clinic_admin/data/clinic_models.dart';

/// Turns a relative avatar path returned by the API into an absolute URL
/// NetworkImage can load. Mirrors app_layout.dart's private helper since
/// that one isn't exported.
String? _resolveAvatarUrl(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final value = raw.trim();
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) return value;
  final base = kBaseUrl.endsWith('/')
      ? kBaseUrl.substring(0, kBaseUrl.length - 1)
      : kBaseUrl;
  final path = value.startsWith('/') ? value : '/$value';
  return '$base$path';
}

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

/// A single simple id/label pair used to feed the multi-select and
/// single-select filter widgets below (specialties, cities, languages).
class _Option {
  final String id;
  final String label;
  const _Option(this.id, this.label);
}

/// Doctor + the reference ids resolved for it (specialties, languages,
/// cities via its clinic branches). Mirrors Angular's EnrichedDoctor.
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

/// Mirrors Angular's patient-dashboard/doctors (browse & search doctors).
/// Header banner, search + filters (specialty / city / rating / language /
/// experience / fee), doctor grid, mobile filter drawer, and the doctor
/// profile view are styled and featured to match doctors.component 1:1.
class PatientDoctorsScreen extends ConsumerStatefulWidget {
  const PatientDoctorsScreen({super.key});

  @override
  ConsumerState<PatientDoctorsScreen> createState() =>
      _PatientDoctorsScreenState();
}

// Extra brand tokens from styles.css not yet in AppTheme.
class _C {
  static const tealDark = Color(0xFF085041); // --teal-d
  static const tealMid = Color(0xFF0F6E56); // --teal-m
  static const tealLight = Color(0xFFE1F5EE); // --teal-l
  static const off = Color(0xFFF8FAF9); // --off
  static const t3 = Color(0xFF6B7280); // --t3
  static const border2 = Color(0xFFD1D5DB); // --border2
  static const feeBg = Color(0xFFECFDF5);
  static const feeText = Color(0xFF065F46);
  static const ratingBg = Color(0xFFFEF3C7);
  static const ratingText = Color(0xFF92400E);
  static const chipBorder = Color(0xFFA7F3D0);

  static const avatarBg = [
    Color(0xFFE1F5EE),
    Color(0xFFDBEAFE),
    Color(0xFFEDE9FE),
    Color(0xFFFEF3C7),
    Color(0xFFDCFCE7),
  ];
  static const avatarFg = [
    Color(0xFF085041),
    Color(0xFF1E40AF),
    Color(0xFF5B21B6),
    Color(0xFF92400E),
    Color(0xFF166534),
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

      // Map every clinic branch to its city, so a doctor's clinic
      // placements can be resolved to filterable city ids.
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

  List<_Option> get _specialtyOptions => _specialties
      .map((s) =>
          _Option(s.specialtyId, s.nameEn.isNotEmpty ? s.nameEn : 'Specialty'))
      .toList();

  List<_Option> get _cityOptions => _cities
      .map((c) => _Option(c.cityId, c.nameEn.isNotEmpty ? c.nameEn : 'City'))
      .toList();

  List<_Option> get _languageOptions => _languages
      .map((l) =>
          _Option(l.languageId, l.nameEn.isNotEmpty ? l.nameEn : 'Language'))
      .toList();

  String _specialtyName(String id) {
    final match = _specialties.where((s) => s.specialtyId == id);
    return match.isNotEmpty ? match.first.nameEn : 'Specialist';
  }

  String _cityName(String id) {
    final match = _cities.where((c) => c.cityId == id);
    return match.isNotEmpty ? match.first.nameEn : '';
  }

  String _languageName(String id) {
    final match = _languages.where((l) => l.languageId == id);
    return match.isNotEmpty ? match.first.nameEn : '';
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DoctorProfileSheet(
        doctorId: doc.doctor.doctorId,
        fallback: doc,
        specialtyName: _specialtyName,
        languageName: _languageName,
        onBook: () {
          Navigator.of(context).pop();
          context.go('/patient/book-appointment');
        },
      ),
    );
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

    return RefreshIndicator(
      onRefresh: _loadDoctors,
      child: ListView(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        children: [
          _HeaderBanner(isMobile: isMobile),
          const SizedBox(height: 20),
          if (isMobile)
            _MobileSearchRow(
              controller: _searchController,
              activeFilterCount: _activeFilterCount,
              onChanged: () => setState(() {}),
              onFilterTap: _openMobileFilterDrawer,
              selectedSpecialtyIds: _selectedSpecialtyIds,
              selectedCityIds: _selectedCityIds,
              selectedRating: _selectedRating,
              selectedLanguageId: _selectedLanguageId,
              specialtyName: _specialtyName,
              cityName: _cityName,
              languageName: _languageName,
              onClearSpecialty: (id) => setState(() => _selectedSpecialtyIds = {
                    ..._selectedSpecialtyIds
                  }..remove(id)),
              onClearCity: (id) => setState(
                  () => _selectedCityIds = {..._selectedCityIds}..remove(id)),
              onClearRating: () => setState(() => _selectedRating = 0),
              onClearLanguage: () => setState(() => _selectedLanguageId = ''),
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
              onLanguageChanged: (v) => setState(() => _selectedLanguageId = v),
              onExperienceChanged: (v) => setState(() => _minExperience = v),
              onFeeChanged: (v) => setState(() => _maxFee = v),
              onReset: _resetFilters,
            ),
          const SizedBox(height: 20),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                  child:
                      CircularProgressIndicator(color: AppTheme.primaryTeal)),
            )
          else if (filtered.isEmpty)
            _EmptyState(onReset: _resetFilters)
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisExtent: 340,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final doc = filtered[i];
                return _DoctorCard(
                  entry: doc,
                  displayName: _displayDoctorName(doc.doctor.fullName),
                  specialtyNames: doc.specialtyIds.map(_specialtyName).toList(),
                  languageNames: doc.languageIds.map(_languageName).toList(),
                  onViewProfile: () => _viewDoctorDetails(doc),
                  onBook: () => _bookAppointment(doc),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ── Header Banner ──────────────────────────────────────────────────────
class _HeaderBanner extends StatelessWidget {
  final bool isMobile;
  const _HeaderBanner({required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 20 : 36, vertical: isMobile ? 20 : 32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_C.tealDark, _C.tealMid],
        ),
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        boxShadow: [
          BoxShadow(
              color: AppTheme.primaryTeal.withOpacity(0.25),
              blurRadius: 24,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: const Text('MEDICAL SPECIALIST DIRECTORY',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
          ),
          const SizedBox(height: 12),
          Text('Browse Doctors',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: isMobile ? 24 : 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text(
            'Find and book consultations with top medical experts near you',
            style: TextStyle(
                color: _C.tealLight, fontSize: isMobile ? 13 : 15, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ── Reusable multi-select trigger + bottom sheet ────────────────────────
Future<void> _openMultiSelect({
  required BuildContext context,
  required String title,
  required List<_Option> options,
  required Set<String> selected,
  required ValueChanged<Set<String>> onChanged,
}) async {
  final result = await showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MultiSelectSheet(
        title: title, options: options, initialSelected: selected),
  );
  if (result != null) onChanged(result);
}

Widget _multiSelectField({
  required BuildContext context,
  required String placeholder,
  required List<_Option> options,
  required Set<String> selected,
  required ValueChanged<Set<String>> onChanged,
}) {
  final label = selected.isEmpty
      ? placeholder
      : selected
          .map((id) => options
              .firstWhere((o) => o.id == id, orElse: () => _Option(id, id))
              .label)
          .join(', ');
  return Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openMultiSelect(
        context: context,
        title: placeholder,
        options: options,
        selected: selected,
        onChanged: onChanged,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _C.off,
          border: Border.all(color: AppTheme.borderGray),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      color: selected.isEmpty ? _C.t3 : AppTheme.textMain)),
            ),
            const Icon(Icons.keyboard_arrow_down, size: 18, color: _C.t3),
          ],
        ),
      ),
    ),
  );
}

class _MultiSelectSheet extends StatefulWidget {
  final String title;
  final List<_Option> options;
  final Set<String> initialSelected;

  const _MultiSelectSheet({
    required this.title,
    required this.options,
    required this.initialSelected,
  });

  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late Set<String> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSelected};
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.options
        .where((o) => o.label.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(widget.title,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
              ),
              if (widget.options.length > 6)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      prefixIcon:
                          const Icon(Icons.search, size: 18, color: _C.t3),
                      filled: true,
                      fillColor: _C.off,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppTheme.borderGray)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppTheme.borderGray)),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: AppTheme.borderGray),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text('No results',
                            style: TextStyle(color: _C.t3, fontSize: 13)))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final o = filtered[i];
                          final checked = _selected.contains(o.id);
                          return CheckboxListTile(
                            value: checked,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: AppTheme.primaryTeal,
                            title: Text(o.label,
                                style: const TextStyle(fontSize: 13.5)),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(o.id);
                              } else {
                                _selected.remove(o.id);
                              }
                            }),
                          );
                        },
                      ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                    20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(top: BorderSide(color: AppTheme.borderGray)),
                ),
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: () => setState(() => _selected.clear()),
                      child: const Text('Clear',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(_selected),
                        child: const Text('Apply',
                            style: TextStyle(fontWeight: FontWeight.w700)),
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

// ── Mobile search row + active chips ────────────────────────────────────
class _MobileSearchRow extends StatelessWidget {
  final TextEditingController controller;
  final int activeFilterCount;
  final VoidCallback onChanged;
  final VoidCallback onFilterTap;
  final Set<String> selectedSpecialtyIds;
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
    required this.onChanged,
    required this.onFilterTap,
    required this.selectedSpecialtyIds,
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
              child: TextField(
                controller: controller,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  hintText: 'Search doctor name...',
                  hintStyle: const TextStyle(fontSize: 14, color: _C.t3),
                  prefixIcon: const Icon(Icons.search, size: 20, color: _C.t3),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.borderGray)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.borderGray)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onFilterTap,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: _C.border2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tune,
                          size: 16, color: Color(0xFF0F172A)),
                      const SizedBox(width: 6),
                      const Text('Filter',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A))),
                      if (activeFilterCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryTeal,
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Text('$activeFilterCount',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (activeFilterCount > 0) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final id in selectedSpecialtyIds)
                  _chip('🩺 ${specialtyName(id)}', () => onClearSpecialty(id)),
                for (final id in selectedCityIds)
                  _chip('📍 ${cityName(id)}', () => onClearCity(id)),
                if (selectedRating > 0)
                  _chip(
                      '★ ${selectedRating.toStringAsFixed(selectedRating.truncateToDouble() == selectedRating ? 0 : 1)}+',
                      onClearRating),
                if (selectedLanguageId.isNotEmpty)
                  _chip('🗣️ ${languageName(selectedLanguageId)}',
                      onClearLanguage),
                TextButton(
                  onPressed: onClearAll,
                  child: const Text('Clear All',
                      style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _chip(String label, VoidCallback onRemove) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _C.feeBg,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: _C.chipBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  color: _C.feeText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            child: const Text('✕',
                style: TextStyle(
                    color: _C.feeText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ── Desktop filters panel ───────────────────────────────────────────────
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.borderGray),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final perRow = constraints.maxWidth >= 900
                ? 4
                : (constraints.maxWidth >= 560 ? 2 : 1);
            const spacing = 20.0;
            final itemWidth =
                (constraints.maxWidth - spacing * (perRow - 1)) / perRow;

            final fields = [
              _labeled(
                'Search Doctor Name',
                TextField(
                  controller: controller,
                  onChanged: (_) => onChanged(),
                  decoration: InputDecoration(
                    hintText: 'Type to search...',
                    hintStyle: const TextStyle(fontSize: 13.5),
                    suffixIcon:
                        const Icon(Icons.search, size: 18, color: _C.t3),
                    filled: true,
                    fillColor: _C.off,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: AppTheme.borderGray)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: AppTheme.borderGray)),
                  ),
                ),
              ),
              _labeled(
                'Medical Specialty',
                _multiSelectField(
                  context: context,
                  placeholder: 'All Specialties',
                  options: specialtyOptions,
                  selected: selectedSpecialtyIds,
                  onChanged: onSpecialtyChanged,
                ),
              ),
              _labeled(
                'Location / City',
                _multiSelectField(
                  context: context,
                  placeholder: 'All Cities',
                  options: cityOptions,
                  selected: selectedCityIds,
                  onChanged: onCityChanged,
                ),
              ),
              _labeled(
                'Minimum Rating',
                _ratingDropdown(selectedRating, onRatingChanged),
              ),
            ];

            return Wrap(
              spacing: spacing,
              runSpacing: 16,
              children: [
                for (final f in fields) SizedBox(width: itemWidth, child: f),
              ],
            );
          }),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onToggleAdvanced,
              icon: Icon(showAdvanced ? Icons.expand_less : Icons.tune,
                  size: 16, color: _C.tealMid),
              label: const Text('Advanced Filters',
                  style: TextStyle(
                      color: _C.tealMid,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: showAdvanced
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.only(top: 20),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.borderGray)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _labeled(
                            'Spoken Language',
                            _languageDropdown(languageOptions,
                                selectedLanguageId, onLanguageChanged),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _labeled(
                            'Min Experience  ·  $minExperience Years',
                            Slider(
                              value: minExperience.toDouble(),
                              min: 0,
                              max: 30,
                              divisions: 30,
                              activeColor: AppTheme.primaryTeal,
                              onChanged: (v) => onExperienceChanged(v.round()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _labeled(
                            'Max Consultation Fee  ·  ${maxFee.toStringAsFixed(0)} SAR',
                            Slider(
                              value: maxFee,
                              min: 50,
                              max: 500,
                              divisions: 45,
                              activeColor: AppTheme.primaryTeal,
                              onChanged: onFeeChanged,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: onReset,
                        icon: const Icon(Icons.refresh, size: 15),
                        label: const Text('Reset Filters',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _labeled(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _ratingDropdown(double value, ValueChanged<double> onChanged) {
    const options = [0.0, 3.0, 4.0, 4.5];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _C.off,
        border: Border.all(color: AppTheme.borderGray),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<double>(
          value: options.contains(value) ? value : 0.0,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: _C.t3),
          items: options
              .map((v) => DropdownMenuItem(
                    value: v,
                    child: Text(v == 0 ? 'Any Rating' : '$v ★ & up',
                        style: const TextStyle(fontSize: 13.5)),
                  ))
              .toList(),
          onChanged: (v) => onChanged(v ?? 0),
        ),
      ),
    );
  }

  Widget _languageDropdown(
      List<_Option> options, String value, ValueChanged<String> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _C.off,
        border: Border.all(color: AppTheme.borderGray),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: _C.t3),
          items: [
            const DropdownMenuItem(
                value: '',
                child: Text('All Languages', style: TextStyle(fontSize: 13.5))),
            ...options.map((o) => DropdownMenuItem(
                value: o.id,
                child: Text(o.label, style: const TextStyle(fontSize: 13.5)))),
          ],
          onChanged: (v) => onChanged(v ?? ''),
        ),
      ),
    );
  }
}

// ── Mobile bottom sheet filter drawer ───────────────────────────────────
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
      initialChildSize: 0.75,
      minChildSize: 0.4,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Filter Specialists',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppTheme.borderGray),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text('Search Doctor Name',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: searchController,
                      onChanged: (_) => onSearchChanged(),
                      decoration: InputDecoration(
                        hintText: 'Type doctor name...',
                        filled: true,
                        fillColor: _C.off,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: AppTheme.borderGray)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('Medical Specialty',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 8),
                    _multiSelectField(
                      context: context,
                      placeholder: 'All Specialties',
                      options: specialtyOptions,
                      selected: selectedSpecialtyIds,
                      onChanged: onSpecialtyChanged,
                    ),
                    const SizedBox(height: 20),
                    const Text('Location / City',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 8),
                    _multiSelectField(
                      context: context,
                      placeholder: 'All Cities',
                      options: cityOptions,
                      selected: selectedCityIds,
                      onChanged: onCityChanged,
                    ),
                    const SizedBox(height: 20),
                    const Text('Minimum Rating',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [0.0, 3.0, 4.0, 4.5].map((r) {
                        final selected = selectedRating == r;
                        return ChoiceChip(
                          label: Text(r == 0 ? 'Any' : '$r★+'),
                          selected: selected,
                          selectedColor: AppTheme.primaryLightTeal,
                          labelStyle: TextStyle(
                              color: selected
                                  ? _C.tealDark
                                  : AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5),
                          onSelected: (_) => onRatingChanged(r),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    const Text('Spoken Language',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Any'),
                          selected: selectedLanguageId.isEmpty,
                          selectedColor: AppTheme.primaryLightTeal,
                          labelStyle: TextStyle(
                              color: selectedLanguageId.isEmpty
                                  ? _C.tealDark
                                  : AppTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5),
                          onSelected: (_) => onLanguageChanged(''),
                        ),
                        for (final o in languageOptions)
                          ChoiceChip(
                            label: Text(o.label),
                            selected: selectedLanguageId == o.id,
                            selectedColor: AppTheme.primaryLightTeal,
                            labelStyle: TextStyle(
                                color: selectedLanguageId == o.id
                                    ? _C.tealDark
                                    : AppTheme.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5),
                            onSelected: (_) => onLanguageChanged(o.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Text('🎓 Min Experience',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                        const Spacer(),
                        Text('$minExperience Years',
                            style: const TextStyle(
                                color: AppTheme.primaryTeal,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5)),
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
                      children: [
                        const Text('💰 Max Consultation Fee',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                        const Spacer(),
                        Text('${maxFee.toStringAsFixed(0)} SAR',
                            style: const TextStyle(
                                color: AppTheme.primaryTeal,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5)),
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
                padding: EdgeInsets.fromLTRB(
                    20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(top: BorderSide(color: AppTheme.borderGray)),
                ),
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: onReset,
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14)),
                      child: const Text('Reset All',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onShowResults,
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: Text('Show Doctors ($resultCount)',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
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

// ── Doctor Card ───────────────────────────────────────────────────────
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.borderGray),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  GestureDetector(
                    onTap: onViewProfile,
                    child: avatarUrl != null
                        ? CircleAvatar(
                            radius: 34,
                            backgroundColor: entry.avatarBg,
                            backgroundImage: NetworkImage(avatarUrl),
                            onBackgroundImageError: (_, __) {},
                          )
                        : CircleAvatar(
                            radius: 34,
                            backgroundColor: entry.avatarBg,
                            child: Text(entry.initials,
                                style: TextStyle(
                                    color: entry.avatarFg,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18)),
                          ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _C.feeBg,
                      border: Border.all(color: const Color(0x2605966A)),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Text(
                        '${doctor.consultationFeeSar.toStringAsFixed(0)} SAR',
                        style: const TextStyle(
                            color: _C.feeText,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: onViewProfile,
                      child: Text(displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: _C.tealDark,
                              fontWeight: FontWeight.w700,
                              fontSize: 15.5)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: specialtyNames.isEmpty
                          ? [
                              _specialtyBadge('General Practitioner',
                                  filled: false)
                            ]
                          : specialtyNames
                              .take(3)
                              .map((n) => _specialtyBadge(n, filled: true))
                              .toList(),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _C.ratingBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star,
                              size: 12, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 4),
                          Text('${doctor.overallRating}',
                              style: const TextStyle(
                                  color: _C.ratingText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 3),
                          Text('(${doctor.reviewCount} reviews)',
                              style: const TextStyle(
                                  color: Color(0xFFB45309), fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.badge_outlined, size: 14, color: _C.t3),
              const SizedBox(width: 6),
              const Text('Experience: ',
                  style:
                      TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
              Text('${doctor.experienceYears} Years',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary)),
            ],
          ),
          if (languageNames.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.language, size: 14, color: _C.t3),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(languageNames.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppTheme.textSecondary)),
                ),
              ],
            ),
          ],
          const Spacer(),
          Container(
            padding: const EdgeInsets.only(top: 14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.borderGray)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onViewProfile,
                    icon: const Icon(Icons.person_outline, size: 15),
                    label: const Text('View Profile',
                        style: TextStyle(fontSize: 12.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _C.tealMid,
                      side: const BorderSide(color: _C.border2),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onBook,
                    icon: const Icon(Icons.calendar_today_outlined, size: 14),
                    label: const Text('Book', style: TextStyle(fontSize: 12.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _specialtyBadge(String label, {required bool filled}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: filled ? _C.tealLight : _C.off,
        border: filled ? null : Border.all(color: AppTheme.borderGray),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: filled ? _C.tealDark : _C.t3)),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onReset;
  const _EmptyState({required this.onReset});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.border2, style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          const Icon(Icons.search_off, size: 40, color: _C.t3),
          const SizedBox(height: 12),
          const Text('No Doctors Found',
              style: TextStyle(
                  color: _C.tealDark,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Try adjusting your search filters or click below to clear all preferences.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _C.t3, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Show All Doctors'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12)),
          ),
        ],
      ),
    );
  }
}

// ── Doctor profile bottom sheet (View Profile) ─────────────────────────
// Fetches the full DoctorDetailResponse (bio, specialties, spoken
// languages, associated clinics/branches, qualifications) the same way
// Angular's doctor-detail page does, instead of only showing the handful
// of fields available on the list-row DoctorModel.
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
  ConsumerState<_DoctorProfileSheet> createState() =>
      _DoctorProfileSheetState();
}

class _DoctorProfileSheetState extends ConsumerState<_DoctorProfileSheet> {
  DoctorDetailResponse? _detail;
  bool _loading = true;
  String? _error;

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
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load full profile.');
    } finally {
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
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppTheme.borderGray,
                    borderRadius: BorderRadius.circular(4)),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: widget.fallback.avatarBg,
                          backgroundImage: avatarUrl != null
                              ? NetworkImage(avatarUrl)
                              : null,
                          onBackgroundImageError:
                              avatarUrl != null ? (_, __) {} : null,
                          child: avatarUrl == null
                              ? Text(initials,
                                  style: TextStyle(
                                      color: widget.fallback.avatarFg,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18))
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(displayName,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                      doctor.mohVerified
                                          ? Icons.verified
                                          : Icons.hourglass_bottom,
                                      size: 13,
                                      color: doctor.mohVerified
                                          ? AppTheme.primaryTeal
                                          : _C.t3),
                                  const SizedBox(width: 4),
                                  Text(
                                      doctor.mohVerified
                                          ? 'MOH Verified License'
                                          : 'MOH Verification Pending',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: doctor.mohVerified
                                              ? AppTheme.primaryTeal
                                              : _C.t3)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (_detail != null &&
                                  _detail!.specialties.isNotEmpty)
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _detail!.specialties
                                      .map((s) => Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: _C.tealLight,
                                              borderRadius:
                                                  BorderRadius.circular(9999),
                                            ),
                                            child: Text(
                                                widget.specialtyName(
                                                    s.specialtyId),
                                                style: const TextStyle(
                                                    color: _C.tealDark,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ))
                                      .toList(),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Quick stats strip.
                    Row(
                      children: [
                        Expanded(
                            child: _statCell(
                                Icons.schedule,
                                '${doctor.experienceYears} Years',
                                'Experience')),
                        Expanded(
                            child: _statCell(
                                Icons.star,
                                '${doctor.overallRating} / 5.0',
                                '${doctor.reviewCount} reviews')),
                        Expanded(
                            child: _statCell(
                                Icons.payments_outlined,
                                '${doctor.consultationFeeSar.toStringAsFixed(0)} SAR',
                                'Consultation Fee')),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.primaryTeal)),
                      )
                    else ...[
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Color(0xFFEF4444), fontSize: 12.5)),
                        ),
                      if ((doctor.bioEn != null &&
                          doctor.bioEn!.trim().isNotEmpty)) ...[
                        _sectionTitle('Professional Biography'),
                        const SizedBox(height: 6),
                        Text(doctor.bioEn!,
                            style:
                                const TextStyle(fontSize: 13.5, height: 1.5)),
                        const SizedBox(height: 18),
                      ],
                      if (_detail != null) ...[
                        _sectionTitle('Associated Clinics & Locations'),
                        const SizedBox(height: 8),
                        if (_detail!.clinics.isEmpty)
                          _emptyNote(
                              'No registered clinical locations assigned.')
                        else
                          ..._detail!.clinics.map((cl) => _clinicTile(cl)),
                        const SizedBox(height: 18),
                        _sectionTitle('Academic Qualifications'),
                        const SizedBox(height: 8),
                        if (_detail!.qualifications.isEmpty)
                          _emptyNote(
                              'No qualifications recorded on profile file.')
                        else
                          ..._detail!.qualifications
                              .map((q) => _qualificationTile(q)),
                        const SizedBox(height: 18),
                        _sectionTitle('Spoken Languages'),
                        const SizedBox(height: 8),
                        if (_detail!.languages.isEmpty)
                          _emptyNote('No languages documented.')
                        else
                          ..._detail!.languages.map((l) => _languageTile(l)),
                        const SizedBox(height: 18),
                      ],
                    ],
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                    24, 12, 24, 16 + MediaQuery.of(context).padding.bottom),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.borderGray)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onBook,
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Book Consultation'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statCell(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryTeal),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, color: _C.t3)),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text,
        style: const TextStyle(
            fontSize: 14.5, fontWeight: FontWeight.w700, color: _C.tealDark));
  }

  Widget _emptyNote(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _C.off,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12.5, color: _C.t3)),
    );
  }

  Widget _clinicTile(DoctorClinicModel cl) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _C.off,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(cl.clinicNameEn ?? 'Clinic Location',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5)),
              ),
              if (cl.isPrimary)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: _C.feeBg,
                      borderRadius: BorderRadius.circular(9999)),
                  child: const Text('Primary',
                      style: TextStyle(
                          color: _C.feeText,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(cl.branchNameEn ?? 'Main Branch',
              style: const TextStyle(fontSize: 12, color: _C.t3)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text('Department: ${cl.department}',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.textSecondary)),
              Text('Fee: ${cl.consultationFeeSar.toStringAsFixed(0)} SAR',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qualificationTile(DoctorQualificationModel q) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _C.off,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Row(
        children: [
          const Icon(Icons.school_outlined, size: 18, color: _C.tealMid),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(q.degree,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                Text('${q.institution}, ${q.country}',
                    style: const TextStyle(fontSize: 11.5, color: _C.t3)),
              ],
            ),
          ),
          Text('${q.yearObtained}',
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: _C.tealMid)),
        ],
      ),
    );
  }

  Widget _languageTile(DoctorLanguageModel l) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.language, size: 15, color: _C.t3),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.languageName(l.languageId),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                border: Border.all(color: AppTheme.primaryTeal),
                borderRadius: BorderRadius.circular(9999)),
            child: Text(l.proficiency.value,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryTeal)),
          ),
        ],
      ),
    );
  }
}

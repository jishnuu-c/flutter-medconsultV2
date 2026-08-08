import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/auth_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/references_service.dart';
import '../../clinic_admin/data/clinic_models.dart';
import '../../clinic_admin/data/clinic_service.dart';
import '../../clinic_admin/data/doctor_models.dart';
import '../../clinic_admin/data/doctor_service.dart';

// ─────────────────────────────────────────────────────────────────────────
// Display models — mirror Angular's ClinicCardDisplay / DoctorCardDisplay
// (landing.component.ts), built from the REAL ClinicService / DoctorService
// / ReferenceService that already exist in this codebase (clinic_admin/data
// + core/services) — reused here rather than duplicated.
// ─────────────────────────────────────────────────────────────────────────

class DoctorCardDisplay {
  final DoctorModel doctor;
  final String clinicId;
  final String dcId;
  final String branchName;
  String nextSlot;
  String avail; // today | tomorrow | busy | loading

  DoctorCardDisplay({
    required this.doctor,
    required this.clinicId,
    required this.dcId,
    this.branchName = '',
    this.nextSlot = 'Checking slots…',
    this.avail = 'loading',
  });
}

class ClinicCardDisplay {
  final ClinicModel clinic;
  final ClinicDetailResponse? detail;
  final String cityName;
  final String area;
  final List<String> specNames;
  final List<String> insuranceNames;
  final List<DoctorCardDisplay> doctors;

  ClinicCardDisplay({
    required this.clinic,
    required this.detail,
    required this.cityName,
    required this.area,
    required this.specNames,
    required this.insuranceNames,
    required this.doctors,
  });
}

class LandingData {
  final List<SpecialtyModel> specialties;
  final List<CityModel> cities;
  final List<InsuranceProviderModel> insurances;
  final List<ClinicCardDisplay> clinics;

  LandingData({
    required this.specialties,
    required this.cities,
    required this.insurances,
    required this.clinics,
  });
}

// Loads real data the same way Angular's loadAllRealData() /
// processRealClinicsAndDoctors() do: specialties, cities, insurances,
// clinics + detail, doctors + their active clinic links — all via the
// existing services, not new ones.
final landingDataProvider = FutureProvider<LandingData>((ref) async {
  final clinicSvc = ref.watch(clinicServiceProvider);
  final doctorSvc = ref.watch(doctorServiceProvider);
  final refSvc = ref.watch(referenceServiceProvider);

  final results = await Future.wait([
    refSvc.getAllSpecialties().catchError((_) => <SpecialtyModel>[]),
    refSvc.getAllCities().catchError((_) => <CityModel>[]),
    refSvc
        .getAllInsuranceProviders()
        .catchError((_) => <InsuranceProviderModel>[]),
    clinicSvc.getAllClinics().catchError((_) => <ClinicModel>[]),
    doctorSvc.getAllDoctors().catchError((_) => <DoctorModel>[]),
  ]);

  final specialties = results[0] as List<SpecialtyModel>;
  final cities = results[1] as List<CityModel>;
  final insurances = results[2] as List<InsuranceProviderModel>;
  final rawClinics = results[3] as List<ClinicModel>;
  final rawDoctors = results[4] as List<DoctorModel>;

  // Active clinic links per doctor.
  final Map<String, List<DoctorClinicModel>> doctorLinks = {};
  await Future.wait(rawDoctors.map((doc) async {
    final links = await doctorSvc
        .getDoctorClinics(doc.doctorId)
        .catchError((_) => <DoctorClinicModel>[]);
    doctorLinks[doc.doctorId] = links.where((l) => l.isActive).toList();
  }));

  // Detail (branches/specialties/insurance) per clinic.
  final details = await Future.wait(rawClinics.map(
    (c) => clinicSvc
        .getClinicDetail(c.clinicId)
        .then<ClinicDetailResponse?>((d) => d)
        .catchError((_) => null),
  ));

  final clinicCards = <ClinicCardDisplay>[];
  for (var i = 0; i < rawClinics.length; i++) {
    final c = rawClinics[i];
    final detail = details[i];
    ClinicBranchModel? primaryBranch;
    if (detail != null && detail.branches.isNotEmpty) {
      primaryBranch = detail.branches.firstWhere(
        (b) => b.isPrimary,
        orElse: () => detail.branches.first,
      );
    }
    final cityId = primaryBranch?.cityId ??
        (cities.isNotEmpty ? cities[i % cities.length].cityId : '');
    final cityName = cities
        .firstWhere((ct) => ct.cityId == cityId,
            orElse: () =>
                CityModel(cityId: '', nameEn: 'Saudi Arabia', nameAr: ''))
        .nameEn;
    final area = (primaryBranch?.addressLine1.isNotEmpty ?? false)
        ? primaryBranch!.addressLine1
        : cityName;

    final specNames = (detail?.specialties ?? <ClinicSpecialtyModel>[])
        .map((s) => specialties
            .firstWhere((x) => x.specialtyId == s.specialtyId,
                orElse: () =>
                    SpecialtyModel(specialtyId: '', nameEn: '', nameAr: ''))
            .nameEn)
        .where((n) => n.isNotEmpty)
        .toList();

    final insNames = {
      for (final ins in (detail?.insurances ?? <ClinicInsuranceModel>[])
          .where((i) => i.isActive))
        insurances
            .firstWhere((x) => x.providerId == ins.providerId,
                orElse: () => InsuranceProviderModel(
                    providerId: '', nameEn: '', nameAr: ''))
            .nameEn
    }.where((n) => n.isNotEmpty).toList();

    // Doctors linked to this clinic via active doctor-clinic assignments.
    final docCards = <DoctorCardDisplay>[];
    for (final doc in rawDoctors) {
      final links = doctorLinks[doc.doctorId] ?? [];
      for (final link in links.where((l) => l.clinicId == c.clinicId)) {
        final branch = detail?.branches.firstWhere(
          (b) => b.branchId == link.branchId,
          orElse: () => ClinicBranchModel(
              branchId: '',
              clinicId: '',
              branchNameEn: '',
              branchNameAr: '',
              cityId: '',
              addressLine1: '',
              isPrimary: false,
              isActive: true),
        );
        docCards.add(DoctorCardDisplay(
          doctor: doc,
          clinicId: c.clinicId,
          dcId: link.dcId,
          branchName: branch?.branchNameEn ?? '',
        ));
      }
    }

    clinicCards.add(ClinicCardDisplay(
      clinic: c,
      detail: detail,
      cityName: cityName,
      area: area,
      specNames: specNames,
      insuranceNames: insNames,
      doctors: docCards,
    ));
  }

  // Fire-and-forget: fetch real next-available-slot per doctor (mirrors
  // fetchRealSlotsForLandingDoctors in Angular) without blocking first paint.
  // getAvailableSlots returns raw json (List<dynamic>) — no dedicated slot
  // model exists yet in doctor_service.dart, so fields are read directly.
  for (final card in clinicCards) {
    for (final doc in card.doctors) {
      if (doc.dcId.isEmpty) {
        doc
          ..nextSlot = 'No open slots'
          ..avail = 'busy';
        continue;
      }
      doctorSvc.getAvailableSlots(doc.dcId).then((raw) {
        final available = raw
            .map((e) => e as Map<String, dynamic>)
            .where((e) =>
                (e['status']?.toString().toUpperCase() ?? '') == 'AVAILABLE')
            .toList()
          ..sort((a, b) {
            final d = (a['slotDate']?.toString() ?? '')
                .compareTo(b['slotDate']?.toString() ?? '');
            return d != 0
                ? d
                : (a['startTime']?.toString() ?? '')
                    .compareTo(b['startTime']?.toString() ?? '');
          });
        if (available.isEmpty) {
          doc
            ..nextSlot = 'No open slots'
            ..avail = 'busy';
          return;
        }
        final first = available.first;
        final slotDate = first['slotDate']?.toString() ?? '';
        final startTime = first['startTime']?.toString() ?? '';
        final today = DateTime.now();
        final todayStr =
            '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        final tomorrow = today.add(const Duration(days: 1));
        final tomorrowStr =
            '${tomorrow.year.toString().padLeft(4, '0')}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
        final time = _formatSlotTime(startTime);
        if (slotDate == todayStr) {
          doc
            ..nextSlot = 'Today $time'
            ..avail = 'today';
        } else if (slotDate == tomorrowStr) {
          doc
            ..nextSlot = 'Tomorrow $time'
            ..avail = 'tomorrow';
        } else {
          doc
            ..nextSlot = '$slotDate $time'
            ..avail = 'tomorrow';
        }
      }).catchError((_) {
        doc
          ..nextSlot = 'No open slots'
          ..avail = 'busy';
      });
    }
  }

  return LandingData(
    specialties: specialties,
    cities: cities,
    insurances: insurances,
    clinics: clinicCards,
  );
});

String _formatSlotTime(String timeStr) {
  final parts = timeStr.split(':');
  if (parts.length < 2) return timeStr;
  var hours = int.tryParse(parts[0]) ?? 0;
  final minutes = parts[1];
  final ampm = hours >= 12 ? 'PM' : 'AM';
  hours = hours % 12;
  hours = hours == 0 ? 12 : hours;
  return '$hours:$minutes $ampm';
}

// ─────────────────────────────────────────────────────────────────────────

class LandingScreen extends ConsumerStatefulWidget {
  const LandingScreen({super.key});

  @override
  ConsumerState<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends ConsumerState<LandingScreen> {
  final _searchController = TextEditingController();
  String? _selectedSpecialtyId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showBookingDialog(DoctorCardDisplay doc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Book Appointment with Dr. ${doc.doctor.fullName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (doc.doctor.consultationFeeSar > 0)
              Text(
                  'Consultation Fee: SAR ${doc.doctor.consultationFeeSar.toStringAsFixed(0)}'),
            const SizedBox(height: 4),
            Text('Next Available Slot: ${doc.nextSlot}'),
            const SizedBox(height: 16),
            const Text(
              'Please log in as a Patient to confirm appointment booking.',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go('/login');
            },
            child: const Text('Login to Book'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.currentUser;
    final landingAsync = ref.watch(landingDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MedConsult V2 Public Portal'),
        actions: [
          if (authState.isLoggedIn && user != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onPressed: () {
                  switch (user.role) {
                    case UserRole.PATIENT:
                      context.go('/patient/home');
                      break;
                    case UserRole.DOCTOR:
                      context.go('/doctor/schedule');
                      break;
                    case UserRole.CLINIC_ADMIN:
                      context.go('/clinic-admin/clinics');
                      break;
                    case UserRole.SYSTEM_ADMIN:
                      context.go('/system-admin');
                      break;
                  }
                },
                child: Text('Dashboard (${user.fullName})'),
              ),
            )
          else ...[
            TextButton(
              key: const Key('landing_login_btn'),
              onPressed: () => context.go('/login'),
              child: const Text('Sign In'),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ElevatedButton(
                key: const Key('landing_register_btn'),
                onPressed: () => context.go('/register'),
                child: const Text('Get Started'),
              ),
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(landingDataProvider.future),
        child: landingAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, st) => ListView(
            children: [
              const SizedBox(height: 120),
              Icon(Icons.wifi_off, size: 40, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              const Center(
                  child: Text('Could not load clinics. Pull to retry.')),
              const SizedBox(height: 4),
              Center(
                child: Text('$err',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted)),
              ),
            ],
          ),
          data: (data) => _buildContent(data),
        ),
      ),
    );
  }

  Widget _buildContent(LandingData data) {
    final query = _searchController.text.trim().toLowerCase();
    final filteredClinics = data.clinics.where((c) {
      final matchesQuery = query.isEmpty ||
          c.clinic.nameEn.toLowerCase().contains(query) ||
          c.doctors.any((d) => d.doctor.fullName.toLowerCase().contains(query));
      final matchesSpec = _selectedSpecialtyId == null ||
          (c.detail?.specialties
                  .any((s) => s.specialtyId == _selectedSpecialtyId) ??
              false);
      return matchesQuery && matchesSpec;
    }).toList();

    return ListView(
      children: [
        // Hero + search
        Container(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          color: AppTheme.darkSidebar,
          child: Column(
            children: [
              const Text(
                'Find a clinic. Connect with the right doctor.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Search verified private clinics — browse doctors by specialty and availability.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    const Icon(Icons.search, color: AppTheme.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: const Key('landing_search_input'),
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'Search doctor, specialty, or clinic...',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          fillColor: Colors.transparent,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    ElevatedButton(
                      key: const Key('landing_search_btn'),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      onPressed: () => setState(() {}),
                      child: const Text('Search'),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Specialty filter chips (real specialties from API)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Browse by Specialty',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _selectedSpecialtyId == null,
                    selectedColor: AppTheme.primaryTeal,
                    labelStyle: TextStyle(
                      color: _selectedSpecialtyId == null
                          ? Colors.white
                          : AppTheme.textMain,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (_) =>
                        setState(() => _selectedSpecialtyId = null),
                  ),
                  ...data.specialties.map((spec) {
                    final isSelected = _selectedSpecialtyId == spec.specialtyId;
                    return ChoiceChip(
                      label: Text(spec.nameEn),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryTeal,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppTheme.textMain,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (selected) => setState(() =>
                          _selectedSpecialtyId =
                              selected ? spec.specialtyId : null),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 32),
              Text('Verified Medical Clinics (${filteredClinics.length})',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (filteredClinics.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                      child: Text(
                          'No medical clinics found matching your current filters.')),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredClinics.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) => _ClinicCard(
                      clinic: filteredClinics[index],
                      onBook: _showBookingDialog),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClinicCard extends StatefulWidget {
  final ClinicCardDisplay clinic;
  final void Function(DoctorCardDisplay) onBook;

  const _ClinicCard({required this.clinic, required this.onBook});

  @override
  State<_ClinicCard> createState() => _ClinicCardState();
}

class _ClinicCardState extends State<_ClinicCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.clinic;
    final visibleDoctors = _expanded ? c.doctors : c.doctors.take(3).toList();
    final logoUrl = c.clinic.logoUrl ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLightTeal,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: logoUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(logoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.local_hospital,
                                  color: AppTheme.primaryDarkTeal)),
                        )
                      : const Icon(Icons.local_hospital,
                          color: AppTheme.primaryDarkTeal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.clinic.nameEn,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 12, color: AppTheme.textMuted),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(c.area.isNotEmpty ? c.area : c.cityName,
                                style: const TextStyle(
                                    fontSize: 12, color: AppTheme.textMuted),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.star,
                                size: 14, color: AppTheme.warningAmber),
                            Text(
                                ' ${c.clinic.overallRating.toStringAsFixed(1)} (${c.clinic.reviewCount})',
                                style: const TextStyle(
                                    fontSize: 11, color: AppTheme.textMuted)),
                          ]),
                          if (c.clinic.mohVerified)
                            _Badge(
                                text: 'MOH Verified',
                                color: AppTheme.primaryTeal),
                          if (c.clinic.isActive)
                            _Badge(
                                text: 'Active', color: AppTheme.successGreen),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (c.specNames.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: c.specNames
                    .map((s) => _Tag(text: s, color: AppTheme.infoBlue))
                    .toList(),
              ),
            ],
            if (c.insuranceNames.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: c.insuranceNames
                    .map((s) => _Tag(text: s, color: AppTheme.primaryDarkTeal))
                    .toList(),
              ),
            ],
            if (visibleDoctors.isNotEmpty) ...[
              const Divider(height: 24),
              ...visibleDoctors
                  .map((doc) => _DoctorTile(doc: doc, onBook: widget.onBook)),
            ],
            if (c.doctors.length > 3)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded
                      ? 'Show fewer doctors ▲'
                      : 'Show more doctors at this facility ▼'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DoctorTile extends StatelessWidget {
  final DoctorCardDisplay doc;
  final void Function(DoctorCardDisplay) onBook;

  const _DoctorTile({required this.doc, required this.onBook});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: AppTheme.primaryLightTeal,
            child: Text(
              doc.doctor.fullName.trim().isEmpty
                  ? 'DR'
                  : doc.doctor.fullName
                      .trim()
                      .split(RegExp(r'\s+'))
                      .map((e) => e.isNotEmpty ? e[0] : '')
                      .take(2)
                      .join()
                      .toUpperCase(),
              style: const TextStyle(
                  color: AppTheme.primaryTeal,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dr. ${doc.doctor.fullName}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                    '${doc.doctor.experienceYears} yrs exp · SAR ${doc.doctor.consultationFeeSar.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted)),
                Text(doc.nextSlot,
                    style: TextStyle(
                        fontSize: 11,
                        color: doc.avail == 'busy'
                            ? AppTheme.dangerRed
                            : AppTheme.successGreen)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(0, 30),
                textStyle: const TextStyle(fontSize: 12)),
            onPressed: () => onBook(doc),
            child: const Text('Book'),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4)),
      child: Text(text,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 10.5, color: color)),
    );
  }
}

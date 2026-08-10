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
import '../../../core/network/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────
// Display models
// ─────────────────────────────────────────────────────────────────────────

class DoctorCardDisplay {
  final DoctorModel doctor;
  final String clinicId;
  final String dcId;
  final String branchId;
  final String branchName;
  String nextSlot;
  String avail; // today | tomorrow | busy | loading

  DoctorCardDisplay({
    required this.doctor,
    required this.clinicId,
    required this.dcId,
    this.branchId = '',
    this.branchName = '',
    this.nextSlot = 'Checking slots…',
    this.avail = 'loading',
  });
}

class BranchCardDisplay {
  final String branchId;
  final String branchNameEn;
  final String branchNameAr;
  final String? addressLine1;
  final bool isPrimary;
  final List<DoctorCardDisplay> doctors;

  BranchCardDisplay({
    required this.branchId,
    required this.branchNameEn,
    required this.branchNameAr,
    this.addressLine1,
    this.isPrimary = false,
    required this.doctors,
  });
}

class ClinicCardDisplay {
  final ClinicModel clinic;
  final ClinicDetailResponse? detail;
  final String cityName;
  final String area;
  final List<String> specNames;
  final List<String> insuranceNames;
  final List<String> languageNames;
  final List<DoctorCardDisplay> doctors;
  final List<BranchCardDisplay> branchesWithDocs;

  ClinicCardDisplay({
    required this.clinic,
    required this.detail,
    required this.cityName,
    required this.area,
    required this.specNames,
    required this.insuranceNames,
    required this.languageNames,
    required this.doctors,
    required this.branchesWithDocs,
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

// ─────────────────────────────────────────────────────────────────────────
// Data provider — mirrors Angular loadAllRealData + processRealClinicsAndDoctors
// ─────────────────────────────────────────────────────────────────────────

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
    refSvc.getAllLanguages().catchError((_) => <LanguageModel>[]),
    clinicSvc.getAllClinics().catchError((_) => <ClinicModel>[]),
    doctorSvc.getAllDoctors().catchError((_) => <DoctorModel>[]),
  ]);

  final specialties = results[0] as List<SpecialtyModel>;
  final cities = results[1] as List<CityModel>;
  final insurances = results[2] as List<InsuranceProviderModel>;
  final languages = results[3] as List<LanguageModel>;
  final rawClinics = results[4] as List<ClinicModel>;
  final rawDoctors = results[5] as List<DoctorModel>;

  // Active clinic links per doctor
  final Map<String, List<DoctorClinicModel>> doctorLinks = {};
  await Future.wait(rawDoctors.map((doc) async {
    final links = await doctorSvc
        .getDoctorClinics(doc.doctorId)
        .catchError((_) => <DoctorClinicModel>[]);
    doctorLinks[doc.doctorId] = links.where((l) => l.isActive).toList();
  }));

  // Clinic details
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
    final cityObj = cities.firstWhere(
      (ct) => ct.cityId == cityId,
      orElse: () => CityModel(cityId: '', nameEn: 'Saudi Arabia', nameAr: ''),
    );
    final cityName = cityObj.nameEn;
    final area = (primaryBranch?.addressLine1 ?? '').isNotEmpty
        ? primaryBranch!.addressLine1
        : cityName;

    final specNames = (detail?.specialties ?? <ClinicSpecialtyModel>[])
        .map((s) => specialties
            .firstWhere(
              (x) => x.specialtyId == s.specialtyId,
              orElse: () =>
                  SpecialtyModel(specialtyId: '', nameEn: '', nameAr: ''),
            )
            .nameEn)
        .where((n) => n.isNotEmpty)
        .toList();

    final insNames = {
      for (final ins in (detail?.insurances ?? <ClinicInsuranceModel>[])
          .where((ins) => ins.isActive))
        insurances
            .firstWhere(
              (x) => x.providerId.toLowerCase() == ins.providerId.toLowerCase(),
              orElse: () => InsuranceProviderModel(
                  providerId: '', nameEn: '', nameAr: ''),
            )
            .nameEn
    }.where((n) => n.isNotEmpty).toList();

    final langNames = (detail?.languages ?? <ClinicLanguageModel>[])
        .map((l) => languages
            .firstWhere(
              (x) => x.languageId == l.languageId,
              orElse: () =>
                  LanguageModel(languageId: '', nameEn: '', nameAr: ''),
            )
            .nameEn)
        .where((n) => n.isNotEmpty)
        .toList();

    // Doctors linked to this clinic
    final allMatchedDoctors = <DoctorCardDisplay>[];
    for (final doc in rawDoctors) {
      final links = doctorLinks[doc.doctorId] ?? [];
      for (final link in links.where((l) => l.clinicId == c.clinicId)) {
        String branchName = '';
        if (detail != null) {
          final branch = detail.branches
              .where((b) => b.branchId == link.branchId)
              .firstOrNull;
          branchName = branch?.branchNameEn ?? '';
        }
        allMatchedDoctors.add(DoctorCardDisplay(
          doctor: doc,
          clinicId: c.clinicId,
          dcId: link.dcId,
          branchId: link.branchId,
          branchName: branchName.isNotEmpty ? branchName : 'Main Branch',
        ));
      }
    }

    // Group into BranchCardDisplay (mirrors Angular branchesWithDocs)
    final branchesWithDocs = <BranchCardDisplay>[];
    if (detail != null && detail.branches.isNotEmpty) {
      for (final branch in detail.branches) {
        final docsInBranch = allMatchedDoctors
            .where((d) => d.branchId == branch.branchId)
            .toList();
        if (docsInBranch.isNotEmpty) {
          branchesWithDocs.add(BranchCardDisplay(
            branchId: branch.branchId,
            branchNameEn: branch.branchNameEn,
            branchNameAr: branch.branchNameAr,
            addressLine1: branch.addressLine1,
            isPrimary: branch.isPrimary,
            doctors: docsInBranch,
          ));
        }
      }
      // Orphan doctors (branchId mismatch)
      final mappedBranchIds = detail.branches.map((b) => b.branchId).toSet();
      final orphans = allMatchedDoctors
          .where((d) =>
              d.branchId.isEmpty || !mappedBranchIds.contains(d.branchId))
          .toList();
      if (orphans.isNotEmpty) {
        if (branchesWithDocs.isNotEmpty) {
          branchesWithDocs.first.doctors.addAll(orphans);
        } else {
          final pb = detail.branches.firstWhere(
            (b) => b.isPrimary,
            orElse: () => detail.branches.first,
          );
          branchesWithDocs.add(BranchCardDisplay(
            branchId: pb.branchId,
            branchNameEn: pb.branchNameEn,
            branchNameAr: pb.branchNameAr,
            addressLine1: pb.addressLine1,
            isPrimary: pb.isPrimary,
            doctors: orphans,
          ));
        }
      }
    } else if (allMatchedDoctors.isNotEmpty) {
      branchesWithDocs.add(BranchCardDisplay(
        branchId: 'fallback',
        branchNameEn: 'Main Branch',
        branchNameAr: '',
        isPrimary: true,
        doctors: allMatchedDoctors,
      ));
    }

    clinicCards.add(ClinicCardDisplay(
      clinic: c,
      detail: detail,
      cityName: cityName,
      area: area,
      specNames: specNames.isNotEmpty ? specNames : ['General Practice'],
      insuranceNames: insNames,
      languageNames: langNames.isNotEmpty ? langNames : ['Arabic', 'English'],
      doctors: allMatchedDoctors,
      branchesWithDocs: branchesWithDocs,
    ));
  }

  // Fire-and-forget slot fetch (mirrors fetchRealSlotsForLandingDoctors)
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

String _initials(String fullName) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return 'DR';
  return trimmed
      .split(RegExp(r'\s+'))
      .map((e) => e.isNotEmpty ? e[0] : '')
      .take(2)
      .join()
      .toUpperCase();
}

// ─────────────────────────────────────────────────────────────────────────
// LandingScreen
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

  void _openFacilityDetail(ClinicCardDisplay card) {
    context.go('/patient/clinics/${card.clinic.clinicId}');
  }

  void _showBookingDialog(DoctorCardDisplay doc, String clinicName) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Modal header — matches Angular teal header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: _LandingColors.teal,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Dr. ${doc.doctor.fullName}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$clinicName · ${doc.branchName}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),

            // Modal body
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fee row
                  if (doc.doctor.consultationFeeSar > 0)
                    _InfoRow(
                      icon: Icons.payments_outlined,
                      label:
                          'SAR ${doc.doctor.consultationFeeSar.toStringAsFixed(0)} consultation fee',
                    ),
                  const SizedBox(height: 8),

                  // Experience
                  _InfoRow(
                    icon: Icons.work_history_outlined,
                    label: '${doc.doctor.experienceYears} years experience',
                  ),
                  const SizedBox(height: 8),

                  // Next slot
                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: doc.avail == 'busy'
                            ? _LandingColors.red
                            : _LandingColors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        doc.nextSlot,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: doc.avail == 'today'
                              ? _LandingColors.green
                              : doc.avail == 'tomorrow'
                                  ? _LandingColors.teal
                                  : _LandingColors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Info box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _LandingColors.tealLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 14, color: _LandingColors.tealDark),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sign in as a Patient to confirm appointment booking.',
                            style: TextStyle(
                                fontSize: 12,
                                color: _LandingColors.tealDark,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side:
                                const BorderSide(color: _LandingColors.border),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            context.go('/login');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _LandingColors.teal,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Login to Book →',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.currentUser;
    final landingAsync = ref.watch(landingDataProvider);

    return Scaffold(
      backgroundColor: _LandingColors.off,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shadowColor: Colors.black.withOpacity(0.06),
        title: Image.asset(
          'lib/assets/images/logo.png',
          height: 40,
          fit: BoxFit.contain,
        ),
        actions: [
          if (authState.isLoggedIn && user != null) ...[
            TextButton.icon(
              icon: const Icon(Icons.dashboard_outlined, size: 16),
              label: const Text('Dashboard'),
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
            ),
          ] else ...[
            TextButton(
              key: const Key('landing_login_btn'),
              onPressed: () => context.go('/login'),
              child: const Text('Sign In',
                  style: TextStyle(color: _LandingColors.textMain)),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton(
                key: const Key('landing_register_btn'),
                onPressed: () => context.go('/register'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _LandingColors.teal,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('Get Started',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        color: _LandingColors.teal,
        onRefresh: () => ref.refresh(landingDataProvider.future),
        child: landingAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: _LandingColors.teal)),
          error: (err, _) => ListView(
            children: [
              const SizedBox(height: 120),
              const Icon(Icons.wifi_off,
                  size: 40, color: _LandingColors.textMuted),
              const SizedBox(height: 12),
              const Center(
                  child: Text('Could not load clinics. Pull to retry.',
                      style: TextStyle(color: _LandingColors.textMuted))),
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
          c.cityName.toLowerCase().contains(query) ||
          c.specNames.any((s) => s.toLowerCase().contains(query)) ||
          c.doctors.any((d) => d.doctor.fullName.toLowerCase().contains(query));
      final matchesSpec = _selectedSpecialtyId == null ||
          (c.detail?.specialties
                  .any((s) => s.specialtyId == _selectedSpecialtyId) ??
              false);
      return matchesQuery && matchesSpec;
    }).toList();

    return ListView(
      children: [
        // ── Hero ──
        _HeroSection(
            searchController: _searchController,
            onSearch: () => setState(() {})),

        // ── Specialty chips ──
        _SpecialtyBar(
          specialties: data.specialties,
          selectedId: _selectedSpecialtyId,
          onSelect: (id) => setState(() => _selectedSpecialtyId = id),
        ),

        // ── Results ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Verified Medical Clinics',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _LandingColors.textMain,
                            letterSpacing: -0.3),
                      ),
                      Text(
                        'Showing: ${filteredClinics.length} clinics',
                        style: const TextStyle(
                            fontSize: 12, color: _LandingColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (filteredClinics.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _LandingColors.border),
                  ),
                  child: const Text(
                    'No medical clinics found matching your current filters.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _LandingColors.textMuted),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredClinics.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) => _ClinicCard(
                    clinic: filteredClinics[index],
                    onBook: _showBookingDialog,
                    onViewFacility: _openFacilityDetail,
                  ),
                ),
            ],
          ),
        ),

        // ── How it works ──
        const _HowItWorksSection(),

        // ── Features ──
        const _FeaturesSection(),

        // ── CTA + Footer ──
        const _CtaFooterSection(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Hero section
// ─────────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final TextEditingController searchController;
  final VoidCallback onSearch;

  const _HeroSection({required this.searchController, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 36),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A1F15), Color(0xFF0F3024), Color(0xFF0D4535)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          // Eyebrow
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '🇸🇦 MOH-Aligned · Saudi Arabia',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'Find a clinic.\nConnect with the right doctor.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Search verified private clinics across Saudi Arabia. Browse doctors, filter by specialty, city, language, and book real appointments online.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 24),

          // Trust pills
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: const [
              _TrustPill('✓ MOH Verified'),
              _TrustPill('✓ Real-time Schedules'),
              _TrustPill('✓ HIPAA Compliant'),
              _TrustPill('✓ Arabic & English'),
            ],
          ),
          const SizedBox(height: 28),

          // Search bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                )
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.search,
                    color: _LandingColors.textMuted, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('landing_search_input'),
                    controller: searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search doctor, specialty, or clinic...',
                      hintStyle: TextStyle(
                          color: _LandingColors.textMuted, fontSize: 13),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => onSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  key: const Key('landing_search_btn'),
                  onPressed: onSearch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _LandingColors.teal,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  child: const Text('Search',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustPill extends StatelessWidget {
  final String text;
  const _TrustPill(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white60, fontSize: 10.5)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Specialty filter bar
// ─────────────────────────────────────────────────────────────────────────

class _SpecialtyBar extends StatelessWidget {
  final List<SpecialtyModel> specialties;
  final String? selectedId;
  final void Function(String?) onSelect;

  const _SpecialtyBar(
      {required this.specialties,
      required this.selectedId,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Browse by Specialty',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _LandingColors.textMain),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _SpecChip(
                  label: 'All',
                  selected: selectedId == null,
                  onTap: () => onSelect(null),
                ),
                const SizedBox(width: 8),
                ...specialties.map((spec) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _SpecChip(
                        label: spec.nameEn,
                        selected: selectedId == spec.specialtyId,
                        onTap: () => onSelect(selectedId == spec.specialtyId
                            ? null
                            : spec.specialtyId),
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SpecChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _LandingColors.teal : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _LandingColors.teal : _LandingColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : _LandingColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Clinic card — mirrors Angular clinic-card
// ─────────────────────────────────────────────────────────────────────────

class _ClinicCard extends StatefulWidget {
  final ClinicCardDisplay clinic;
  final void Function(DoctorCardDisplay, String) onBook;
  final void Function(ClinicCardDisplay) onViewFacility;

  const _ClinicCard(
      {required this.clinic,
      required this.onBook,
      required this.onViewFacility});

  @override
  State<_ClinicCard> createState() => _ClinicCardState();
}

class _ClinicCardState extends State<_ClinicCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.clinic;
    final rawLogoUrl = c.clinic.logoUrl ?? '';
    final logoUrl = rawLogoUrl.isNotEmpty
        ? (rawLogoUrl.startsWith('http')
            ? rawLogoUrl
            : '$kBaseUrl${rawLogoUrl.startsWith('/') ? '' : '/'}$rawLogoUrl')
        : '';

    print('LOGOOOOOOOOOOOOO:$logoUrl');
    final totalDoctors = c.doctors.length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _LandingColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _LandingColors.tealLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: logoUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            logoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.local_hospital,
                                color: _LandingColors.tealDark,
                                size: 24),
                          ),
                        )
                      : const Icon(Icons.local_hospital,
                          color: _LandingColors.tealDark, size: 24),
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: GestureDetector(
                    onTap: () => widget.onViewFacility(c),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.clinic.nameEn,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _LandingColors.textMain,
                              letterSpacing: -0.2),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.location_on,
                                size: 11, color: _LandingColors.textMuted),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                c.area.isNotEmpty ? c.area : c.cityName,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: _LandingColors.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Rating + badges row
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star,
                                    size: 13, color: _LandingColors.amber),
                                Text(
                                  ' ${c.clinic.overallRating.toStringAsFixed(1)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _LandingColors.textMain),
                                ),
                                Text(
                                  ' (${c.clinic.reviewCount} reviews)',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: _LandingColors.textMuted),
                                ),
                              ],
                            ),
                            if (c.clinic.mohVerified)
                              _StatusBadge(
                                label: '✓ MOH Verified',
                                bg: const Color(0xFFE1F5EE),
                                fg: _LandingColors.tealDark,
                              ),
                            if (c.clinic.isActive)
                              _StatusBadge(
                                label: '● Active',
                                bg: const Color(0xFFDCFCE7),
                                fg: _LandingColors.green,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // City + action
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      c.cityName,
                      style: const TextStyle(
                          fontSize: 11, color: _LandingColors.textMuted),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton(
                      onPressed: () => widget.onViewFacility(c),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _LandingColors.teal),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'View Facility →',
                        style: TextStyle(
                            fontSize: 11,
                            color: _LandingColors.teal,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Metadata groups ──
          if (c.specNames.isNotEmpty ||
              c.insuranceNames.isNotEmpty ||
              c.languageNames.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  const Divider(height: 1, color: _LandingColors.border),
                  const SizedBox(height: 10),
                  if (c.specNames.isNotEmpty)
                    _MetaGroupRow(
                      label: 'Specialties:',
                      children: c.specNames
                          .map((s) => _TagChip(
                                text: s,
                                bg: const Color(0xFFE1F5EE),
                                fg: const Color(0xFF085041),
                                borderColor: const Color(0xFFA3E6CD),
                              ))
                          .toList(),
                    ),
                  if (c.insuranceNames.isNotEmpty)
                    _MetaGroupRow(
                      label: 'Insurance:',
                      children: c.insuranceNames
                          .map((s) => _TagChip(
                                text: s,
                                bg: const Color(0xFFEEF2FF),
                                fg: const Color(0xFF3730A3),
                                borderColor: const Color(0xFFC7D2FE),
                              ))
                          .toList(),
                    )
                  else
                    _MetaGroupRow(
                      label: 'Insurance:',
                      children: [
                        _TagChip(
                          text: 'Self-Pay / Direct',
                          bg: const Color(0xFFF3F4F6),
                          fg: const Color(0xFF4B5563),
                          borderColor: const Color(0xFFD1D5DB),
                        )
                      ],
                    ),
                  if (c.languageNames.isNotEmpty)
                    _MetaGroupRow(
                      label: 'Languages:',
                      children: c.languageNames
                          .map((s) => _TagChip(
                                text: s,
                                bg: const Color(0xFFF9FAFB),
                                fg: const Color(0xFF374151),
                                borderColor: const Color(0xFFE5E7EB),
                              ))
                          .toList(),
                    ),
                ],
              ),
            ),

          // ── Doctors grouped by branch ──
          if (c.doctors.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _LandingColors.off,
                border: Border(
                  top: BorderSide(color: _LandingColors.border),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 14, color: _LandingColors.tealDark),
                  const SizedBox(width: 6),
                  Text(
                    '$totalDoctors specialist doctor(s) at this facility',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _LandingColors.tealDark),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: c.branchesWithDocs.map((branch) {
                  final docsToShow = _expanded
                      ? branch.doctors
                      : branch.doctors
                          .where((d) => c.doctors.indexOf(d) < 3)
                          .toList();
                  if (docsToShow.isEmpty) return const SizedBox.shrink();
                  return _BranchGroup(
                    branch: branch,
                    doctors: docsToShow,
                    clinicName: c.clinic.nameEn,
                    onBook: widget.onBook,
                  );
                }).toList(),
              ),
            ),
          ],

          // ── Expand toggle ──
          if (totalDoctors > 3)
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: _LandingColors.off,
                  border: Border(top: BorderSide(color: _LandingColors.border)),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(14)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _expanded
                          ? 'Show fewer doctors ▲'
                          : 'Show more doctors at this facility ▼',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _LandingColors.teal),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Branch group with header + doctor list
// ─────────────────────────────────────────────────────────────────────────

class _BranchGroup extends StatelessWidget {
  final BranchCardDisplay branch;
  final List<DoctorCardDisplay> doctors;
  final String clinicName;
  final void Function(DoctorCardDisplay, String) onBook;

  const _BranchGroup({
    required this.branch,
    required this.doctors,
    required this.clinicName,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.location_on,
                size: 12, color: _LandingColors.tealDark),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                branch.branchNameEn,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _LandingColors.tealDark),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _LandingColors.tealLight,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${branch.doctors.length} doctor(s)',
                style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: _LandingColors.tealDark),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Divider(height: 1, color: _LandingColors.border),
        ...doctors.map((doc) => _DoctorTile(
              doc: doc,
              clinicName: clinicName,
              onBook: onBook,
            )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Doctor tile — mirrors Angular doc-mini
// ─────────────────────────────────────────────────────────────────────────

class _DoctorTile extends StatelessWidget {
  final DoctorCardDisplay doc;
  final String clinicName;
  final void Function(DoctorCardDisplay, String) onBook;

  const _DoctorTile(
      {required this.doc, required this.clinicName, required this.onBook});

  @override
  Widget build(BuildContext context) {
    final rawAvatarUrl = doc.doctor.avatarUrl ?? '';
    final avatarUrl = rawAvatarUrl.isNotEmpty
        ? (rawAvatarUrl.startsWith('http')
            ? rawAvatarUrl
            : '$kBaseUrl${rawAvatarUrl.startsWith('/') ? '' : '/'}$rawAvatarUrl')
        : '';
    final initials = _initials(doc.doctor.fullName);

    // Avail color — matches Angular: today=green, tomorrow=teal, busy=red
    final Color availColor;
    switch (doc.avail) {
      case 'today':
        availColor = _LandingColors.green;
        break;
      case 'tomorrow':
        availColor = _LandingColors.teal;
        break;
      default:
        availColor = _LandingColors.red;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: _LandingColors.tealLight,
            backgroundImage:
                avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            onBackgroundImageError: avatarUrl.isNotEmpty ? (_, __) {} : null,
            child: avatarUrl.isEmpty
                ? Text(
                    initials,
                    style: const TextStyle(
                        color: _LandingColors.teal,
                        fontWeight: FontWeight.w800,
                        fontSize: 12),
                  )
                : null,
          ),
          const SizedBox(width: 10),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dr. ${doc.doctor.fullName}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _LandingColors.textMain),
                ),
                const SizedBox(height: 1),
                // Rating + reviews
                Row(
                  children: [
                    const Icon(Icons.star,
                        size: 11, color: _LandingColors.amber),
                    Text(
                      ' ${doc.doctor.overallRating.toStringAsFixed(1)} (${doc.doctor.reviewCount})',
                      style: const TextStyle(
                          fontSize: 10, color: _LandingColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Exp + fee
                Text(
                  '${doc.doctor.experienceYears} yrs exp · SAR ${doc.doctor.consultationFeeSar.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 11, color: _LandingColors.textMuted),
                ),
                const SizedBox(height: 3),
                // Next slot
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 11),
                    children: [
                      const TextSpan(
                        text: 'Next Slot: ',
                        style: TextStyle(color: _LandingColors.textMuted),
                      ),
                      TextSpan(
                        text: doc.nextSlot,
                        style: TextStyle(
                            color: availColor, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Book button
          ElevatedButton(
            onPressed: () => onBook(doc, clinicName),
            style: ElevatedButton.styleFrom(
              backgroundColor: _LandingColors.teal,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              elevation: 0,
            ),
            child: const Text(
              'Book',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// How it works section
// ─────────────────────────────────────────────────────────────────────────

class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _LandingColors.off,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _LandingColors.tealLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('How it works',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _LandingColors.tealDark)),
          ),
          const SizedBox(height: 12),
          const Text(
            'Three steps to your appointment',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _LandingColors.textMain,
                letterSpacing: -0.4),
          ),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(
                  child: _HowStep(
                      num: '1',
                      icon: Icons.local_hospital_outlined,
                      title: 'Search for a clinic',
                      sub:
                          'Search by name, city, specialty or doctor. Filter by ratings, language, insurance.')),
              SizedBox(width: 16),
              Expanded(
                  child: _HowStep(
                      num: '2',
                      icon: Icons.person_search_outlined,
                      title: 'Choose your doctor',
                      sub:
                          'Review credentials, experience, spoken languages, and live open slots.')),
              SizedBox(width: 16),
              Expanded(
                  child: _HowStep(
                      num: '3',
                      icon: Icons.calendar_month_outlined,
                      title: 'Book appointment',
                      sub:
                          'Select preferred date & time slot. Confirm directly into the clinic system.')),
            ],
          ),
        ],
      ),
    );
  }
}

class _HowStep extends StatelessWidget {
  final String num;
  final IconData icon;
  final String title;
  final String sub;

  const _HowStep(
      {required this.num,
      required this.icon,
      required this.title,
      required this.sub});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _LandingColors.tealLight,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(num,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _LandingColors.tealDark)),
          ),
        ),
        const SizedBox(height: 10),
        Icon(icon, color: _LandingColors.teal, size: 26),
        const SizedBox(height: 8),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _LandingColors.textMain)),
        const SizedBox(height: 6),
        Text(sub,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11, color: _LandingColors.textMuted, height: 1.5)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Features section
// ─────────────────────────────────────────────────────────────────────────

class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection();

  static const _features = [
    (
      Icons.chat_outlined,
      'Secure Consultation Chat',
      'Direct doctor-patient messaging with attachment support for medical records.'
    ),
    (
      Icons.group_outlined,
      'Case Discussion Rooms',
      'Multidisciplinary rooms enabling doctors across clinics to collaborate on care.'
    ),
    (
      Icons.science_outlined,
      'Lab Results & Reports',
      'Upload, preview, and download clinical reports with reference range tracking.'
    ),
    (
      Icons.receipt_long_outlined,
      'Digital Prescriptions',
      'Electronically signed prescriptions with pharmacy integration.'
    ),
    (
      Icons.folder_shared_outlined,
      'Unified Health Record',
      'One patient profile across all visits, labs, prescriptions, and clinics.'
    ),
    (
      Icons.lock_outline,
      'Privacy & Security',
      'HIPAA-compliant end-to-end encrypted data storage and transmission.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _LandingColors.tealLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('✦ Platform Features',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _LandingColors.tealDark)),
          ),
          const SizedBox(height: 12),
          const Text(
            'More than booking.\nA complete care platform.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _LandingColors.textMain,
                letterSpacing: -0.4,
                height: 1.2),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connected care across clinics, doctors, and patient records.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, color: _LandingColors.textMuted, height: 1.5),
          ),
          const SizedBox(height: 28),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.82,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _features.length,
            itemBuilder: (_, i) {
              final (icon, title, body) = _features[i];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _LandingColors.off,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _LandingColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _LandingColors.tealLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child:
                          Icon(icon, color: _LandingColors.tealDark, size: 18),
                    ),
                    const SizedBox(height: 10),
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _LandingColors.textMain)),
                    const SizedBox(height: 4),
                    Flexible(
                      child: Text(body,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10.5,
                              color: _LandingColors.textMuted,
                              height: 1.4)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// CTA + Footer
// ─────────────────────────────────────────────────────────────────────────

class _CtaFooterSection extends StatelessWidget {
  const _CtaFooterSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A1F15), Color(0xFF0F3024), Color(0xFF0D4535)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('✦ For Clinics & Doctors',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70)),
          ),
          const SizedBox(height: 16),
          const Text(
            'List your clinic.\nReach more patients.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
                height: 1.1),
          ),
          const SizedBox(height: 10),
          const Text(
            'Join the verified network. Accept online bookings. Manage patient records.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 24),
          // FIX: Row → Wrap so the two CTA buttons no longer overflow on
          // narrow widths (was: fixed-width Row causing "RenderFlex
          // overflowed by 50 pixels on the right").
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton(
                onPressed: () => context.go('/register'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _LandingColors.teal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Sign up / List clinic free →',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              OutlinedButton(
                onPressed: () => context.go('/login'),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Sign in to portal',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 48),
          const Divider(color: Colors.white12),
          const SizedBox(height: 20),
          const Text(
            '© 2025 MedConsult. All rights reserved. Saudi Arabia.',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(height: 4),
          const Text(
            'Saudi MOH Aligned · HIPAA Compliant · Naphies Interoperable',
            style: TextStyle(fontSize: 10, color: Colors.white24),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────

class _MetaGroupRow extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _MetaGroupRow({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: _LandingColors.textMuted)),
          ),
          Expanded(
            child: Wrap(spacing: 5, runSpacing: 4, children: children),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final Color borderColor;

  const _TagChip(
      {required this.text,
      required this.bg,
      required this.fg,
      required this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10.5, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _StatusBadge({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label,
          style:
              TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: _LandingColors.textMuted),
        const SizedBox(width: 8),
        Text(label,
            style:
                const TextStyle(fontSize: 13, color: _LandingColors.textMain)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Color constants — matches Angular CSS variables
// ─────────────────────────────────────────────────────────────────────────

class _LandingColors {
  static const teal = Color(0xFF0D9488);
  static const tealDark = Color(0xFF0F766E);
  static const tealLight = Color(0xFFCCFBF1);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
  static const amber = Color(0xFFF59E0B);
  static const textMain = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF334155);
  static const textMuted = Color(0xFF94A3B8);
  static const border = Color(0xFFE2E8F0);
  static const off = Color(0xFFF8FAFC);
}

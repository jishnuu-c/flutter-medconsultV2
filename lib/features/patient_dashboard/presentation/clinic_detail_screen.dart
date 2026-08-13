import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../clinic_admin/data/clinic_models.dart';
import '../../clinic_admin/data/clinic_service.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../clinic_admin/data/doctor_models.dart';
import '../../../core/services/references_service.dart';
import '../../../core/network/api_client.dart';
import '../data/review_service.dart';

/// Full facility detail page — mirrors Angular's clinic-detail route
/// (branch selector step, reached from clinic-explorer via selectClinic()).
class ClinicDetailScreen extends ConsumerStatefulWidget {
  final String clinicId;

  const ClinicDetailScreen({super.key, required this.clinicId});

  @override
  ConsumerState<ClinicDetailScreen> createState() => _ClinicDetailScreenState();
}

class _ClinicDetailScreenState extends ConsumerState<ClinicDetailScreen> {
  bool _loading = true;
  String? _error;
  ClinicDetailResponse? _detail;
  final Map<String, String> _cityNameById = {};
  final Map<String, int> _doctorCountByBranch = {};

  // Reviews — mirrors Angular's clinicReviews / showClinicReviews.
  List<ClinicReviewModel> _reviews = [];
  bool _showReviews = false;

  // Branch → doctors step — mirrors Angular's viewStep 'BRANCH_DOCTORS'
  // (reached via selectBranch()).
  String _viewStep = 'CLINIC_DETAIL';
  ClinicBranchModel? _selectedBranch;
  bool _branchDoctorsLoading = false;
  List<ClinicOperatingHourModel> _branchHours = [];
  List<_BranchDoctorEntry> _branchDoctors = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ref
          .read(clinicServiceProvider)
          .getClinicDetail(widget.clinicId);
      if (mounted) setState(() => _detail = d);
      _loadBranchExtras(d);
      _loadReviews();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load facility details.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fills in branch city names and per-branch doctor counts in the
  /// background, mirroring Angular's getBranchCityName / getBranchDoctorCount.
  Future<void> _loadBranchExtras(ClinicDetailResponse detail) async {
    try {
      final cities = await ref.read(referenceServiceProvider).getAllCities();
      if (mounted) {
        setState(() {
          _cityNameById
              .addEntries(cities.map((c) => MapEntry(c.cityId, c.nameEn)));
        });
      }
    } catch (_) {}

    if (detail.branches.isEmpty) return;
    try {
      final doctorService = ref.read(doctorServiceProvider);
      final doctors = await doctorService.getAllDoctors();
      final branchIds = detail.branches.map((b) => b.branchId).toSet();
      final counts = <String, int>{for (final id in branchIds) id: 0};

      await Future.wait(doctors.map((doc) async {
        try {
          final links = await doctorService.getDoctorClinics(doc.doctorId);
          for (final link in links) {
            if (branchIds.contains(link.branchId)) {
              counts[link.branchId] = (counts[link.branchId] ?? 0) + 1;
            }
          }
        } catch (_) {}
      }));

      if (mounted) setState(() => _doctorCountByBranch.addAll(counts));
    } catch (_) {}
  }

  /// Mirrors Angular's reviewService.getClinicReviews() call in
  /// loadClinicData(): fetched independently so a review-service failure
  /// never blocks the rest of the page, and auto-expands the section once
  /// reviews arrive.
  Future<void> _loadReviews() async {
    try {
      final revs = await ref
          .read(reviewServiceProvider)
          .getClinicReviews(widget.clinicId);
      if (mounted) {
        setState(() {
          _reviews = revs;
          if (_reviews.isNotEmpty) _showReviews = true;
        });
      }
    } catch (_) {}
  }

  /// Mirrors Angular's selectBranch(): loads the branch's operating hours,
  /// then matches every clinic doctor whose active DoctorClinic link points
  /// at this branch (falling back to a clinic-wide match when the clinic
  /// has only one branch), enriching each match with qualifications.
  Future<void> _selectBranch(ClinicBranchModel branch) async {
    setState(() {
      _selectedBranch = branch;
      _viewStep = 'BRANCH_DOCTORS';
      _branchDoctorsLoading = true;
      _branchHours = [];
      _branchDoctors = [];
    });

    try {
      final clinicService = ref.read(clinicServiceProvider);
      final doctorService = ref.read(doctorServiceProvider);

      final hours = await clinicService
          .getBranchHours(branch.branchId)
          .catchError((_) => <ClinicOperatingHourModel>[]);
      if (mounted) setState(() => _branchHours = hours);

      final doctors = await doctorService.getAllDoctors();
      final singleBranchClinic = (_detail?.branches.length ?? 0) <= 1;
      final entries = <_BranchDoctorEntry>[];

      await Future.wait(doctors.map((doc) async {
        try {
          final links = await doctorService.getDoctorClinics(doc.doctorId);
          final match = links.where((l) {
            if (!l.isActive) return false;
            if (l.branchId == branch.branchId) return true;
            if (l.branchId.isEmpty &&
                l.clinicId == branch.clinicId &&
                singleBranchClinic) return true;
            return false;
          }).toList();
          if (match.isEmpty) return;

          final quals = await doctorService
              .getDoctorQualifications(doc.doctorId)
              .catchError((_) => <DoctorQualificationModel>[]);

          entries.add(_BranchDoctorEntry(
            doctor: doc,
            dcLink: match.first,
            qualifications: quals,
          ));
        } catch (_) {}
      }));

      if (mounted) {
        setState(() {
          _branchDoctors = entries;
          _branchDoctorsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _branchDoctorsLoading = false);
    }
  }

  void _goBackToBranches() {
    setState(() {
      _viewStep = 'CLINIC_DETAIL';
      _selectedBranch = null;
      _branchDoctors = [];
      _branchHours = [];
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Colors.off,
      appBar: AppBar(
        backgroundColor: _Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: _viewStep == 'BRANCH_DOCTORS'
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _goBackToBranches,
              )
            : null,
        title: Text(_viewStep == 'BRANCH_DOCTORS'
            ? (_selectedBranch?.branchNameEn ?? 'Branch')
            : (_detail?.nameEn ?? 'Facility Details')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _Colors.teal))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                          style: const TextStyle(color: _Colors.textMuted)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                          onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : _detail == null
                  ? const Center(child: Text('Facility not found.'))
                  : _viewStep == 'BRANCH_DOCTORS'
                      ? _buildBranchDoctorsStep(_detail!)
                      : _buildContent(_detail!),
    );
  }

  Widget _buildContent(ClinicDetailResponse detail) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Logo + license
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _Colors.tealLight,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _resolveLogoUrl(detail.logoUrl) != null
                  ? Image.network(_resolveLogoUrl(detail.logoUrl)!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.local_hospital,
                          color: _Colors.tealDark))
                  : const Icon(Icons.local_hospital, color: _Colors.tealDark),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(detail.nameEn,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _Colors.textMain)),
                  const SizedBox(height: 2),
                  Text('MOH License: ${detail.mohLicenseNumber}',
                      style: const TextStyle(
                          fontSize: 12, color: _Colors.textMuted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // About
        const Text('About Facility',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _Colors.tealDark)),
        const SizedBox(height: 4),
        Text(
          (detail.descriptionEn ?? '').isNotEmpty
              ? detail.descriptionEn!
              : 'Premier healthcare provider delivering specialized medical services.',
          style: const TextStyle(
              fontSize: 13, color: _Colors.textMuted, height: 1.5),
        ),
        const SizedBox(height: 20),

        // Contact + status
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Contact Information',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _Colors.textMuted)),
                  const SizedBox(height: 8),
                  _InfoRow(
                      icon: Icons.phone_outlined, label: detail.phonePrimary),
                  if ((detail.email ?? '').isNotEmpty) ...[
                    const SizedBox(height: 5),
                    _InfoRow(icon: Icons.mail_outline, label: detail.email!),
                  ],
                  if ((detail.website ?? '').isNotEmpty) ...[
                    const SizedBox(height: 5),
                    _InfoRow(icon: Icons.language, label: detail.website!),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Facility Status',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _Colors.textMuted)),
                const SizedBox(height: 8),
                if (detail.mohVerified)
                  const _Badge(
                      label: '✓ MOH Verified',
                      bg: Color(0xFFCCFBF1),
                      fg: _Colors.tealDark),
                if (detail.isActive)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: _Badge(
                        label: '● Active',
                        bg: Color(0xFFDCFCE7),
                        fg: _Colors.green),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Patient Reviews & Ratings — mirrors .reviews-section-wrapper.
        _ReviewsSection(
          overallRating: detail.overallRating,
          reviews: _reviews,
          expanded: _showReviews,
          onToggle: () => setState(() => _showReviews = !_showReviews),
        ),
        const SizedBox(height: 24),

        // Branch Selection Header — mirrors .branches-section-header
        const Text('🏢  Select a Branch Location',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _Colors.textMain)),
        const SizedBox(height: 3),
        const Text(
            'Choose a branch below to view its working hours, address, and available doctors for booking.',
            style: TextStyle(fontSize: 12, color: _Colors.textMuted)),
        const SizedBox(height: 12),

        // Branch Cards — mirrors .executive-branch-card
        if (detail.branches.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _Colors.border),
            ),
            child: const Text('No active branches found for this clinic.',
                style: TextStyle(color: _Colors.textMuted)),
          )
        else
          ...detail.branches.map((b) => _BranchCard(
                branch: b,
                clinicPhone: detail.phonePrimary,
                cityName: _cityNameById[b.cityId],
                doctorCount: _doctorCountByBranch[b.branchId],
                onViewDoctors: () => _selectBranch(b),
              )),

        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => context.pop(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: const BorderSide(color: _Colors.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Close Facility Details'),
          ),
        ),
      ],
    );
  }

  /// Mirrors Angular's STEP 3 (BRANCH_DOCTORS): branch summary banner with
  /// working hours, followed by the doctors assigned to this branch, each
  /// bookable via the shared booking flow.
  Widget _buildBranchDoctorsStep(ClinicDetailResponse detail) {
    final branch = _selectedBranch!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Branch summary banner — mirrors .branch-summary-banner.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _Colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📍 ${_cityNameById[branch.cityId] ?? 'Saudi Arabia'}',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _Colors.teal)),
              const SizedBox(height: 4),
              Text(branch.branchNameEn,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: _Colors.textMain)),
              const SizedBox(height: 4),
              Text(
                [branch.addressLine1, branch.addressLine2]
                        .where((s) => (s ?? '').isNotEmpty)
                        .join(', ') +
                    ((branch.phone ?? detail.phonePrimary).isNotEmpty
                        ? '  •  📞 ${branch.phone ?? detail.phonePrimary}'
                        : ''),
                style: const TextStyle(fontSize: 12, color: _Colors.textMuted),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _Colors.off,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _Colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🕒  Working Hours',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _Colors.textMain)),
                    const SizedBox(height: 4),
                    if (_branchHours.isEmpty)
                      const Text('Sun - Thu: 08:00 AM - 08:00 PM',
                          style: TextStyle(
                              fontSize: 11.5, color: _Colors.textMuted))
                    else
                      ..._branchHours.take(3).map((h) => Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${_dayNames[h.dayOfWeek] ?? 'Day ${h.dayOfWeek}'}: ${h.isClosed ? 'Closed' : '${h.openTime} - ${h.closeTime}'}',
                              style: const TextStyle(
                                  fontSize: 11.5, color: _Colors.textMuted),
                            ),
                          )),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Doctors header — mirrors .doctors-section-header.
        const Text('👨‍⚕️  Available Doctors at this Branch',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _Colors.textMain)),
        const SizedBox(height: 3),
        const Text(
            'Select your preferred doctor below to check bookable slots and schedule an appointment.',
            style: TextStyle(fontSize: 12, color: _Colors.textMuted)),
        const SizedBox(height: 12),

        if (_branchDoctorsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child:
                Center(child: CircularProgressIndicator(color: _Colors.teal)),
          )
        else if (_branchDoctors.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _Colors.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.medical_services_outlined,
                    size: 32, color: _Colors.textMuted),
                const SizedBox(height: 8),
                const Text('No Doctors Registered',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: _Colors.textMain)),
                const SizedBox(height: 4),
                const Text(
                    'There are currently no active doctors assigned to this specific branch.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: _Colors.textMuted)),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _goBackToBranches,
                  child: const Text('Choose Another Branch'),
                ),
              ],
            ),
          )
        else
          ..._branchDoctors.map((e) => _BranchDoctorCard(
                entry: e,
                onBook: () => context.push('/patient/book-appointment'),
              )),
      ],
    );
  }
}

/// Doctor matched to a branch via an active DoctorClinic link, plus their
/// qualifications — mirrors Angular's branchDoctors entry shape
/// ({ doctor, dcLink, qualifications }).
class _BranchDoctorEntry {
  final DoctorModel doctor;
  final DoctorClinicModel dcLink;
  final List<DoctorQualificationModel> qualifications;

  const _BranchDoctorEntry({
    required this.doctor,
    required this.dcLink,
    required this.qualifications,
  });
}

/// Mirrors .doctor-card-executive — avatar, name + rating, bio, qualification
/// pills, and a footer split by a fee on the left and a Book button.
class _BranchDoctorCard extends StatelessWidget {
  final _BranchDoctorEntry entry;
  final VoidCallback onBook;

  const _BranchDoctorCard({required this.entry, required this.onBook});

  @override
  Widget build(BuildContext context) {
    final doctor = entry.doctor;
    final avatarUrl = _resolveLogoUrl(doctor.avatarUrl);
    final initials = _initials(doctor.fullName);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Colors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08172A), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: _Colors.tealLight,
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: avatarUrl != null
                    ? Image.network(avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Text(initials,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _Colors.tealDark)))
                    : Text(initials,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _Colors.tealDark)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(doctor.fullName,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _Colors.textMain)),
                        ),
                        _Badge(
                          label: '★ ${doctor.overallRating.toStringAsFixed(1)}',
                          bg: const Color(0xFFFFFBEB),
                          fg: const Color(0xFFB45309),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      (doctor.bioEn ?? '').trim().isNotEmpty
                          ? doctor.bioEn!.trim()
                          : 'Consultant Specialist',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: _Colors.tealDark, height: 1.4),
                    ),
                    if (entry.qualifications.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: entry.qualifications
                            .map((q) => _Badge(
                                  label: '🎓 ${q.degree}',
                                  bg: const Color(0xFFF8FAFC),
                                  fg: const Color(0xFF334155),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Consultation Fee',
                        style: TextStyle(
                            fontSize: 10.5, color: _Colors.textMuted)),
                    Text(
                        '${entry.dcLink.consultationFeeSar.toStringAsFixed(0)} SAR',
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: _Colors.textMain)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: onBook,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.event_available, size: 16),
                  label: const Text('Book Appointment',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _initials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'DR';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
  return trimmed.substring(0, trimmed.length.clamp(0, 2)).toUpperCase();
}

/// Mirrors .reviews-section-wrapper: a collapsible header with the overall
/// rating + review count, expanding into a list of review cards.
class _ReviewsSection extends StatelessWidget {
  final double overallRating;
  final List<ClinicReviewModel> reviews;
  final bool expanded;
  final VoidCallback onToggle;

  const _ReviewsSection({
    required this.overallRating,
    required this.reviews,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Colors.border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: _Colors.off,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _Colors.border),
                    ),
                    child: Column(
                      children: [
                        Text('★ ${overallRating.toStringAsFixed(1)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFB45309),
                                fontSize: 14)),
                        const Text('Rating',
                            style: TextStyle(
                                fontSize: 9.5, color: _Colors.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Flexible(
                              child: Text('Patient Reviews & Network Ratings',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _Colors.textMain)),
                            ),
                            if (reviews.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              _Badge(
                                  label: '${reviews.length} Verified Reviews',
                                  bg: _Colors.teal,
                                  fg: Colors.white),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                            'Ratings and verified feedback from patients who completed visits.',
                            style: TextStyle(
                                fontSize: 11, color: _Colors.textMuted)),
                      ],
                    ),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more,
                      color: _Colors.textMuted),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: reviews.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(20),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _Colors.off,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                          'No reviews recorded for this clinic yet.',
                          style: TextStyle(
                              fontSize: 12, color: _Colors.textMuted)),
                    )
                  : Column(
                      children:
                          reviews.map((r) => _ReviewCard(review: r)).toList(),
                    ),
            ),
        ],
      ),
    );
  }
}

/// Mirrors .review-item: avatar-initial, reviewer name / anonymous label,
/// verified badge, date, star rating, and optional subrating chips + quote.
class _ReviewCard extends StatelessWidget {
  final ClinicReviewModel review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final name = review.isAnonymous ? 'Anonymous Patient' : review.patientName;
    final initials = _initials(review.isAnonymous ? 'Anonymous' : name);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _Colors.off,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _Colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _Colors.tealLight,
                child: Text(initials,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _Colors.tealDark)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _Colors.textMain)),
                    if (review.createdAt != null)
                      Text(_formatDate(review.createdAt!),
                          style: const TextStyle(
                              fontSize: 10.5, color: _Colors.textMuted)),
                  ],
                ),
              ),
              Text('★ ${review.rating}.0/5.0',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB45309))),
            ],
          ),
          if (review.ratingCleanliness != null ||
              review.ratingStaff != null ||
              review.ratingWait != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (review.ratingCleanliness != null)
                  _Badge(
                      label: '✨ Cleanliness: ${review.ratingCleanliness}/5',
                      bg: Colors.white,
                      fg: _Colors.textMuted),
                if (review.ratingStaff != null)
                  _Badge(
                      label: '👩‍⚕️ Staff: ${review.ratingStaff}/5',
                      bg: Colors.white,
                      fg: _Colors.textMuted),
                if (review.ratingWait != null)
                  _Badge(
                      label: '🕒 Wait: ${review.ratingWait}/5',
                      bg: Colors.white,
                      fg: _Colors.textMuted),
              ],
            ),
          ],
          if ((review.reviewText ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('"${review.reviewText!.trim()}"',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    color: _Colors.textMain,
                    height: 1.4)),
          ],
        ],
      ),
    );
  }
}

String _formatDate(String iso) {
  try {
    final d = DateTime.parse(iso);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  } catch (_) {
    return iso;
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
        Icon(icon, size: 14, color: _Colors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: const TextStyle(fontSize: 12, color: _Colors.textMain)),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Badge({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5, color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

/// Mirrors .executive-branch-card — name + city/doctor-count badges, address,
/// and a footer split by a divider with phone + two action buttons.
class _BranchCard extends StatelessWidget {
  final ClinicBranchModel branch;
  final String clinicPhone;
  final String? cityName;
  final int? doctorCount;
  final VoidCallback onViewDoctors;

  const _BranchCard({
    required this.branch,
    required this.clinicPhone,
    required this.cityName,
    required this.doctorCount,
    required this.onViewDoctors,
  });

  @override
  Widget build(BuildContext context) {
    final phone = (branch.phone ?? '').isNotEmpty ? branch.phone! : clinicPhone;
    final hasLocation = branch.latitude != null && branch.longitude != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Colors.border),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08172A), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(branch.branchNameEn,
                        style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: _Colors.textMain)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if ((cityName ?? '').isNotEmpty)
                          _Badge(
                              label: '📍 $cityName',
                              bg: const Color(0xFFF8FAFC),
                              fg: _Colors.teal),
                        _Badge(
                            label: '👥 ${doctorCount ?? 0} Doctors',
                            bg: const Color(0xFFF8FAFC),
                            fg: const Color(0xFF334155)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Dot(),
                    SizedBox(width: 4),
                    Text('Open Today',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF16A34A))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            [branch.addressLine1, branch.addressLine2]
                .where((s) => (s ?? '').isNotEmpty)
                .join(', '),
            style: const TextStyle(fontSize: 12, color: _Colors.textMuted),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 8,
              children: [
                if (phone.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.phone_outlined,
                          size: 13, color: _Colors.textMuted),
                      const SizedBox(width: 4),
                      Text(phone,
                          style: const TextStyle(
                              fontSize: 12, color: _Colors.textMuted)),
                    ],
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: hasLocation
                          ? () async {
                              final url = Uri.parse(
                                  'https://www.google.com/maps/search/?api=1&query=${branch.latitude},${branch.longitude}');
                              try {
                                final launched = await launchUrl(url,
                                    mode: LaunchMode.externalApplication);
                                if (!launched && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Could not open map location.')),
                                  );
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Could not open map location.')),
                                  );
                                }
                              }
                            }
                          : null,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _Colors.border),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('📍 View Location',
                          style: TextStyle(fontSize: 11.5)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: onViewDoctors,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _Colors.teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('View Doctors & Book →',
                          style: TextStyle(fontSize: 11.5)),
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
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration:
          const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle),
    );
  }
}

class _Colors {
  static const teal = Color(0xFF0D9488);
  static const tealDark = Color(0xFF0F766E);
  static const tealLight = Color(0xFFCCFBF1);
  static const green = Color(0xFF16A34A);
  static const textMain = Color(0xFF0F172A);
  static const textMuted = Color(0xFF94A3B8);
  static const border = Color(0xFFE2E8F0);
  static const off = Color(0xFFF8FAFC);
}

String? _resolveLogoUrl(String? raw) {
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

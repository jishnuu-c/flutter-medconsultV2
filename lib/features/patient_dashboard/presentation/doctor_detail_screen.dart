import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/localization/language_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/image_utils.dart';
import '../../../core/services/references_service.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../clinic_admin/data/doctor_models.dart';
import '../../clinic_admin/data/clinic_service.dart';
import '../../clinic_admin/data/clinic_models.dart';
import '../data/review_service.dart';

/// Full public-facing Doctor Detail Screen mirroring Angular's DoctorDetailComponent.
/// Optimized for mobile UI/UX.
class DoctorDetailScreen extends ConsumerStatefulWidget {
  final String doctorId;

  const DoctorDetailScreen({super.key, required this.doctorId});

  @override
  ConsumerState<DoctorDetailScreen> createState() => _DoctorDetailScreenState();
}

class _DoctorDetailScreenState extends ConsumerState<DoctorDetailScreen> {
  bool _loading = true;
  String? _error;
  DoctorDetailResponse? _detail;
  List<DoctorReviewModel> _reviews = [];
  Map<String, String> _specialtyNames = {};
  Map<String, String> _languageNames = {};
  Map<String, ClinicModel> _clinicsMap = {};
  Map<String, String> _branchNames = {};

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
      final doctorService = ref.read(doctorServiceProvider);
      final refService = ref.read(referenceServiceProvider);
      final reviewService = ref.read(reviewServiceProvider);
      final clinicService = ref.read(clinicServiceProvider);

      final results = await Future.wait([
        doctorService.getDoctorProfile(widget.doctorId),
        reviewService.getDoctorReviews(widget.doctorId).catchError((_) => <DoctorReviewModel>[]),
        refService.getAllSpecialties().catchError((_) => <SpecialtyModel>[]),
        refService.getAllLanguages().catchError((_) => <LanguageModel>[]),
      ]);

      final detail = results[0] as DoctorDetailResponse;
      final reviews = results[1] as List<DoctorReviewModel>;
      final specialties = results[2] as List<SpecialtyModel>;
      final languages = results[3] as List<LanguageModel>;

      final specMap = <String, String>{};
      for (final s in specialties) {
        specMap[s.specialtyId] = s.nameEn;
      }

      final langMap = <String, String>{};
      for (final l in languages) {
        langMap[l.languageId] = l.nameEn;
      }

      // Enrich clinic information
      final clMap = <String, ClinicModel>{};
      final brMap = <String, String>{};
      if (detail.clinics.isNotEmpty) {
        await Future.wait(detail.clinics.map((c) async {
          try {
            if (c.clinicId.isNotEmpty) {
              final clinicDetail = await clinicService.getClinicDetail(c.clinicId);
              clMap[c.clinicId] = clinicDetail;
              final branches = await clinicService.getClinicBranches(c.clinicId);
              for (final b in branches) {
                brMap[b.branchId] = b.branchNameEn;
              }
            }
          } catch (_) {}
        }));
      }

      if (mounted) {
        setState(() {
          _detail = detail;
          _reviews = reviews;
          _specialtyNames = specMap;
          _languageNames = langMap;
          _clinicsMap = clMap;
          _branchNames = brMap;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to load doctor profile.');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatDoctorName(String fullName) {
    final trimmed = fullName.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('dr') ||
        lower.startsWith('doctor') ||
        lower.startsWith('prof') ||
        lower.startsWith('consultant') ||
        trimmed.startsWith('د.')) {
      return trimmed;
    }
    return 'Dr. $trimmed';
  }

  void _bookAppointment() {
    if (_detail == null) return;
    context.push('/patient/book-appointment?doctorId=${_detail!.doctorId}');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundApp,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryTeal),
        ),
      );
    }

    if (_error != null || _detail == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundApp,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.textMain),
            onPressed: () => Navigator.of(context).canPop()
                ? Navigator.of(context).pop()
                : context.go('/patient/doctors'),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 48, color: Color(0xFFEF4444)),
                const SizedBox(height: 12),
                Text(
                  _error ?? 'Doctor not found',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMain),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _load,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final doc = _detail!;
    final doctorName = _formatDoctorName(doc.fullName);

    return Scaffold(
      backgroundColor: AppTheme.backgroundApp,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textMain),
          onPressed: () => Navigator.of(context).canPop()
              ? Navigator.of(context).pop()
              : context.go('/patient/doctors'),
        ),
        title: Text(
          doctorName,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textMain,
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Standard Consultation Fee'.tr,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                Text(
                  '${doc.consultationFeeSar.toStringAsFixed(0)} ${'SAR'.tr}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F766E),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _bookAppointment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: Text(
                  'Book Appointment'.tr,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryTeal,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 1. Hero Profile Card ──────────────────────────────────────
            _buildHeroCard(doc, doctorName),
            const SizedBox(height: 16),

            // ── 2. Quick Metrics Strip ────────────────────────────────────
            _buildQuickStatsStrip(doc),
            const SizedBox(height: 16),

            // ── 3. Professional Biography ─────────────────────────────────
            _buildBioCard(doc),
            const SizedBox(height: 16),

            // ── 4. Associated Clinics & Locations ─────────────────────────
            _buildClinicsCard(doc),
            const SizedBox(height: 16),

            // ── 5. Academic Qualifications ────────────────────────────────
            _buildQualificationsCard(doc),
            const SizedBox(height: 16),

            // ── 6. Spoken Languages ───────────────────────────────────────
            _buildLanguagesCard(doc),
            const SizedBox(height: 16),

            // ── 7. Patient Reviews & Ratings ──────────────────────────────
            _buildReviewsSection(doc),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ── Hero Card ──────────────────────────────────────────────────────────
  Widget _buildHeroCard(DoctorDetailResponse doc, String doctorName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppAvatar(
                imageUrl: doc.avatarUrl,
                name: doc.fullName,
                radius: 36,
                fontSize: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctorName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: doc.mohVerified
                            ? const Color(0xFFCCFBF1)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            doc.mohVerified
                                ? Icons.verified_rounded
                                : Icons.pending_rounded,
                            size: 13,
                            color: doc.mohVerified
                                ? const Color(0xFF0F766E)
                                : const Color(0xFFB45309),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            doc.mohVerified
                                ? '✓ MOH Verified License'.tr
                                : 'MOH Verification Pending'.tr,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: doc.mohVerified
                                  ? const Color(0xFF0F766E)
                                  : const Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Specialties pills
          if (doc.specialties.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: doc.specialties.map((s) {
                final name = _specialtyNames[s.specialtyId] ?? 'Specialist'.tr;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.medical_services_outlined,
                          size: 12, color: Color(0xFF0F766E)),
                      const SizedBox(width: 4),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),

          // Metadata row: Reg ID & Email
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Registration ID:'.tr,
                        style:
                            const TextStyle(fontSize: 10.5, color: AppTheme.textMuted)),
                    Text(
                      doc.mohRegistrationNumber.isNotEmpty
                          ? doc.mohRegistrationNumber
                          : 'N/A',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMain),
                    ),
                  ],
                ),
              ),
              if (doc.email.isNotEmpty)
                Expanded(
                  child: InkWell(
                    onTap: () {
                      final uri = Uri.parse('mailto:${doc.email}');
                      launchUrl(uri);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Email'.tr,
                            style: const TextStyle(
                                fontSize: 10.5, color: AppTheme.textMuted)),
                        Text(
                          doc.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Quick Stats Strip ──────────────────────────────────────────────────
  Widget _buildQuickStatsStrip(DoctorDetailResponse doc) {
    return Row(
      children: [
        Expanded(
          child: _statCell(
            icon: Icons.work_outline_rounded,
            value: '${doc.experienceYears} ${'Years'.tr}',
            label: 'Experience'.tr,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statCell(
            icon: Icons.star_rounded,
            iconColor: const Color(0xFFF59E0B),
            value: '${doc.overallRating.toStringAsFixed(1)} ★',
            label: '${doc.reviewCount} ${'reviews'.tr}',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statCell(
            icon: Icons.payments_outlined,
            value: '${doc.consultationFeeSar.toStringAsFixed(0)} ${'SAR'.tr}',
            label: 'Standard Fee:'.tr,
          ),
        ),
      ],
    );
  }

  Widget _statCell({
    required IconData icon,
    Color iconColor = const Color(0xFF0F766E),
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  // ── Biography Card ─────────────────────────────────────────────────────
  Widget _buildBioCard(DoctorDetailResponse doc) {
    final bioEn = doc.bioEn?.trim() ?? '';
    final bioAr = doc.bioAr?.trim() ?? '';
    final hasBio = bioEn.isNotEmpty || bioAr.isNotEmpty;

    return _cardWrapper(
      title: 'Professional Biography'.tr,
      icon: Icons.description_outlined,
      child: hasBio
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bioEn.isNotEmpty) ...[
                  Text(
                    bioEn,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF334155),
                      height: 1.45,
                    ),
                  ),
                ],
                if (bioAr.isNotEmpty) ...[
                  if (bioEn.isNotEmpty) const SizedBox(height: 10),
                  Text(
                    bioAr,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF334155),
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            )
          : Text(
              'No bio notes provided.'.tr,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
            ),
    );
  }

  // ── Associated Clinics Card ────────────────────────────────────────────
  Widget _buildClinicsCard(DoctorDetailResponse doc) {
    final isAr = ref.watch(isArabicProvider);
    return _cardWrapper(
      title: 'Associated Clinics & Locations'.tr,
      icon: Icons.local_hospital_outlined,
      child: doc.clinics.isNotEmpty
          ? Column(
              children: doc.clinics.map((c) {
                final clinic = _clinicsMap[c.clinicId];
                final clinicName = clinic != null
                    ? (isAr && clinic.nameAr.isNotEmpty ? clinic.nameAr : clinic.nameEn)
                    : (c.clinicNameEn ?? 'Clinic Location'.tr);
                final branchName = _branchNames[c.branchId] ?? c.branchNameEn ?? 'Primary Branch'.tr;
                final logoUrl = resolveImageUrl(clinic?.logoUrl);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (logoUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                logoUrl,
                                width: 36,
                                height: 36,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _clinicIconPlaceholder(),
                              ),
                            )
                          else
                            _clinicIconPlaceholder(),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        clinicName,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textMain,
                                        ),
                                      ),
                                    ),
                                    if (c.isPrimary)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFCCFBF1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'Primary Location'.tr,
                                          style: const TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F766E),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                Text(
                                  branchName,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '📍 ${c.department}',
                              style: const TextStyle(
                                  fontSize: 11.5, color: Color(0xFF475569)),
                            ),
                          ),
                          Text(
                            '${'Fee:'.tr} ${c.consultationFeeSar.toStringAsFixed(0)} ${'SAR'.tr}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            )
          : Text(
              'No registered clinical locations assigned.'.tr,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
            ),
    );
  }

  Widget _clinicIconPlaceholder() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFCCFBF1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.local_hospital_rounded,
          size: 20, color: Color(0xFF0F766E)),
    );
  }

  // ── Academic Qualifications Card ───────────────────────────────────────
  Widget _buildQualificationsCard(DoctorDetailResponse doc) {
    return _cardWrapper(
      title: 'Academic Qualifications'.tr,
      icon: Icons.school_outlined,
      child: doc.qualifications.isNotEmpty
          ? Column(
              children: doc.qualifications.map((q) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.school_rounded,
                            size: 16, color: Color(0xFF6D28D9)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q.degree,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textMain,
                              ),
                            ),
                            Text(
                              '${q.institution}, ${q.country}',
                              style: const TextStyle(
                                  fontSize: 11.5, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${q.yearObtained}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            )
          : Text(
              'No qualifications recorded on profile file.'.tr,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
            ),
    );
  }

  // ── Spoken Languages Card ──────────────────────────────────────────────
  Widget _buildLanguagesCard(DoctorDetailResponse doc) {
    return _cardWrapper(
      title: 'Spoken Languages'.tr,
      icon: Icons.language_rounded,
      child: doc.languages.isNotEmpty
          ? Wrap(
              spacing: 8,
              runSpacing: 8,
              children: doc.languages.map((l) {
                final name = _languageNames[l.languageId] ?? 'Language'.tr;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chat_bubble_outline_rounded,
                          size: 13, color: Color(0xFF0F766E)),
                      const SizedBox(width: 6),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFCCFBF1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l.proficiency.name,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            )
          : Text(
              'No languages documented.'.tr,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
            ),
    );
  }

  // ── Patient Reviews & Ratings ──────────────────────────────────────────
  Widget _buildReviewsSection(DoctorDetailResponse doc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.star_rounded,
                      size: 20, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 6),
                  Text(
                    'Patient Reviews & Ratings'.tr,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMain,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '★ ${doc.overallRating.toStringAsFixed(1)} / 5.0 (${_reviews.length})',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 14),

          if (_reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.rate_review_outlined,
                        size: 32, color: AppTheme.textMuted),
                    const SizedBox(height: 6),
                    Text(
                      'No patient reviews recorded yet for this doctor.'.tr,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._reviews.map((rev) => _buildReviewRow(rev, doc.fullName)),
        ],
      ),
    );
  }

  Widget _buildReviewRow(DoctorReviewModel rev, String doctorName) {
    final patientName = rev.isAnonymous
        ? 'Anonymous'.tr
        : (rev.patientName.isNotEmpty ? rev.patientName : 'Patient'.tr);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(
                imageUrl: rev.isAnonymous ? null : rev.patientAvatarUrl,
                name: patientName,
                radius: 14,
                fontSize: 10,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patientName,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMain,
                      ),
                    ),
                    if (rev.createdAt != null && rev.createdAt!.isNotEmpty)
                      Text(
                        rev.createdAt!.split('T')[0],
                        style: const TextStyle(
                            fontSize: 10, color: AppTheme.textMuted),
                      ),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (starIdx) {
                  return Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: starIdx < rev.rating
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFFCBD5E1),
                  );
                }),
              ),
            ],
          ),
          if (rev.reviewText != null && rev.reviewText!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              rev.reviewText!,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF334155),
                height: 1.35,
              ),
            ),
          ],

          // Nested Doctor Reply Box
          if (rev.doctorReply != null && rev.doctorReply!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: const Border(
                  left: BorderSide(color: Color(0xFF0F766E), width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '👨‍⚕️ ${'Doctor Response'.tr}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rev.doctorReply!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Card Container Helper ──────────────────────────────────────────────
  Widget _cardWrapper({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF0F766E)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

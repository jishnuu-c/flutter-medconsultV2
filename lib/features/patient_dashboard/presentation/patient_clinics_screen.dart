import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../clinic_admin/data/clinic_service.dart';
import '../../clinic_admin/data/clinic_models.dart';
import '../../../core/services/references_service.dart';
import '../../../core/network/api_client.dart';

/// Mirrors Angular's patient-dashboard/clinic-explorer ("Clinics & Branches"),
/// mobile list layout: executive-clinic-list-item cards with verified badge,
/// rating, branch count + specialty pills, phone, and an explore action.
class PatientClinicsScreen extends ConsumerStatefulWidget {
  const PatientClinicsScreen({super.key});

  @override
  ConsumerState<PatientClinicsScreen> createState() =>
      _PatientClinicsScreenState();
}

class _ClinicEnrichment {
  final int branchCount;
  final List<String> specialtyNames;
  const _ClinicEnrichment(
      {required this.branchCount, required this.specialtyNames});
}

class _PatientClinicsScreenState extends ConsumerState<PatientClinicsScreen> {
  bool _isLoading = false;
  List<ClinicModel> _clinics = [];
  final Map<String, _ClinicEnrichment> _enrichment = {};
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadClinics();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadClinics() async {
    setState(() => _isLoading = true);
    try {
      final clinicService = ref.read(clinicServiceProvider);
      final referenceService = ref.read(referenceServiceProvider);

      final results = await Future.wait([
        clinicService.getAllClinics(),
        referenceService.getAllSpecialties(),
      ]);
      final clinics = results[0] as List<ClinicModel>;
      final specialties = results[1] as List<SpecialtyModel>;
      final specialtyNameById = {
        for (final s in specialties) s.specialtyId: s.nameEn,
      };

      if (mounted) setState(() => _clinics = clinics);

      // Enrich each clinic with its branch count & top specialties, in
      // parallel — mirrors the Angular forkJoin enrichment pass.
      await Future.wait(clinics.map((c) async {
        try {
          final branchesAndSpecs = await Future.wait([
            clinicService.getClinicBranches(c.clinicId),
            clinicService.getClinicSpecialties(c.clinicId),
          ]);
          final branches = branchesAndSpecs[0] as List<ClinicBranchModel>;
          final specs = branchesAndSpecs[1] as List<ClinicSpecialtyModel>;
          _enrichment[c.clinicId] = _ClinicEnrichment(
            branchCount: branches.length,
            specialtyNames: specs
                .map((s) => specialtyNameById[s.specialtyId])
                .whereType<String>()
                .where((n) => n.isNotEmpty)
                .take(2)
                .toList(),
          );
        } catch (_) {
          // Skip enrichment for this clinic on failure; card still renders.
        }
      }));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load clinics: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<ClinicModel> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _clinics;
    return _clinics.where((c) {
      final name = c.nameEn.toLowerCase();
      final desc = (c.descriptionEn ?? '').toLowerCase();
      return name.contains(q) || desc.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadClinics,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Clinics & Branches',
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: _Colors.textDark)),
          const SizedBox(height: 4),
          const Text('Explore verified clinics and their branches.',
              style: TextStyle(fontSize: 13, color: _Colors.textMuted)),
          const SizedBox(height: 14),

          // Mobile search bar (mirrors .mobile-search-input-wrapper).
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search clinic name or description...',
              hintStyle:
                  const TextStyle(fontSize: 13.5, color: _Colors.textMuted),
              prefixIcon:
                  const Icon(Icons.search, size: 19, color: _Colors.textMuted),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _Colors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _Colors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: _Colors.teal, width: 1.5)),
            ),
          ),
          const SizedBox(height: 16),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child:
                  Center(child: CircularProgressIndicator(color: _Colors.teal)),
            )
          else if (_filtered.isEmpty)
            _EmptyState(
              hasClinics: _clinics.isNotEmpty,
              onClear: () {
                _searchController.clear();
                setState(() {});
              },
            )
          else
            Column(
              children: _filtered
                  .map((clinic) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _ClinicListCard(
                          clinic: clinic,
                          enrichment: _enrichment[clinic.clinicId],
                          onTap: () => context
                              .push('/patient/clinics/${clinic.clinicId}'),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasClinics;
  final VoidCallback onClear;
  const _EmptyState({required this.hasClinics, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _Colors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.local_hospital_outlined,
                size: 30, color: _Colors.textMuted),
          ),
          const SizedBox(height: 14),
          const Text('No Clinics Found',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _Colors.textDark)),
          const SizedBox(height: 6),
          Text(
            hasClinics
                ? 'No medical clinics match your current search. Try adjusting your keyword.'
                : 'No medical clinics are available right now.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: _Colors.textMuted),
          ),
          if (hasClinics) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onClear,
              style: ElevatedButton.styleFrom(
                backgroundColor: _Colors.teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Reset Search'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Mirrors .executive-clinic-list-item: on mobile, the action row (phone +
/// explore button) breaks onto its own line under a top divider.
class _ClinicListCard extends StatelessWidget {
  final ClinicModel clinic;
  final _ClinicEnrichment? enrichment;
  final VoidCallback onTap;

  const _ClinicListCard(
      {required this.clinic, required this.enrichment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final initials = (clinic.nameEn.isNotEmpty ? clinic.nameEn : '?')
            .substring(0, 1)
            .toUpperCase() +
        (clinic.nameEn.length > 1 ? clinic.nameEn.substring(1, 2) : '');
    final resolvedUrl = _resolveLogoUrl(clinic.logoUrl);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _Colors.border),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x08172A), blurRadius: 10, offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo avatar
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      border: Border.all(color: _Colors.border),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: resolvedUrl != null
                        ? Image.network(resolvedUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Text(initials,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: _Colors.teal)))
                        : Text(initials,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _Colors.teal)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Text(clinic.nameEn,
                                style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700,
                                    color: _Colors.textDark)),
                            if (clinic.mohVerified)
                              const _Pill(
                                label: 'MOH Verified',
                                icon: Icons.check,
                                bg: Color(0xFFF0FDF4),
                                fg: Color(0xFF166534),
                                border: Color(0xFFBBF7D0),
                              ),
                            _Pill(
                              label:
                                  '${clinic.overallRating} (${clinic.reviewCount})',
                              iconText: '★',
                              bg: const Color(0xFFFFFBEB),
                              fg: const Color(0xFFB45309),
                              border: const Color(0xFFFEF3C7),
                            ),
                          ],
                        ),
                        if ((clinic.descriptionEn ?? '').isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            clinic.descriptionEn!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: _Colors.textMuted,
                                height: 1.3),
                          ),
                        ],
                        if (enrichment != null) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _Pill(
                                label: '${enrichment!.branchCount} Branches',
                                icon: Icons.business_outlined,
                                bg: const Color(0xFFF0FDFA),
                                fg: const Color(0xFF0F766E),
                                border: const Color(0xFFCCFBF1),
                              ),
                              for (final spec in enrichment!.specialtyNames)
                                _Pill(
                                  label: spec,
                                  iconText: '⚕️',
                                  bg: const Color(0xFFF8FAFC),
                                  fg: const Color(0xFF334155),
                                  border: _Colors.border,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              // Bottom action row — mobile: full width, split by a divider.
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.only(top: 10),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (clinic.phonePrimary.isNotEmpty)
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.phone_outlined,
                                size: 14, color: _Colors.textMuted),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(clinic.phonePrimary,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _Colors.textMuted)),
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDFA),
                        border: Border.all(color: const Color(0xFFCCFBF1)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Explore Clinic & Branches',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _Colors.teal)),
                          SizedBox(width: 5),
                          Text('→',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _Colors.teal)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small rounded pill — mirrors .info-pill / .badge-verified / .rating-badge.
class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String? iconText;
  final Color bg;
  final Color fg;
  final Color border;

  const _Pill({
    required this.label,
    this.icon,
    this.iconText,
    required this.bg,
    required this.fg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: 11, color: fg),
          if (iconText != null)
            Text(iconText!, style: TextStyle(fontSize: 10.5, color: fg)),
          if (icon != null || iconText != null) const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

class _Colors {
  static const teal = Color(0xFF0D9488);
  static const textDark = Color(0xFF0F172A);
  static const textMuted = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);
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

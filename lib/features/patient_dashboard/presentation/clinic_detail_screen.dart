import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../clinic_admin/data/clinic_models.dart';
import '../../clinic_admin/data/clinic_service.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../../core/services/references_service.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Colors.off,
      appBar: AppBar(
        backgroundColor: _Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_detail?.nameEn ?? 'Facility Details'),
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
              child: (detail.logoUrl ?? '').isNotEmpty
                  ? Image.network(detail.logoUrl!,
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

  const _BranchCard({
    required this.branch,
    required this.clinicPhone,
    required this.cityName,
    required this.doctorCount,
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
                          ? () => ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        '${branch.branchNameEn}: ${branch.latitude}, ${branch.longitude}')),
                              )
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
                      onPressed: () => context.push('/patient/doctors'),
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

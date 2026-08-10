import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../clinic_admin/data/clinic_models.dart';
import '../../clinic_admin/data/clinic_service.dart';

/// Full facility detail page — mirrors Angular's clinic detail route
/// (navigated to from landing/clinic-explorer via selectClinic()).
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
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load facility details.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

        // Branches
        if (detail.branches.isNotEmpty) ...[
          const Text('Branches & Locations',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _Colors.tealDark)),
          const SizedBox(height: 10),
          ...detail.branches.map((b) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 14, color: _Colors.textMuted),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(b.branchNameEn,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _Colors.textMain)),
                        ),
                        if (b.isPrimary)
                          const _Badge(
                              label: 'Primary Location',
                              bg: Color(0xFFCCFBF1),
                              fg: _Colors.tealDark),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(b.addressLine1,
                        style: const TextStyle(
                            fontSize: 12, color: _Colors.textMuted)),
                    if ((b.phone ?? '').isNotEmpty) ...[
                      const SizedBox(height: 5),
                      _InfoRow(icon: Icons.phone_outlined, label: b.phone!),
                    ],
                  ],
                ),
              )),
        ],

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

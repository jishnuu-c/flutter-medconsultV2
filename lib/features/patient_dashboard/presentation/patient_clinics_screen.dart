import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/clinic_service.dart';
import '../../clinic_admin/data/clinic_models.dart';

/// Mirrors Angular's patient-dashboard/clinic-explorer ("Clinics & Branches").
class PatientClinicsScreen extends ConsumerStatefulWidget {
  const PatientClinicsScreen({super.key});

  @override
  ConsumerState<PatientClinicsScreen> createState() =>
      _PatientClinicsScreenState();
}

class _PatientClinicsScreenState extends ConsumerState<PatientClinicsScreen> {
  bool _isLoading = false;
  List<ClinicModel> _clinics = [];
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
      final res = await ref.read(clinicServiceProvider).getAllClinics();
      if (mounted) setState(() => _clinics = res);
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
    return _clinics.where((c) => c.nameEn.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 700;
    return RefreshIndicator(
      onRefresh: _loadClinics,
      child: ListView(
        padding: EdgeInsets.all(isNarrow ? 16 : 24),
        children: [
          Text('Clinics & Branches',
              style: TextStyle(
                  fontSize: isNarrow ? 19 : 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain)),
          const SizedBox(height: 4),
          const Text('Explore verified clinics and their branches.',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by clinic name',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.borderGray)),
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  _clinics.isEmpty
                      ? 'No clinics found in system database.'
                      : 'No clinics match your search.',
                  style: const TextStyle(color: AppTheme.textMuted),
                ),
              ),
            )
          else
            LayoutBuilder(builder: (context, constraints) {
              final cols =
                  isNarrow ? 1 : (constraints.maxWidth ~/ 300).clamp(1, 4);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisExtent: 176,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _filtered.length,
                itemBuilder: (context, i) {
                  final clinic = _filtered[i];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppTheme.borderGray),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                border: Border.all(color: AppTheme.borderGray),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: const Text('🏥',
                                  style: TextStyle(fontSize: 18)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(clinic.nameEn,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14)),
                                  Text(clinic.nameAr,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          color: AppTheme.textMuted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.only(top: 10),
                          decoration: const BoxDecoration(
                            border: Border(
                                top: BorderSide(color: AppTheme.borderGray)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: clinic.isActive
                                      ? AppTheme.primaryLightTeal
                                      : const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  clinic.mohVerified
                                      ? 'MOH VERIFIED'
                                      : 'UNVERIFIED',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: clinic.isActive
                                        ? AppTheme.primaryTeal
                                        : AppTheme.dangerRed,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                  '⭐ ${clinic.overallRating} (${clinic.reviewCount})',
                                  style: const TextStyle(
                                      fontSize: 12, color: AppTheme.textMuted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            }),
        ],
      ),
    );
  }
}

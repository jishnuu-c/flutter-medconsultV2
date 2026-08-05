import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../clinic_admin/data/doctor_models.dart';

/// Mirrors Angular's patient-dashboard/doctors (browse & search doctors).
class PatientDoctorsScreen extends ConsumerStatefulWidget {
  const PatientDoctorsScreen({super.key});

  @override
  ConsumerState<PatientDoctorsScreen> createState() =>
      _PatientDoctorsScreenState();
}

class _PatientDoctorsScreenState extends ConsumerState<PatientDoctorsScreen> {
  bool _isLoading = false;
  List<DoctorModel> _doctors = [];
  final _searchController = TextEditingController();

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
      final res = await ref.read(doctorServiceProvider).getAllDoctors();
      if (mounted) setState(() => _doctors = res);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load doctors: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<DoctorModel> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _doctors;
    return _doctors.where((d) => d.fullName.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 700;
    return RefreshIndicator(
      onRefresh: _loadDoctors,
      child: ListView(
        padding: EdgeInsets.all(isNarrow ? 16 : 24),
        children: [
          Text('Browse Doctors',
              style: TextStyle(
                  fontSize: isNarrow ? 19 : 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain)),
          const SizedBox(height: 4),
          const Text('Find and book a consultation with a verified doctor.',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by doctor name',
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
                  _doctors.isEmpty
                      ? 'No doctors found in system database.'
                      : 'No doctors match your search.',
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
                  mainAxisExtent: 190,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _filtered.length,
                itemBuilder: (context, i) {
                  final doc = _filtered[i];
                  final initials = doc.fullName.isNotEmpty
                      ? doc.fullName
                          .trim()
                          .split(' ')
                          .take(2)
                          .map((s) => s.isNotEmpty ? s[0] : '')
                          .join()
                          .toUpperCase()
                      : 'DR';
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
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLightTeal,
                                border: Border.all(color: AppTheme.primaryTeal),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              alignment: Alignment.center,
                              child: Text(initials,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primaryTeal)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${doc.title.value}. ${doc.fullName}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14)),
                                  Text(
                                      '⭐ ${doc.overallRating} (${doc.reviewCount})',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textMuted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('${doc.experienceYears} years experience',
                            style: const TextStyle(
                                fontSize: 12.5, color: AppTheme.textMuted)),
                        const Spacer(),
                        Row(
                          children: [
                            Text('SAR ${doc.consultationFeeSar}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryTeal,
                                    fontSize: 13.5)),
                            const Spacer(),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryTeal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                textStyle: const TextStyle(fontSize: 12.5),
                              ),
                              onPressed: () =>
                                  context.go('/patient/book-appointment'),
                              child: const Text('Book'),
                            ),
                          ],
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

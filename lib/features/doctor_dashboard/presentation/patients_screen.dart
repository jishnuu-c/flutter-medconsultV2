import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/clinical_record_service.dart';

class DoctorPatientsScreen extends ConsumerStatefulWidget {
  const DoctorPatientsScreen({super.key});

  @override
  ConsumerState<DoctorPatientsScreen> createState() => _DoctorPatientsScreenState();
}

class _PatientInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _PatientInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13, color: AppTheme.textMain)),
        ),
      ],
    );
  }
}

class _DoctorPatientsScreenState extends ConsumerState<DoctorPatientsScreen> {
  final _searchController = TextEditingController();
  bool _isLoading = false;
  List<dynamic> _prescriptions = [];

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref.read(clinicalRecordServiceProvider).searchPrescriptions();
      setState(() => _prescriptions = res);
    } catch (_) {
      _populateMockPrescriptions();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateMockPrescriptions() {
    _prescriptions = [
      {
        'prescriptionId': 'rx-101',
        'patientName': 'Sarah Ahmed',
        'medication': 'Amoxicillin 500mg',
        'dosage': '1 capsule every 8 hours',
        'duration': '7 Days',
        'status': 'ACTIVE',
        'date': '2026-07-20',
      },
      {
        'prescriptionId': 'rx-102',
        'patientName': 'Mohammed Al-Harbi',
        'medication': 'Lisinopril 10mg',
        'dosage': '1 tablet daily in the morning',
        'duration': '30 Days',
        'status': 'ACTIVE',
        'date': '2026-07-15',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Patient EMR Records',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Search patient profiles, active prescriptions, and clinical history.',
                      style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Search input
            Container(
              constraints: const BoxConstraints(maxWidth: 400),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search patient by name or EMR ID...',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (val) => setState(() {}),
              ),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _prescriptions.isEmpty
                      ? const Center(
                          child: Text('No prescriptions found.', style: TextStyle(color: AppTheme.textMuted)),
                        )
                      : ListView.separated(
                          itemCount: _prescriptions.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final rx = _prescriptions[index];
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            rx['patientName'] ?? 'Patient',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textMain),
                                          ),
                                        ),
                                        Chip(
                                          label: Text(rx['status'] ?? 'ACTIVE', style: const TextStyle(fontSize: 12)),
                                          backgroundColor: AppTheme.primaryLightTeal,
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    _PatientInfoRow(label: 'Medication', value: rx['medication'] ?? ''),
                                    const SizedBox(height: 6),
                                    _PatientInfoRow(label: 'Dosage', value: rx['dosage'] ?? ''),
                                    const SizedBox(height: 6),
                                    _PatientInfoRow(label: 'Duration', value: rx['duration'] ?? ''),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

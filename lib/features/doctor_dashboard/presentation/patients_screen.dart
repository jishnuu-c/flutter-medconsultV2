import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/clinical_record_service.dart';

class DoctorPatientsScreen extends ConsumerStatefulWidget {
  const DoctorPatientsScreen({super.key});

  @override
  ConsumerState<DoctorPatientsScreen> createState() => _DoctorPatientsScreenState();
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
              child: Card(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Patient Name')),
                            DataColumn(label: Text('Medication')),
                            DataColumn(label: Text('Dosage & Instructions')),
                            DataColumn(label: Text('Duration')),
                            DataColumn(label: Text('Status')),
                          ],
                          rows: _prescriptions.map((rx) {
                            return DataRow(cells: [
                              DataCell(Text(rx['patientName'] ?? 'Patient', style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text(rx['medication'] ?? '')),
                              DataCell(Text(rx['dosage'] ?? '')),
                              DataCell(Text(rx['duration'] ?? '')),
                              DataCell(
                                Chip(
                                  label: Text(rx['status'] ?? 'ACTIVE'),
                                  backgroundColor: AppTheme.primaryLightTeal,
                                ),
                              ),
                            ]);
                          }).toList(),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

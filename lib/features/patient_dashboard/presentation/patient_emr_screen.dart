import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../doctor_dashboard/data/clinical_record_service.dart';

class PatientEmrScreen extends ConsumerStatefulWidget {
  const PatientEmrScreen({super.key});

  @override
  ConsumerState<PatientEmrScreen> createState() => _PatientEmrScreenState();
}

class _PatientEmrScreenState extends ConsumerState<PatientEmrScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = false;
  List<dynamic> _prescriptions = [];
  List<dynamic> _vitals = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadEMRData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadEMRData() async {
    setState(() => _isLoading = true);
    try {
      final crService = ref.read(clinicalRecordServiceProvider);
      final rxRes = await crService.searchPrescriptions();
      final vitalsRes = await crService.searchVitals();
      setState(() {
        _prescriptions = rxRes;
        _vitals = vitalsRes;
      });
    } catch (_) {
      _populateMockEMR();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateMockEMR() {
    _prescriptions = [
      {
        'prescriptionId': 'rx-201',
        'doctorName': 'Dr. Tariq Al-Mansoor',
        'medication': 'Amoxicillin 500mg',
        'dosage': '1 capsule every 8 hours',
        'duration': '7 Days',
        'status': 'ACTIVE',
        'issuedDate': '2026-07-20',
      },
    ];
    _vitals = [
      {
        'vitalId': 'vt-1',
        'bp': '120/80 mmHg',
        'pulse': '72 bpm',
        'temp': '36.8 °C',
        'date': '2026-07-20',
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
            const Text(
              'My Medical Records (EMR)',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textMain),
            ),
            const SizedBox(height: 4),
            const Text(
              'Access your clinical prescriptions, vital signs history, and lab reports.',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 20),

            // TabBar
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: AppTheme.borderGray)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: AppTheme.primaryTeal,
                unselectedLabelColor: AppTheme.textMuted,
                tabs: const [
                  Tab(text: 'Prescriptions'),
                  Tab(text: 'Vitals History'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Prescriptions
                  Card(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _prescriptions.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final rx = _prescriptions[index];
                              return ListTile(
                                leading: const Icon(Icons.medication_outlined, color: AppTheme.primaryTeal, size: 28),
                                title: Text(rx['medication'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Doctor: ${rx['doctorName'] ?? "Dr. Practitioner"}\nDosage: ${rx['dosage']} (${rx['duration']})'),
                                trailing: Chip(label: Text(rx['status'] ?? 'ACTIVE'), backgroundColor: AppTheme.primaryLightTeal),
                              );
                            },
                          ),
                  ),

                  // Tab 2: Vitals History
                  Card(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _vitals.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final vt = _vitals[index];
                              return ListTile(
                                leading: const Icon(Icons.favorite_outline, color: AppTheme.dangerRed, size: 28),
                                title: Text('Blood Pressure: ${vt['bp']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Pulse: ${vt['pulse']} | Temp: ${vt['temp']}'),
                                trailing: Text(vt['date'] ?? '', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

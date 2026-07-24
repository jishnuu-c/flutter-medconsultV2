import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../doctor_dashboard/data/clinical_record_service.dart';
import '../data/patient_service.dart';

class PatientEmrScreen extends ConsumerStatefulWidget {
  const PatientEmrScreen({super.key});

  @override
  ConsumerState<PatientEmrScreen> createState() => _PatientEmrScreenState();
}

class _PatientEmrScreenState extends ConsumerState<PatientEmrScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = false;
  bool _needProfileInit = false;
  String? _patientId;
  List<dynamic> _prescriptions = [];
  List<dynamic> _vitals = [];
  List<dynamic> _labResults = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
      final profile = await ref.read(patientServiceProvider).getMyProfile();
      _patientId = profile['patientId'];
      final crService = ref.read(clinicalRecordServiceProvider);
      final results = await Future.wait([
        crService.searchPrescriptions(patientId: _patientId),
        crService.searchVitals(patientId: _patientId),
        crService.searchLabResults(patientId: _patientId),
      ]);
      setState(() {
        _prescriptions = results[0];
        _vitals = results[1];
        _labResults = results[2];
        _needProfileInit = false;
      });
    } catch (e) {
      final status = _statusCodeOf(e);
      if (status == 404) {
        setState(() => _needProfileInit = true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load medical records.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int? _statusCodeOf(dynamic e) {
    try {
      return e.response?.statusCode;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_needProfileInit) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Initialize your patient profile to view medical records.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.go('/patient/profile'),
                  child: const Text('Setup Profile'),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
                  Tab(text: 'Lab Results'),
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
                        : _prescriptions.isEmpty
                            ? const Center(child: Text('No prescriptions on file yet.'))
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: _prescriptions.length,
                                separatorBuilder: (context, index) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final rx = _prescriptions[index];
                                  return ListTile(
                                    leading: const Icon(Icons.medication_outlined, color: AppTheme.primaryTeal, size: 28),
                                    title: Text(rx['naphiesReference'] ?? 'Local Record', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                        'Issued: ${rx['issuedDate'] ?? 'N/A'} | Valid Until: ${rx['validUntil'] ?? 'N/A'}\n${rx['diagnosisNotes'] ?? 'No notes available.'}'),
                                    isThreeLine: true,
                                    trailing: Chip(
                                      label: Text(rx['status'] ?? 'ACTIVE'),
                                      backgroundColor: rx['status'] == 'ACTIVE' ? AppTheme.primaryLightTeal : Colors.red[100],
                                    ),
                                  );
                                },
                              ),
                  ),

                  // Tab 2: Vitals History
                  Card(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _vitals.isEmpty
                            ? const Center(child: Text('No vitals recorded yet.'))
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: _vitals.length,
                                separatorBuilder: (context, index) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final vt = _vitals[index];
                                  return ListTile(
                                    leading: const Icon(Icons.favorite_outline, color: AppTheme.dangerRed, size: 28),
                                    title: Text(
                                        'BP: ${vt['bloodPressureSystolic']}/${vt['bloodPressureDiastolic']} mmHg',
                                        style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text('Heart Rate: ${vt['heartRateBpm']} BPM | Weight: ${vt['weightKg']} kg | Temp: ${vt['temperatureC']} °C'),
                                    trailing: Text(vt['recordedAt']?.toString().split('T').first ?? '',
                                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                  );
                                },
                              ),
                  ),

                  // Tab 3: Lab Results
                  Card(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _labResults.isEmpty
                            ? const Center(child: Text('No lab results yet.'))
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: _labResults.length,
                                separatorBuilder: (context, index) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final lab = _labResults[index];
                                  return ListTile(
                                    leading: Icon(Icons.biotech_outlined,
                                        color: lab['overallFlag'] == 'CRITICAL'
                                            ? AppTheme.dangerRed
                                            : lab['overallFlag'] == 'ABNORMAL'
                                                ? Colors.orange
                                                : AppTheme.primaryTeal,
                                        size: 28),
                                    title: Text(lab['labName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text('${lab['reportType'] ?? ''} • ${lab['reportDate']?.toString().split('T').first ?? ''}\n${lab['doctorAnnotation'] ?? 'No clinical annotation added.'}'),
                                    isThreeLine: true,
                                    trailing: Chip(
                                      label: Text(lab['overallFlag'] ?? lab['status'] ?? ''),
                                      backgroundColor: lab['overallFlag'] == 'CRITICAL'
                                          ? Colors.red[100]
                                          : lab['overallFlag'] == 'ABNORMAL'
                                              ? Colors.orange[100]
                                              : AppTheme.primaryLightTeal,
                                    ),
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

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../doctor_dashboard/data/clinical_record_service.dart';
import '../data/patient_service.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../clinic_admin/data/doctor_models.dart';

class PatientEmrScreen extends ConsumerStatefulWidget {
  const PatientEmrScreen({super.key});

  @override
  ConsumerState<PatientEmrScreen> createState() => _PatientEmrScreenState();
}

class _PatientEmrScreenState extends ConsumerState<PatientEmrScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = false;
  bool _needProfileInit = false;
  String? _patientId;
  List<dynamic> _prescriptions = [];
  final Map<String, List<dynamic>> _rxItems = {};
  final Map<String, List<dynamic>> _adherenceLogs = {};
  List<dynamic> _vitals = [];
  List<dynamic> _labResults = [];
  String? _downloadingFileId;
  Map<String, DoctorModel> _doctorsMap = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDoctors();
    _loadEMRData();
  }

  // Mirrors emr.component.ts loadDoctors(): fetch all doctors up front so
  // prescription cards can show "Prescribed By: Dr. X".
  Future<void> _loadDoctors() async {
    try {
      final docs = await ref.read(doctorServiceProvider).getAllDoctors();
      final map = <String, DoctorModel>{};
      for (final d in docs) {
        map[d.doctorId] = d;
      }
      if (mounted) setState(() => _doctorsMap = map);
    } catch (e) {
      debugPrint('EMR: loadDoctors failed: $e');
    }
  }

  // Mirrors emr.component.ts getDoctorDisplayName. No Arabic locale in this
  // app (unlike the Angular LanguageService), so the prefix is always 'Dr.'.
  String _getDoctorDisplayName(DoctorModel? d) {
    if (d == null) return '';
    final name = d.fullName.trim();
    final nameLower = name.toLowerCase();
    if (nameLower.startsWith('dr') ||
        nameLower.startsWith('doctor') ||
        nameLower.startsWith('prof') ||
        nameLower.startsWith('consultant') ||
        nameLower.startsWith('specialist') ||
        name.startsWith('د.')) {
      return name;
    }
    return 'Dr. $name';
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadEMRData() async {
    setState(() => _isLoading = true);
    // Mirrors emr.component.ts checkProfileAndLoad(): getMyProfile() is
    // wrapped in its own catch (Angular's catchError(() => of(null))), so
    // ANY failure — not just a 404 — falls through to needProfileInit,
    // same as when the profile call succeeds but returns no patientId.
    dynamic profile;
    try {
      profile = await ref.read(patientServiceProvider).getMyProfile();
    } catch (e) {
      profile = null;
    }
    final patientId = profile?['patientId'];
    if (patientId == null) {
      if (mounted) {
        setState(() {
          _needProfileInit = true;
          _isLoading = false;
        });
      }
      return;
    }
    _patientId = patientId;
    try {
      final crService = ref.read(clinicalRecordServiceProvider);
      final results = await Future.wait([
        crService.searchPrescriptions(patientId: _patientId),
        crService.searchVitals(
            patientId: _patientId,
            size: 30,
            sortBy: 'recordedAt',
            sortDir: 'desc'),
        crService.searchLabResults(patientId: _patientId),
      ]);
      setState(() {
        _prescriptions = results[0];
        _vitals = results[1];
        _labResults = results[2];
        _needProfileInit = false;
      });
      _loadPrescriptionDetails();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load medical records.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Mirrors emr.component.ts loadPrescriptionItems + loadAdherenceLogs: fan out
  // per-prescription item fetches, then per-item adherence log fetches.
  Future<void> _loadPrescriptionDetails() async {
    final crService = ref.read(clinicalRecordServiceProvider);
    for (final rx in _prescriptions) {
      // toString(), not `as String?` — a strict cast throws if the backend
      // sends prescriptionId as a non-String, which used to kill this whole
      // loop silently (caught nowhere, so every later rx's items never loaded).
      final rxId = rx['prescriptionId']?.toString();
      if (rxId == null) continue;
      try {
        final items = await crService.getPrescriptionItems(rxId);
        if (mounted) setState(() => _rxItems[rxId] = items);
        for (final item in items) {
          final itemId = item['itemId']?.toString();
          if (itemId == null) continue;
          try {
            final logs = await crService.searchAdherence(
                patientId: _patientId, rxItemId: itemId);
            if (mounted) setState(() => _adherenceLogs[itemId] = logs);
          } catch (e) {
            debugPrint('EMR: adherence load failed for item $itemId: $e');
          }
        }
      } catch (e) {
        debugPrint('EMR: prescription items load failed for rx $rxId: $e');
      }
    }
  }

  Future<void> _logAdherence(String itemId, bool taken,
      {String? skippedReason}) async {
    final todayStr = DateTime.now().toIso8601String().split('T').first;
    final payload = {
      'rxItemId': itemId,
      'patientId': _patientId,
      'logDate': todayStr,
      'taken': taken,
      if (taken) 'takenAt': DateTime.now().toIso8601String(),
      if (!taken) 'skippedReason': skippedReason ?? 'No Reason',
    };
    try {
      await ref.read(clinicalRecordServiceProvider).createAdherence(payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Daily adherence logged!')),
        );
      }
      final logs = await ref
          .read(clinicalRecordServiceProvider)
          .searchAdherence(patientId: _patientId, rxItemId: itemId);
      if (mounted) setState(() => _adherenceLogs[itemId] = logs);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Adherence record already exists or failed to save.')),
        );
      }
    }
  }

  // ── Vitals modal (mirrors emr.component.html's Record Vitals modal) ──
  void _openVitalModal() {
    final systolicCtrl = TextEditingController(text: '120');
    final diastolicCtrl = TextEditingController(text: '80');
    final heartRateCtrl = TextEditingController(text: '72');
    final glucoseCtrl = TextEditingController(text: '5.5');
    final weightCtrl = TextEditingController(text: '70');
    final tempCtrl = TextEditingController(text: '36.6');
    final notesCtrl = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final screenWidth = MediaQuery.of(context).size.width;
          final isNarrow = screenWidth < 480;
          return AlertDialog(
            title: const Text('Log New Vital Entry'),
            content: SizedBox(
              width: isNarrow ? screenWidth * 0.85 : 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _vitalFieldRow(systolicCtrl, 'Systolic BP (mmHg)',
                        diastolicCtrl, 'Diastolic BP (mmHg)', isNarrow),
                    const SizedBox(height: 12),
                    _vitalFieldRow(heartRateCtrl, 'Heart Rate (BPM)',
                        glucoseCtrl, 'Blood Glucose (mmol/L)', isNarrow),
                    const SizedBox(height: 12),
                    _vitalFieldRow(weightCtrl, 'Weight (kg)', tempCtrl,
                        'Body Temp (°C)', isNarrow),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Log Notes',
                          hintText: 'Context, symptom notes...'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        final payload = {
                          'patientId': _patientId,
                          'bloodPressureSystolic':
                              int.tryParse(systolicCtrl.text) ?? 120,
                          'bloodPressureDiastolic':
                              int.tryParse(diastolicCtrl.text) ?? 80,
                          'heartRateBpm':
                              int.tryParse(heartRateCtrl.text) ?? 72,
                          'bloodGlucoseMmol': double.tryParse(glucoseCtrl.text),
                          'weightKg': double.tryParse(weightCtrl.text),
                          'temperatureC': double.tryParse(tempCtrl.text),
                          'notes': notesCtrl.text.trim(),
                          'recordedAt': DateTime.now().toIso8601String(),
                          'source': 'PATIENT_APP',
                        };
                        try {
                          await ref
                              .read(clinicalRecordServiceProvider)
                              .createVital(payload);
                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Vitals logged successfully.')),
                            );
                          }
                          final vitals = await ref
                              .read(clinicalRecordServiceProvider)
                              .searchVitals(
                                  patientId: _patientId,
                                  size: 30,
                                  sortBy: 'recordedAt',
                                  sortDir: 'desc');
                          if (mounted) setState(() => _vitals = vitals);
                        } catch (_) {
                          setDialogState(() => isSaving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Failed to record vital metrics.')),
                            );
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Record Vitals'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Stacks the two fields vertically on narrow screens instead of forcing
  // a cramped side-by-side Row, so the modal stays usable on phones.
  Widget _vitalFieldRow(TextEditingController c1, String l1,
      TextEditingController c2, String l2, bool isNarrow) {
    final f1 = TextField(
        controller: c1,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: l1));
    final f2 = TextField(
        controller: c2,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: l2));
    if (isNarrow) {
      return Column(children: [f1, const SizedBox(height: 12), f2]);
    }
    return Row(children: [
      Expanded(child: f1),
      const SizedBox(width: 12),
      Expanded(child: f2)
    ]);
  }

  // ── Lab file download (mirrors emr.component.ts downloadLabFile) ────
  Future<void> _downloadLabFile(String fileId) async {
    setState(() => _downloadingFileId = fileId);
    try {
      final bytes =
          await ref.read(clinicalRecordServiceProvider).downloadFile(fileId);
      final shortId = fileId.length > 8 ? fileId.substring(0, 8) : fileId;
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Save Lab Report',
        fileName: 'Lab_Report_$shortId.pdf',
        bytes: Uint8List.fromList(bytes),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(savedPath != null
                  ? 'Lab attachment saved to $savedPath'
                  : 'Download cancelled.')),
        );
      }
    } catch (e) {
      debugPrint('EMR: lab file download failed for $fileId: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not download lab attachment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingFileId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    if (_needProfileInit) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'Initialize your patient profile to view medical records.',
                    textAlign: TextAlign.center),
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
      body: RefreshIndicator(
        onRefresh: _loadEMRData,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border:
                      Border(bottom: BorderSide(color: AppTheme.borderGray)),
                ),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: isMobile,
                  labelColor: AppTheme.primaryTeal,
                  unselectedLabelColor: AppTheme.textMuted,
                  tabAlignment: isMobile ? TabAlignment.start : null,
                  tabs: const [
                    Tab(text: '💊 Prescriptions'),
                    Tab(text: '📊 Vitals History'),
                    Tab(text: '🔬 Lab Results'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPrescriptionsTab(isMobile),
                    _buildVitalsTab(isMobile, screenWidth),
                    _buildLabsTab(isMobile),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrescriptionsTab(bool isMobile) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_prescriptions.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No prescriptions found on your EMR file.')));
    }
    return ListView.separated(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      itemCount: _prescriptions.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final rx = _prescriptions[index];
        final rxId = rx['prescriptionId'] as String?;
        final items = rxId != null ? (_rxItems[rxId] ?? []) : [];
        final isActive = rx['status'] == 'ACTIVE';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 160),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Prescription Reference: ${rx['naphiesReference'] ?? 'Local Record'}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryTeal)),
                          const SizedBox(height: 2),
                          Text(
                              'Issued: ${_fmtDate(rx['issuedDate'])} | Valid Until: ${_fmtDate(rx['validUntil'])}',
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.textMuted)),
                          if (_doctorsMap[rx['doctorId']?.toString()] !=
                              null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Prescribed By: ${_getDoctorDisplayName(_doctorsMap[rx['doctorId']?.toString()])}',
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.textMuted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Chip(
                      label: Text(rx['status'] ?? 'ACTIVE'),
                      backgroundColor: isActive
                          ? AppTheme.primaryLightTeal
                          : Colors.red[100],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('DIAGNOSIS & CLINICAL NOTES',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMuted)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppTheme.backgroundApp,
                      border: Border.all(color: AppTheme.borderGray),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(
                      rx['diagnosisNotes'] ?? 'No diagnosis notes available.',
                      style: const TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 12),
                const Text('PRESCRIBED MEDICATIONS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMuted)),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  const Text('No medication items on this prescription.',
                      style: TextStyle(fontSize: 13, color: AppTheme.textMuted))
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // 1 column under ~420px, 2 columns otherwise — keeps med
                      // cards readable on phones without wasting desktop space.
                      final columns = constraints.maxWidth < 420 ? 1 : 2;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          // Taller than before to fit the adherence tracker
                          // header, today-status/action row, and 7-day dot
                          // history strip added below the medication details.
                          mainAxisExtent: 270,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, i) =>
                            _buildMedicationCard(items[i]),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Mirrors emr.component.ts getAdherenceLogForToday.
  dynamic _adherenceLogForToday(String? itemId) {
    if (itemId == null) return null;
    final logs = _adherenceLogs[itemId];
    if (logs == null || logs.isEmpty) return null;
    final todayStr = DateTime.now().toIso8601String().split('T').first;
    for (final log in logs) {
      if (log['logDate'] == todayStr) return log;
    }
    return null;
  }

  // Mirrors emr.component.ts getLast7DaysLogs: builds the last 7 days
  // (oldest first, today last) with each day's taken/skipped/none status.
  List<Map<String, dynamic>> _last7DaysLogs(String? itemId) {
    final logs = itemId != null ? (_adherenceLogs[itemId] ?? []) : [];
    final todayStr = DateTime.now().toIso8601String().split('T').first;
    final result = <Map<String, dynamic>>[];
    for (int i = 6; i >= 0; i--) {
      final d = DateTime.now().subtract(Duration(days: i));
      final dateStr = d.toIso8601String().split('T').first;
      final log = logs.firstWhere(
        (l) => l['logDate'] == dateStr,
        orElse: () => null,
      );
      String status = 'none';
      if (log != null) {
        status = log['taken'] == true ? 'taken' : 'skipped';
      }
      result.add({
        'date': d,
        'status': status,
        'label': _weekdayNarrow(d),
        'isToday': dateStr == todayStr,
      });
    }
    return result;
  }

  String _weekdayNarrow(DateTime d) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return labels[d.weekday - 1];
  }

  Widget _buildMedicationCard(dynamic item) {
    final itemId = item['itemId']?.toString();
    final todayLog = _adherenceLogForToday(itemId);
    final last7 = _last7DaysLogs(itemId);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          border: Border.all(color: AppTheme.borderGray),
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item['drugName'] ?? '',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: AppTheme.primaryTeal)),
          const SizedBox(height: 4),
          Text(
              'Dosage: ${item['dosage'] ?? '-'} | Route: ${item['route'] ?? '-'}',
              style: const TextStyle(fontSize: 12)),
          Text('Frequency: ${item['frequency'] ?? '-'}',
              style: const TextStyle(fontSize: 12)),
          Text(
              'Duration: ${item['durationDays'] ?? '-'} days | Refills: ${item['refillsUsed'] ?? 0}/${item['refillsAllowed'] ?? 0}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          const Spacer(),
          const Divider(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Adherence Tracker',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              if (todayLog != null)
                Text(
                  todayLog['taken'] == true ? 'Taken Today' : 'Skipped Today',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: todayLog['taken'] == true
                        ? AppTheme.successGreen
                        : AppTheme.dangerRed,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Daily logger actions — only shown while today isn't logged yet,
          // matching emr.component.html's *ngIf="!getAdherenceLogForToday(...)".
          if (todayLog == null)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.successGreen,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed:
                      itemId == null ? null : () => _logAdherence(itemId, true),
                  child: const Text('✓ Mark Taken',
                      style: TextStyle(fontSize: 12)),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.dangerRed,
                    side: const BorderSide(color: AppTheme.dangerRed),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: itemId == null
                      ? null
                      : () => _logAdherence(itemId, false,
                          skippedReason: 'Patient skipped'),
                  child: const Text('✕ Mark Skipped',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          const SizedBox(height: 8),
          // 7-day dot history strip, oldest to today.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: last7.map((day) {
              final status = day['status'] as String;
              Color dotColor;
              Widget? icon;
              if (status == 'taken') {
                dotColor = AppTheme.successGreen;
                icon = const Icon(Icons.check, size: 10, color: Colors.white);
              } else if (status == 'skipped') {
                dotColor = AppTheme.dangerRed;
                icon = const Icon(Icons.close, size: 10, color: Colors.white);
              } else {
                dotColor = AppTheme.borderGray;
                icon = null;
              }
              final isToday = day['isToday'] == true;
              return Tooltip(
                message: _fmtDate((day['date'] as DateTime).toIso8601String()),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(day['label'] as String,
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight:
                                isToday ? FontWeight.bold : FontWeight.normal,
                            color: isToday
                                ? AppTheme.primaryTeal
                                : AppTheme.textMuted)),
                    const SizedBox(height: 2),
                    Container(
                      width: 16,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                        border: isToday
                            ? Border.all(
                                color: AppTheme.primaryTeal, width: 1.5)
                            : null,
                      ),
                      child: icon,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildVitalsTab(bool isMobile, double screenWidth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              isMobile ? 12 : 16, 16, isMobile ? 12 : 16, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              const Text('Vital Metrics History',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryTeal)),
              ElevatedButton.icon(
                onPressed: _openVitalModal,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Log New Vitals'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _vitals.isEmpty
                  ? const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                              'No vitals records listed. Tap above to log your first metric.')))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth < 420
                            ? 1
                            : (constraints.maxWidth < 900 ? 2 : 3);
                        return GridView.builder(
                          padding: EdgeInsets.all(isMobile ? 12 : 16),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            mainAxisExtent: 190,
                          ),
                          itemCount: _vitals.length,
                          itemBuilder: (context, index) =>
                              _buildVitalCard(_vitals[index]),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildVitalCard(dynamic v) {
    final source = (v['source'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          border: Border.all(color: AppTheme.borderGray),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                  child: Text('🗓️ ${_fmtDateTime(v['recordedAt'])}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textMuted),
                      overflow: TextOverflow.ellipsis)),
              Chip(
                label: Text(source.replaceAll('_', ' '),
                    style: const TextStyle(fontSize: 10)),
                backgroundColor: source == 'PATIENT_APP'
                    ? AppTheme.primaryLightTeal
                    : Colors.blue[50],
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const Divider(height: 12),
          _vitalRow('Blood Pressure',
              '${v['bloodPressureSystolic'] ?? '-'}/${v['bloodPressureDiastolic'] ?? '-'} mmHg'),
          _vitalRow('Heart Rate', '${v['heartRateBpm'] ?? '-'} BPM',
              valueColor: AppTheme.dangerRed),
          if (v['bloodGlucoseMmol'] != null)
            _vitalRow('Blood Glucose', '${v['bloodGlucoseMmol']} mmol/L'),
          if (v['weightKg'] != null) _vitalRow('Weight', '${v['weightKg']} kg'),
          if (v['oxygenSaturation'] != null)
            _vitalRow('O2 Saturation', '${v['oxygenSaturation']}%'),
        ],
      ),
    );
  }

  Widget _vitalRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? AppTheme.textMain)),
        ],
      ),
    );
  }

  Widget _buildLabsTab(bool isMobile) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_labResults.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No lab report files uploaded on your file.')));
    }
    return ListView.separated(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      itemCount: _labResults.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final lab = _labResults[index];
        final flag = (lab['overallFlag'] ?? '').toString();
        final fileId = lab['fileId'] as String?;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 160),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(lab['labName'] ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryTeal,
                                  fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(
                              '${lab['reportType'] ?? ''} | Date: ${_fmtDate(lab['reportDate'])}',
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        Chip(
                          label:
                              Text(flag, style: const TextStyle(fontSize: 11)),
                          backgroundColor: flag == 'CRITICAL'
                              ? Colors.red[100]
                              : (flag == 'ABNORMAL'
                                  ? Colors.orange[100]
                                  : AppTheme.primaryLightTeal),
                        ),
                        Chip(
                            label: Text(lab['status'] ?? '',
                                style: const TextStyle(fontSize: 11)),
                            backgroundColor: Colors.blue[50]),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text("DOCTOR'S ANNOTATIONS",
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMuted)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppTheme.backgroundApp,
                      border: Border.all(color: AppTheme.borderGray),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(
                      lab['doctorAnnotation'] ??
                          'No clinical annotation added.',
                      style: const TextStyle(fontSize: 13)),
                ),
                if (fileId != null) ...[
                  const SizedBox(height: 10),
                  const Divider(),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Text(
                          '📎 Attachment (ID: ${fileId.substring(0, fileId.length > 8 ? 8 : fileId.length)}...)',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textMuted)),
                      ElevatedButton.icon(
                        onPressed: _downloadingFileId == fileId
                            ? null
                            : () => _downloadLabFile(fileId),
                        icon: _downloadingFileId == fileId
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.download, size: 16),
                        label: const Text('Download',
                            style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return 'N/A';
    final str = raw.toString();
    return str.split('T').first;
  }

  String _fmtDateTime(dynamic raw) {
    if (raw == null) return 'N/A';
    final str = raw.toString();
    if (str.contains('T')) {
      final parts = str.split('T');
      final timePart =
          parts[1].length >= 5 ? parts[1].substring(0, 5) : parts[1];
      return '${parts[0]} $timePart';
    }
    return str;
  }
}

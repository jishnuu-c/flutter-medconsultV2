import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/appointment_service.dart';
import '../data/clinical_record_service.dart';
import '../data/patient_record_service.dart';
import '../data/consultation_service.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../../core/auth/auth_provider.dart';

class DoctorPatientsScreen extends ConsumerStatefulWidget {
  const DoctorPatientsScreen({super.key});

  @override
  ConsumerState<DoctorPatientsScreen> createState() =>
      _DoctorPatientsScreenState();
}

class _PatientInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _PatientInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontSize: 13, color: AppTheme.textMain),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoctorPatientsScreenState extends ConsumerState<DoctorPatientsScreen> {
  bool _isLoadingPatients = false;
  bool _isLoadingEmr = false;

  List<Map<String, String>> _patientList = [];
  String _selectedPatientId = '';
  String _selectedPatientName = '';

  // EMR Chart details — mirrors patients.component.ts
  Map<String, dynamic>? _healthProfile;
  List<dynamic> _allergies = [];
  List<dynamic> _chronicConditions = [];
  List<dynamic> _prescriptions = [];
  final Map<String, List<dynamic>> _selectedRxItems = {};
  List<dynamic> _vitals = [];
  List<dynamic> _labResults = [];

  @override
  void initState() {
    super.initState();
    _loadDoctorPatients();
  }

  String _errorMessage(Object e) {
    if (e is DioException) {
      return e.response?.statusMessage ?? e.message ?? 'Network error';
    }
    return e.toString();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppTheme.dangerRed : null,
      ),
    );
  }

  Future<void> _loadDoctorPatients() async {
    setState(() => _isLoadingPatients = true);
    final map = <String, String>{};

    void updateList() {
      if (!mounted) return;
      setState(() {
        _patientList = map.entries
            .map((e) => {'patientId': e.key, 'patientName': e.value})
            .toList();
      });
    }

    // 1. Patients from upcoming appointments
    try {
      final apps = await ref
          .read(appointmentServiceProvider)
          .getDoctorUpcomingAppointments();
      for (final app in apps) {
        final id = app['patientId'];
        final name = app['patientName'];
        if (id != null) map[id.toString()] = (name ?? '').toString();
      }
      updateList();
    } catch (e) {
      debugPrint('appointments error: ${_errorMessage(e)}');
    }

    // 2. Patients from tele-consultations, mirrors patients.component.ts fallback
    try {
      final user = ref.read(authNotifierProvider).currentUser;
      List<dynamic> consultations = [];
      try {
        consultations = await ref
            .read(consultationServiceProvider)
            .getConsultationsByDoctor(user?.id ?? '', page: 0, size: 100);
      } catch (_) {
        // fall back to resolving doctorId via doctor list, same as Angular
        final docs = await ref.read(doctorServiceProvider).getAllDoctors();
        final doc = docs.firstWhere(
          (d) =>
              (user != null && d.userId == user.id) ||
              (user != null &&
                  d.fullName.toLowerCase() == user.fullName.toLowerCase()),
          orElse: () => docs.isNotEmpty ? docs.first : throw 'no doctor',
        );
        consultations = await ref
            .read(consultationServiceProvider)
            .getConsultationsByDoctor(doc.doctorId, page: 0, size: 100);
      }
      for (final c in consultations) {
        final id = c['patientId'];
        final name = c['patientName'];
        if (id != null) map[id.toString()] = (name ?? '').toString();
      }
      updateList();
    } catch (e) {
      debugPrint('consultations error: ${_errorMessage(e)}');
    }

    if (mounted) setState(() => _isLoadingPatients = false);

    if (_patientList.isEmpty && mounted) {
      _toast(
          'No patients found — no upcoming appointments or consultations for this doctor.');
    }
  }

  void _onPatientSelect(String? patientId) {
    setState(() {
      _selectedPatientId = patientId ?? '';
      final opt = _patientList.firstWhere(
        (p) => p['patientId'] == _selectedPatientId,
        orElse: () => {'patientId': '', 'patientName': ''},
      );
      _selectedPatientName = opt['patientName'] ?? '';
    });

    if (_selectedPatientId.isEmpty) {
      _clearPatientDetails();
      return;
    }
    _loadPatientEmr();
  }

  void _clearPatientDetails() {
    setState(() {
      _healthProfile = null;
      _allergies = [];
      _chronicConditions = [];
      _prescriptions = [];
      _selectedRxItems.clear();
      _vitals = [];
      _labResults = [];
    });
  }

  Future<void> _loadPatientEmr() async {
    setState(() => _isLoadingEmr = true);
    final patientId = _selectedPatientId;

    // Independent lookups — one failing must not block the rest, same as Angular.
    ref
        .read(patientRecordServiceProvider)
        .getPatientHealthProfile(patientId)
        .then((profile) {
      if (mounted) setState(() => _healthProfile = profile);
    }).catchError((e) {
      debugPrint('healthProfile error: ${_errorMessage(e)}');
      if (mounted) setState(() => _healthProfile = null);
    });

    ref
        .read(patientRecordServiceProvider)
        .getPatientAllergies(patientId)
        .then((data) {
      if (mounted) setState(() => _allergies = data);
    }).catchError((e) {
      debugPrint('allergies error: ${_errorMessage(e)}');
      if (mounted) setState(() => _allergies = []);
    });

    ref
        .read(patientRecordServiceProvider)
        .getPatientChronicConditions(patientId)
        .then((data) {
      if (mounted) setState(() => _chronicConditions = data);
    }).catchError((e) {
      debugPrint('chronicConditions error: ${_errorMessage(e)}');
      if (mounted) setState(() => _chronicConditions = []);
    });

    ref
        .read(clinicalRecordServiceProvider)
        .searchVitals(patientId: patientId, page: 0, size: 20)
        .then((data) {
      if (mounted) setState(() => _vitals = data);
    }).catchError((e) {
      debugPrint('vitals error: ${_errorMessage(e)}');
      if (mounted) setState(() => _vitals = []);
    });

    ref
        .read(clinicalRecordServiceProvider)
        .searchLabResults(patientId: patientId, page: 0, size: 20)
        .then((data) {
      if (mounted) setState(() => _labResults = data);
    }).catchError((e) {
      debugPrint('labResults error: ${_errorMessage(e)}');
      if (mounted) setState(() => _labResults = []);
    });

    try {
      final rx = await ref
          .read(clinicalRecordServiceProvider)
          .searchPrescriptions(patientId: patientId, page: 0, size: 20);
      if (mounted) setState(() => _prescriptions = rx);
      for (final r in rx) {
        ref
            .read(clinicalRecordServiceProvider)
            .getPrescriptionItems(r['prescriptionId'])
            .then((items) {
          if (mounted)
            setState(() => _selectedRxItems[r['prescriptionId']] = items);
        }).catchError((e) {
          debugPrint('rxItems error: ${_errorMessage(e)}');
        });
      }
    } catch (e) {
      debugPrint('prescriptions error: ${_errorMessage(e)}');
      _toast('Failed to load prescriptions: ${_errorMessage(e)}', error: true);
    } finally {
      if (mounted) setState(() => _isLoadingEmr = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Patient EMR Records',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMain),
              ),
              const SizedBox(height: 4),
              const Text(
                'Search patient profiles, active prescriptions, and clinical history.',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 16),
              _buildPatientSelector(),
              const SizedBox(height: 16),
              Expanded(
                child: _selectedPatientId.isEmpty
                    ? const Center(
                        child: Text(
                          'Choose a patient to view their chart.',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadPatientEmr,
                        child: ListView(
                          children: [
                            _buildProfileCard(),
                            const SizedBox(height: 14),
                            _buildAllergiesAndConditions(),
                            const SizedBox(height: 14),
                            _buildPrescriptionsCard(),
                            const SizedBox(height: 14),
                            _buildVitalsCard(),
                            const SizedBox(height: 14),
                            _buildLabResultsCard(),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPatientSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: _isLoadingPatients
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
                ),
              )
            : DropdownButtonFormField<String>(
                initialValue:
                    _selectedPatientId.isEmpty ? null : _selectedPatientId,
                decoration: const InputDecoration(labelText: 'Choose Patient'),
                hint: const Text('-- Choose Patient --'),
                items: _patientList
                    .map((p) => DropdownMenuItem<String>(
                          value: p['patientId'],
                          child: Text(p['patientName'] ?? ''),
                        ))
                    .toList(),
                onChanged: _onPatientSelect,
              ),
      ),
    );
  }

  Widget _buildProfileCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chart: $_selectedPatientName',
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryTeal),
            ),
            if (_healthProfile != null) ...[
              const SizedBox(height: 6),
              Text(
                'Height: ${_healthProfile!['heightCm'] ?? '-'} cm | '
                'Weight: ${_healthProfile!['weightKg'] ?? '-'} kg | '
                'BMI: ${_formatBmi(_healthProfile!['bmi'])}',
                style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(
                        'Smoking: ${_healthProfile!['smokingStatus'] ?? '-'}'),
                    backgroundColor: AppTheme.primaryLightTeal,
                    visualDensity: VisualDensity.compact,
                  ),
                  Chip(
                    label: Text(
                        'Alcohol: ${_healthProfile!['alcoholStatus'] ?? '-'}'),
                    backgroundColor: AppTheme.primaryLightTeal,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _openVitalDialog,
                  child: const Text('Record Vitals'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryDarkTeal),
                  onPressed: _openPrescriptionDialog,
                  child: const Text('Write Prescription'),
                ),
                OutlinedButton(
                  onPressed: _openLabDialog,
                  child: const Text('Upload Lab Report'),
                ),
              ],
            ),
            if (_isLoadingEmr) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  String _formatBmi(dynamic bmi) {
    if (bmi == null) return '-';
    final v = double.tryParse(bmi.toString());
    return v == null ? bmi.toString() : v.toStringAsFixed(1);
  }

  Widget _buildAllergiesAndConditions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ALLERGIES (${_allergies.length})',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMuted),
            ),
            const SizedBox(height: 6),
            if (_allergies.isEmpty)
              const Text('No allergies recorded.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted))
            else
              ..._allergies.map((al) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '🔴 ${al['allergen']} (${al['severity']}) - ${al['reaction']}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  )),
            const SizedBox(height: 14),
            Text(
              'CHRONIC CONDITIONS (${_chronicConditions.length})',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMuted),
            ),
            const SizedBox(height: 6),
            if (_chronicConditions.isEmpty)
              const Text('No conditions recorded.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted))
            else
              ..._chronicConditions.map((cc) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '⚫ ${cc['conditionName']} [${cc['icd10Code']}] - Status: ${cc['status']}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildPrescriptionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Prescription History',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryTeal)),
            const Divider(),
            if (_prescriptions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('No prescription records found.',
                      style: TextStyle(color: AppTheme.textMuted)),
                ),
              )
            else
              ..._prescriptions.map((rx) {
                final items = _selectedRxItems[rx['prescriptionId']] ?? [];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.borderGray),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text('Issued: ${rx['issuedDate'] ?? '-'}',
                                style: const TextStyle(
                                    fontSize: 12, color: AppTheme.textMuted)),
                          ),
                          Chip(
                            label: Text(rx['status'] ?? '',
                                style: const TextStyle(fontSize: 11)),
                            backgroundColor: AppTheme.primaryLightTeal,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Diagnosis: ${rx['diagnosisNotes'] ?? ''}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                      if (items.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        const Divider(height: 1),
                        const SizedBox(height: 6),
                        ...items.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                '💊 ${item['drugName']} (${item['dosage']}) - ${item['frequency']} for ${item['durationDays']} Days',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            )),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildVitalsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recorded Vitals History',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryTeal)),
            const Divider(),
            if (_vitals.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                    child: Text('No vitals documented.',
                        style: TextStyle(color: AppTheme.textMuted))),
              )
            else
              ..._vitals.map((v) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                'BP: ${v['bloodPressureSystolic']}/${v['bloodPressureDiastolic']} mmHg',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                            Text('HR: ${v['heartRateBpm']} BPM',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Glucose: ${v['bloodGlucoseMmol'] ?? 'N/A'} | Temp: ${v['temperatureC'] ?? 'N/A'}°C',
                                style: const TextStyle(
                                    fontSize: 11, color: AppTheme.textMuted),
                              ),
                            ),
                            Text(_shortDate(v['recordedAt']),
                                style: const TextStyle(
                                    fontSize: 11, color: AppTheme.textMuted)),
                          ],
                        ),
                        const Divider(height: 12),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildLabResultsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Lab Reports',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryTeal)),
            const Divider(),
            if (_labResults.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                    child: Text('No reports found.',
                        style: TextStyle(color: AppTheme.textMuted))),
              )
            else
              ..._labResults.map((lab) {
                final flag = lab['overallFlag'];
                final flagColor = flag == 'CRITICAL'
                    ? AppTheme.dangerRed
                    : flag == 'NORMAL'
                        ? AppTheme.successGreen
                        : AppTheme.warningAmber;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                                '${lab['labName']} - ${lab['reportType']}',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                          ),
                          Chip(
                            label: Text(flag ?? '',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white)),
                            backgroundColor: flagColor,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('Date: ${lab['reportDate'] ?? '-'}',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textMuted)),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundApp,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          lab['doctorAnnotation'] ?? 'No annotation',
                          style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: AppTheme.textMain),
                        ),
                      ),
                      const Divider(height: 16),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  String _shortDate(dynamic iso) {
    if (iso == null) return '';
    final s = iso.toString();
    return s.length >= 16 ? s.replaceFirst('T', ' ').substring(0, 16) : s;
  }

  // ── Record Vitals dialog ─────────────────────────────────────────────
  void _openVitalDialog() {
    final formKey = GlobalKey<FormState>();
    final systolic = TextEditingController(text: '120');
    final diastolic = TextEditingController(text: '80');
    final heartRate = TextEditingController(text: '72');
    final glucose = TextEditingController(text: '5.5');
    final hba1c = TextEditingController(text: '5.7');
    final weight = TextEditingController(text: '70');
    final temp = TextEditingController(text: '36.6');
    final oxygen = TextEditingController(text: '98');
    final notes = TextEditingController();
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Document Vitals Metric'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _numField('Systolic BP (mmHg)', systolic),
                  _numField('Diastolic BP (mmHg)', diastolic),
                  _numField('Heart Rate (BPM)', heartRate),
                  _numField('Glucose (mmol/L)', glucose, decimal: true),
                  _numField('HbA1c (%)', hba1c, decimal: true),
                  _numField('Weight (kg)', weight),
                  _numField('Temperature (°C)', temp, decimal: true),
                  _numField('Oxygen Saturation (%)', oxygen),
                  TextFormField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 2,
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
              onPressed: submitting
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setDialogState(() => submitting = true);
                      try {
                        await ref
                            .read(clinicalRecordServiceProvider)
                            .createVital({
                          'bloodPressureSystolic':
                              int.tryParse(systolic.text) ?? 0,
                          'bloodPressureDiastolic':
                              int.tryParse(diastolic.text) ?? 0,
                          'heartRateBpm': int.tryParse(heartRate.text) ?? 0,
                          'bloodGlucoseMmol': double.tryParse(glucose.text),
                          'hba1cPercent': double.tryParse(hba1c.text),
                          'weightKg': double.tryParse(weight.text),
                          'temperatureC': double.tryParse(temp.text),
                          'oxygenSaturation': int.tryParse(oxygen.text),
                          'notes': notes.text,
                          'patientId': _selectedPatientId,
                          'recordedAt': DateTime.now().toIso8601String(),
                          'source': 'DOCTOR_ENTRY',
                        });
                        if (mounted) Navigator.pop(ctx);
                        _toast('Vital logged.');
                        _loadPatientEmr();
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        _toast('Failed to record vitals.', error: true);
                      }
                    },
              child: const Text('Save Entry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numField(String label, TextEditingController c,
      {bool decimal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextFormField(
        controller: c,
        decoration: InputDecoration(labelText: label),
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      ),
    );
  }

  // ── Write Prescription dialog (2-stage, mirrors patients.component.html) ──
  void _openPrescriptionDialog() {
    final formKey = GlobalKey<FormState>();
    DateTime? validUntil;
    final diagnosisNotes = TextEditingController();
    final pharmacistNotes = TextEditingController();
    String? createdRxId;
    final List<dynamic> rxItemsList = [];
    bool submitting = false;

    final itemFormKey = GlobalKey<FormState>();
    final drugName = TextEditingController();
    final dosage = TextEditingController();
    String route = 'ORAL';
    final frequency = TextEditingController(text: '1x daily');
    final durationDays = TextEditingController(text: '7');
    final quantity = TextEditingController(text: '1');
    final refillsAllowed = TextEditingController(text: '0');
    final specialInstructions = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Write E-Prescription'),
          content: SingleChildScrollView(
            child: createdRxId == null
                ? Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(validUntil == null
                              ? 'Valid Until Date'
                              : 'Valid Until: ${validUntil!.toIso8601String().split('T')[0]}'),
                          trailing: const Icon(Icons.calendar_today, size: 18),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 3650)),
                            );
                            if (picked != null)
                              setDialogState(() => validUntil = picked);
                          },
                        ),
                        TextFormField(
                          controller: diagnosisNotes,
                          decoration: const InputDecoration(
                              labelText: 'Clinical Diagnosis Notes',
                              hintText: 'Symptoms, diagnostic findings...'),
                          maxLines: 3,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: pharmacistNotes,
                          decoration: const InputDecoration(
                              labelText: 'Pharmacist Instructions',
                              hintText: 'Substitutions, warnings...'),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundApp,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Added Items (${rxItemsList.length})',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryTeal)),
                            ...rxItemsList.map((item) => Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '💊 ${item['drugName']} (${item['dosage']}) - ${item['frequency']} for ${item['durationDays']} Days',
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                )),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Form(
                        key: itemFormKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: drugName,
                              decoration: const InputDecoration(
                                  labelText: 'Drug / Medicine Name',
                                  hintText: 'E.g. Amoxicillin 500mg'),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: dosage,
                              decoration: const InputDecoration(
                                  labelText: 'Dosage',
                                  hintText: 'E.g. 1 tablet'),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: route,
                              decoration:
                                  const InputDecoration(labelText: 'Route'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'ORAL', child: Text('Oral')),
                                DropdownMenuItem(
                                    value: 'INTRAVENOUS',
                                    child: Text('Intravenous')),
                                DropdownMenuItem(
                                    value: 'TOPICAL', child: Text('Topical')),
                              ],
                              onChanged: (v) =>
                                  setDialogState(() => route = v ?? 'ORAL'),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: frequency,
                              decoration: const InputDecoration(
                                  labelText: 'Frequency',
                                  hintText: 'E.g. Twice daily'),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                            ),
                            const SizedBox(height: 8),
                            _numField('Duration (Days)', durationDays),
                            _numField('Total Quantity', quantity),
                            _numField('Refills Allowed', refillsAllowed),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: specialInstructions,
                              decoration: const InputDecoration(
                                  labelText: 'Special Instructions',
                                  hintText: 'E.g. Take after meal'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          actions: createdRxId == null
              ? [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  ElevatedButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            if (!(formKey.currentState?.validate() ?? false))
                              return;
                            setDialogState(() => submitting = true);
                            try {
                              final rx = await ref
                                  .read(clinicalRecordServiceProvider)
                                  .createPrescription({
                                'validUntil':
                                    validUntil?.toIso8601String().split('T')[0],
                                'diagnosisNotes': diagnosisNotes.text,
                                'pharmacistNotes': pharmacistNotes.text,
                                'patientId': _selectedPatientId,
                                'status': 'ACTIVE',
                                'issuedDate': DateTime.now()
                                    .toIso8601String()
                                    .split('T')[0],
                              });
                              setDialogState(() {
                                createdRxId = rx['prescriptionId'];
                                submitting = false;
                              });
                              _toast(
                                  'Prescription shell created. Now add items.');
                            } catch (e) {
                              setDialogState(() => submitting = false);
                              _toast('Failed to create prescription.',
                                  error: true);
                            }
                          },
                    child: const Text('Create Shell'),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: () async {
                      if (!(itemFormKey.currentState?.validate() ?? false))
                        return;
                      try {
                        final item = await ref
                            .read(clinicalRecordServiceProvider)
                            .addPrescriptionItem(createdRxId!, {
                          'drugName': drugName.text,
                          'dosage': dosage.text,
                          'route': route,
                          'frequency': frequency.text,
                          'durationDays': int.tryParse(durationDays.text) ?? 1,
                          'quantity': int.tryParse(quantity.text) ?? 1,
                          'refillsAllowed':
                              int.tryParse(refillsAllowed.text) ?? 0,
                          'specialInstructions': specialInstructions.text,
                        });
                        setDialogState(() {
                          rxItemsList.add(item);
                          drugName.clear();
                          dosage.clear();
                          route = 'ORAL';
                          frequency.text = '1x daily';
                          durationDays.text = '7';
                          quantity.text = '1';
                          refillsAllowed.text = '0';
                          specialInstructions.clear();
                        });
                        _toast('Prescription item added.');
                      } catch (e) {
                        _toast('Failed to add prescription item.', error: true);
                      }
                    },
                    child: const Text('+ Add Item'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _loadPatientEmr();
                    },
                    child: const Text('Finish Prescription'),
                  ),
                ],
        ),
      ),
    );
  }

  // ── Upload Lab Report dialog ────────────────────────────────────────
  void _openLabDialog() {
    final formKey = GlobalKey<FormState>();
    final labName = TextEditingController();
    final reportType = TextEditingController();
    DateTime? reportDate;
    final doctorAnnotation = TextEditingController();
    PlatformFile? selectedFile;
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Upload Lab Report'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: labName,
                    decoration: const InputDecoration(
                        labelText: 'Lab Facility Name',
                        hintText: 'E.g. Al Borg Diagnostics'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: reportType,
                    decoration: const InputDecoration(
                        labelText: 'Report Type / Test Category',
                        hintText: 'E.g. Lipid Profile'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(reportDate == null
                        ? 'Report Date'
                        : 'Report Date: ${reportDate!.toIso8601String().split('T')[0]}'),
                    trailing: const Icon(Icons.calendar_today, size: 18),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 3650)),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null)
                        setDialogState(() => reportDate = picked);
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: Text(selectedFile == null
                        ? 'Select Report Attachment (PDF/Image)'
                        : selectedFile!.name),
                    onPressed: () async {
                      final result = await FilePicker.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                      );
                      if (result != null && result.files.isNotEmpty) {
                        setDialogState(() => selectedFile = result.files.first);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: doctorAnnotation,
                    decoration: const InputDecoration(
                        labelText: 'Clinical Annotation Notes'),
                    maxLines: 2,
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
              onPressed: submitting
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setDialogState(() => submitting = true);
                      try {
                        await ref
                            .read(clinicalRecordServiceProvider)
                            .createLabResult(
                          {
                            'labName': labName.text,
                            'reportType': reportType.text,
                            'reportDate':
                                reportDate?.toIso8601String().split('T')[0],
                            'status': 'PENDING',
                            'overallFlag': 'NORMAL',
                            'doctorAnnotation': doctorAnnotation.text,
                            'patientId': _selectedPatientId,
                          },
                          filePath: selectedFile?.path,
                        );
                        if (mounted) Navigator.pop(ctx);
                        _toast('Lab result uploaded.');
                        _loadPatientEmr();
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        _toast('Failed to upload lab report.', error: true);
                      }
                    },
              child: const Text('Upload Report'),
            ),
          ],
        ),
      ),
    );
  }
}

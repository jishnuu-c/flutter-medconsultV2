import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../data/appointment_service.dart';
import '../data/clinical_record_service.dart';
import '../data/patient_record_service.dart';
import '../data/consultation_service.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../../core/auth/auth_provider.dart';

/// Turns a relative avatar path (e.g. "/uploads/Users/avatar/x.jpg") returned
/// by the API into an absolute URL NetworkImage can load. Returns null when
/// there is nothing usable, so callers can fall back to the icon avatar.
String? resolveAssetUrl(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final value = raw.trim();
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) return value;
  final base = kBaseUrl.endsWith('/')
      ? kBaseUrl.substring(0, kBaseUrl.length - 1)
      : kBaseUrl;
  final path = value.startsWith('/') ? value : '/$value';
  return '$base$path';
}

class DoctorPatientsScreen extends ConsumerStatefulWidget {
  const DoctorPatientsScreen({super.key});

  @override
  ConsumerState<DoctorPatientsScreen> createState() =>
      _DoctorPatientsScreenState();
}

class _DoctorPatientsScreenState extends ConsumerState<DoctorPatientsScreen> {
  bool _isLoadingPatients = false;
  bool _isLoadingEmr = false;

  // patientId, patientName, avatarUrl
  List<Map<String, String>> _patientList = [];
  String _searchTerm = '';
  String _selectedPatientId = '';
  String _selectedPatientName = '';
  String _selectedPatientAvatarUrl = '';

  // EMR Chart details — mirrors patients.component.ts
  Map<String, dynamic>? _healthProfile;
  List<dynamic> _allergies = [];
  List<dynamic> _chronicConditions = [];
  List<dynamic> _prescriptions = [];
  final Map<String, List<dynamic>> _selectedRxItems = {};
  List<dynamic> _vitals = [];
  List<dynamic> _labResults = [];

  List<Map<String, String>> get _filteredPatients {
    if (_searchTerm.trim().isEmpty) return _patientList;
    final term = _searchTerm.toLowerCase();
    return _patientList
        .where((p) =>
            (p['patientName'] ?? '').toLowerCase().contains(term) ||
            (p['patientId'] ?? '').toLowerCase().contains(term))
        .toList();
  }

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
    final map = <String, Map<String, String>>{};

    void updateList() {
      if (!mounted) return;
      setState(() {
        _patientList = map.entries
            .map((e) => {
                  'patientId': e.key,
                  'patientName': e.value['patientName'] ?? '',
                  'avatarUrl': e.value['avatarUrl'] ?? '',
                })
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
        if (id == null) continue;
        final existing = map[id.toString()];
        map[id.toString()] = {
          'patientName':
              (app['patientName'] ?? existing?['patientName'] ?? '').toString(),
          'avatarUrl': (app['patientAvatarUrl'] ?? existing?['avatarUrl'] ?? '')
              .toString(),
        };
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
        if (id == null) continue;
        final existing = map[id.toString()];
        map[id.toString()] = {
          'patientName':
              (c['patientName'] ?? existing?['patientName'] ?? '').toString(),
          'avatarUrl': (c['patientAvatarUrl'] ?? existing?['avatarUrl'] ?? '')
              .toString(),
        };
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

  void _selectPatient(Map<String, String> p) {
    setState(() {
      _selectedPatientId = p['patientId'] ?? '';
      _selectedPatientName = p['patientName'] ?? '';
      _selectedPatientAvatarUrl = p['avatarUrl'] ?? '';
    });
    _loadPatientEmr();
  }

  void _backToDirectory() {
    setState(() {
      _selectedPatientId = '';
      _selectedPatientAvatarUrl = '';
    });
    _clearPatientDetails();
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
          if (mounted) {
            setState(() => _selectedRxItems[r['prescriptionId']] = items);
          }
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

  Future<void> _downloadLabFile(String? fileId) async {
    if (fileId == null || fileId.isEmpty) return;
    try {
      await ref.read(clinicalRecordServiceProvider).downloadFile(fileId);
      _toast('Report downloading...');
    } catch (e) {
      debugPrint('download error: ${_errorMessage(e)}');
      _toast('Could not download lab report file.', error: true);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundApp,
      appBar: AppBar(
        title: Text(_selectedPatientId.isEmpty
            ? 'Patient Directory'
            : _selectedPatientName),
        leading: _selectedPatientId.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _backToDirectory,
              ),
      ),
      body: SafeArea(
        child: _selectedPatientId.isEmpty
            ? _buildDirectory()
            : RefreshIndicator(
                onRefresh: _loadPatientEmr,
                child: _buildChart(),
              ),
      ),
    );
  }

  // ── Directory (mirrors patients-directory-card / patients-grid) ────────
  Widget _buildDirectory() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search patient name or ID...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.borderGray),
              ),
            ),
            onChanged: (v) => setState(() => _searchTerm = v),
          ),
        ),
        Expanded(
          child: _isLoadingPatients
              ? const Center(child: CircularProgressIndicator())
              : _filteredPatients.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No patients found.\nCheck your appointments and consultations.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadDoctorPatients,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _filteredPatients.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final p = _filteredPatients[i];
                          return _PatientDirectoryTile(
                            name: p['patientName'] ?? '',
                            id: p['patientId'] ?? '',
                            avatarUrl: p['avatarUrl'] ?? '',
                            onTap: () => _selectPatient(p),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  // ── Chart (mirrors chart-header-card + emr-dashboard-grid, stacked for mobile) ──
  Widget _buildChart() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_isLoadingEmr) const LinearProgressIndicator(),
        if (_isLoadingEmr) const SizedBox(height: 10),
        _buildProfileCard(),
        const SizedBox(height: 14),
        _buildAllergiesAndConditions(),
        const SizedBox(height: 14),
        _buildActionButtons(),
        const SizedBox(height: 14),
        _buildPrescriptionsCard(),
        const SizedBox(height: 14),
        _buildVitalsCard(),
        const SizedBox(height: 14),
        _buildLabResultsCard(),
      ],
    );
  }

  Widget _buildProfileCard() {
    // NOTE: a BoxDecoration can't combine `borderRadius` with a `border`
    // that has different widths/colors per side (Flutter throws "A
    // borderRadius can only be given on borders with uniform colors").
    // Card's own shape gives the rounding; clipBehavior clips the child to
    // it, and the inner Container only draws the left accent bar (no radius
    // on that Container), so the two never conflict.
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: AppTheme.primaryTeal, width: 4),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(
                  url: resolveAssetUrl(_selectedPatientAvatarUrl),
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedPatientName,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryTeal),
                  ),
                ),
              ],
            ),
            if (_healthProfile != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill('📏 Height: ${_healthProfile!['heightCm'] ?? '-'} cm'),
                  _pill('⚖️ Weight: ${_healthProfile!['weightKg'] ?? '-'} kg'),
                  _pill('📊 BMI: ${_formatBmi(_healthProfile!['bmi'])}'),
                  _pill('🚬 ${_healthProfile!['smokingStatus'] ?? '-'}'),
                  _pill('🍷 ${_healthProfile!['alcoholStatus'] ?? '-'}'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryLightTeal,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppTheme.primaryTeal.withValues(alpha: 0.2)),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryDarkTeal)),
    );
  }

  String _formatBmi(dynamic bmi) {
    if (bmi == null) return '-';
    final v = double.tryParse(bmi.toString());
    return v == null ? bmi.toString() : v.toStringAsFixed(1);
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.favorite, size: 16),
            label: const Text('Vitals'),
            onPressed: _openVitalSheet,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryDarkTeal),
            icon: const Icon(Icons.medication, size: 16),
            label: const Text('Rx'),
            onPressed: _openPrescriptionSheet,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.science, size: 16),
            label: const Text('Lab'),
            onPressed: _openLabSheet,
          ),
        ),
      ],
    );
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
                  color: AppTheme.textMuted,
                  letterSpacing: 0.4),
            ),
            const SizedBox(height: 8),
            if (_allergies.isEmpty)
              const Text('No allergies recorded on file.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted))
            else
              ..._allergies.map((al) => _LeftAccentBox(
                    accentColor: AppTheme.dangerRed,
                    backgroundColor: const Color(0xFFFFF5F5),
                    margin: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '🚨 ${al['allergen']} (${al['severity']}) — ${al['reaction']}',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF991B1B)),
                    ),
                  )),
            const SizedBox(height: 16),
            Text(
              'CHRONIC CONDITIONS (${_chronicConditions.length})',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.4),
            ),
            const SizedBox(height: 8),
            if (_chronicConditions.isEmpty)
              const Text('No chronic conditions recorded.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted))
            else
              ..._chronicConditions.map((cc) => _LeftAccentBox(
                    accentColor: const Color(0xFF3B82F6),
                    backgroundColor: const Color(0xFFF8FAFC),
                    margin: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '🩺 ${cc['conditionName']} [${cc['icd10Code']}] — Status: ${cc['status']}',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF1E293B)),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('📜 Prescription History',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryTeal)),
                Chip(
                  label: Text('${_prescriptions.length}',
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: AppTheme.primaryLightTeal,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text('📅 Issued: ${rx['issuedDate'] ?? '-'}',
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
                      Text('🩺 Diagnosis: ${rx['diagnosisNotes'] ?? ''}',
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🫀 Recorded Vitals History',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryTeal)),
                Chip(
                  label: Text('${_vitals.length}',
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: AppTheme.primaryLightTeal,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const Divider(),
            if (_vitals.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                    child: Text('No vitals documented.',
                        style: TextStyle(color: AppTheme.textMuted))),
              )
            else
              ..._vitals.map((v) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundApp,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                '🩺 BP: ${v['bloodPressureSystolic']}/${v['bloodPressureDiastolic']} mmHg',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                            Text('❤️ ${v['heartRateBpm']} BPM',
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '🩸 ${v['bloodGlucoseMmol'] ?? 'N/A'} | 🌡️ ${v['temperatureC'] ?? 'N/A'}°C',
                                style: const TextStyle(
                                    fontSize: 11, color: AppTheme.textMuted),
                              ),
                            ),
                            Text(_shortDate(v['recordedAt']),
                                style: const TextStyle(
                                    fontSize: 11, color: AppTheme.textMuted)),
                          ],
                        ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🔬 Lab Reports & Attachments',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryTeal)),
                Chip(
                  label: Text('${_labResults.length}',
                      style: const TextStyle(fontSize: 11)),
                  backgroundColor: AppTheme.primaryLightTeal,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
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
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.borderGray),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                                '🧪 ${lab['labName']} — ${lab['reportType']}',
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
                      const SizedBox(height: 4),
                      Text(
                          '📅 Date: ${lab['reportDate'] ?? '-'} | Status: ${lab['status'] ?? '-'}',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textMuted)),
                      if ((lab['doctorAnnotation'] ?? '')
                          .toString()
                          .isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _LeftAccentBox(
                          accentColor: AppTheme.primaryTeal,
                          backgroundColor: AppTheme.backgroundApp,
                          width: double.infinity,
                          child: Text(
                            '💬 ${lab['doctorAnnotation']}',
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textMain),
                          ),
                        ),
                      ],
                      if (lab['fileId'] != null &&
                          lab['fileId'].toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLightTeal,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('📄 Lab Attachment',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryDarkTeal)),
                              TextButton.icon(
                                icon: const Icon(Icons.download, size: 16),
                                label: const Text('Download'),
                                onPressed: () =>
                                    _downloadLabFile(lab['fileId']?.toString()),
                              ),
                            ],
                          ),
                        ),
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

  String _shortDate(dynamic iso) {
    if (iso == null) return '';
    final s = iso.toString();
    return s.length >= 16 ? s.replaceFirst('T', ' ').substring(0, 16) : s;
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

  Widget _sheetScaffold({
    required String title,
    required Widget child,
    required List<Widget> actions,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.borderGray,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryTeal)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: child,
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: actions),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Record Vitals sheet ─────────────────────────────────────────────
  void _openVitalSheet() {
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => _sheetScaffold(
          title: 'Document Vitals Metric',
          child: Form(
            key: formKey,
            child: Column(
              children: [
                Row(children: [
                  Expanded(child: _numField('Systolic BP (mmHg)', systolic)),
                  const SizedBox(width: 10),
                  Expanded(child: _numField('Diastolic BP (mmHg)', diastolic)),
                ]),
                Row(children: [
                  Expanded(child: _numField('Heart Rate (BPM)', heartRate)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _numField('Glucose (mmol/L)', glucose,
                          decimal: true)),
                ]),
                Row(children: [
                  Expanded(child: _numField('HbA1c (%)', hba1c, decimal: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _numField('Weight (kg)', weight)),
                ]),
                Row(children: [
                  Expanded(
                      child:
                          _numField('Temperature (°C)', temp, decimal: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _numField('Oxygen Saturation (%)', oxygen)),
                ]),
                TextFormField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: submitting
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        setSheetState(() => submitting = true);
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
                          setSheetState(() => submitting = false);
                          _toast('Failed to record vitals.', error: true);
                        }
                      },
                child: submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save Entry'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Write Prescription sheet (2-stage, mirrors patients.component.html) ──
  void _openPrescriptionSheet() {
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final stageOne = createdRxId == null;
          return _sheetScaffold(
            title: 'Write E-Prescription',
            child: stageOne
                ? Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                            if (picked != null) {
                              setSheetState(() => validUntil = picked);
                            }
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
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                  setSheetState(() => route = v ?? 'ORAL'),
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
                            Row(children: [
                              Expanded(
                                  child: _numField(
                                      'Duration (Days)', durationDays)),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: _numField('Total Quantity', quantity)),
                            ]),
                            _numField('Refills Allowed', refillsAllowed),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: specialInstructions,
                              decoration: const InputDecoration(
                                  labelText: 'Special Instructions',
                                  hintText: 'E.g. Take after meal'),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add Item'),
                                onPressed: () async {
                                  if (!(itemFormKey.currentState?.validate() ??
                                      false)) {
                                    return;
                                  }
                                  try {
                                    final item = await ref
                                        .read(clinicalRecordServiceProvider)
                                        .addPrescriptionItem(createdRxId!, {
                                      'drugName': drugName.text,
                                      'dosage': dosage.text,
                                      'route': route,
                                      'frequency': frequency.text,
                                      'durationDays':
                                          int.tryParse(durationDays.text) ?? 1,
                                      'quantity':
                                          int.tryParse(quantity.text) ?? 1,
                                      'refillsAllowed':
                                          int.tryParse(refillsAllowed.text) ??
                                              0,
                                      'specialInstructions':
                                          specialInstructions.text,
                                    });
                                    setSheetState(() {
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
                                    _toast('Failed to add prescription item.',
                                        error: true);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
            actions: stageOne
                ? [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: submitting
                            ? null
                            : () async {
                                if (!(formKey.currentState?.validate() ??
                                    false)) {
                                  return;
                                }
                                setSheetState(() => submitting = true);
                                try {
                                  final rx = await ref
                                      .read(clinicalRecordServiceProvider)
                                      .createPrescription({
                                    'validUntil': validUntil
                                        ?.toIso8601String()
                                        .split('T')[0],
                                    'diagnosisNotes': diagnosisNotes.text,
                                    'pharmacistNotes': pharmacistNotes.text,
                                    'patientId': _selectedPatientId,
                                    'status': 'ACTIVE',
                                    'issuedDate': DateTime.now()
                                        .toIso8601String()
                                        .split('T')[0],
                                  });
                                  setSheetState(() {
                                    createdRxId = rx['prescriptionId'];
                                    submitting = false;
                                  });
                                  _toast(
                                      'Prescription shell created. Now add items.');
                                } catch (e) {
                                  setSheetState(() => submitting = false);
                                  _toast('Failed to create prescription.',
                                      error: true);
                                }
                              },
                        child: submitting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Create Shell'),
                      ),
                    ),
                  ]
                : [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _loadPatientEmr();
                        },
                        child: const Text('Finish Prescription'),
                      ),
                    ),
                  ],
          );
        },
      ),
    );
  }

  // ── Upload Lab Report sheet ────────────────────────────────────────
  void _openLabSheet() {
    final formKey = GlobalKey<FormState>();
    final labName = TextEditingController();
    final reportType = TextEditingController();
    DateTime? reportDate;
    final doctorAnnotation = TextEditingController();
    PlatformFile? selectedFile;
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => _sheetScaffold(
          title: 'Upload Lab Report',
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    if (picked != null) {
                      setSheetState(() => reportDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
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
                        setSheetState(() => selectedFile = result.files.first);
                      }
                    },
                  ),
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
          actions: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: submitting
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        setSheetState(() => submitting = true);
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
                          setSheetState(() => submitting = false);
                          _toast('Failed to upload lab report.', error: true);
                        }
                      },
                child: submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Upload Report'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Directory list tile — mirrors .patient-profile-card from patients.component.css,
/// laid out horizontally for a mobile scroll list instead of a desktop grid.
class _PatientDirectoryTile extends StatelessWidget {
  final String name;
  final String id;
  final String avatarUrl;
  final VoidCallback onTap;

  const _PatientDirectoryTile({
    required this.name,
    required this.id,
    required this.avatarUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Outer ClipRRect + outline gives the rounded card border; the teal
    // strip is a separate solid-color Container (no radius on it), so we
    // never mix `borderRadius` with a multi-color Border on the same box —
    // that combo is what was throwing "borderRadius can only be given on
    // borders with uniform colors" and killing this list's render.
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppTheme.borderGray),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(width: 4, color: AppTheme.primaryTeal),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          _Avatar(url: resolveAssetUrl(avatarUrl), radius: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textMain)),
                                const SizedBox(height: 2),
                                Text('ID: $id',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textMuted)),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              color: AppTheme.textMuted),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded box with a solid-color left accent strip. Splitting the accent
/// into its own Container (instead of a one-sided Border) is what lets this
/// combine cleanly with `borderRadius` — see note in _PatientDirectoryTile.
class _LeftAccentBox extends StatelessWidget {
  final Color accentColor;
  final Color backgroundColor;
  final Widget child;
  final EdgeInsets margin;
  final double? width;

  const _LeftAccentBox({
    required this.accentColor,
    required this.backgroundColor,
    required this.child,
    this.margin = EdgeInsets.zero,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Container(width: 4, color: accentColor),
              Expanded(
                child: Container(
                  color: backgroundColor,
                  padding: const EdgeInsets.all(10),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Safe avatar: shows a placeholder icon if url is null/empty, and falls
/// back to the icon (instead of crashing/looping) on any load error.
class _Avatar extends StatelessWidget {
  final String? url;
  final double radius;

  const _Avatar({required this.url, required this.radius});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.primaryLightTeal,
        child:
            Icon(Icons.person, color: AppTheme.primaryDarkTeal, size: radius),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.primaryLightTeal,
      child: ClipOval(
        child: Image.network(
          url!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.person,
            color: AppTheme.primaryDarkTeal,
            size: radius,
          ),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: radius * 2,
              height: radius * 2,
              child: const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

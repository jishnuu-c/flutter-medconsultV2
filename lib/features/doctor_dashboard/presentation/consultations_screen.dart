import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../data/consultation_service.dart';
import '../data/patient_record_service.dart';
import '../data/clinical_record_service.dart';

class DoctorConsultationsScreen extends ConsumerStatefulWidget {
  const DoctorConsultationsScreen({super.key});

  @override
  ConsumerState<DoctorConsultationsScreen> createState() =>
      _DoctorConsultationsScreenState();
}

const List<String> _statusOptions = [
  'OPEN',
  'IN_PROGRESS',
  'CLOSED',
  'ARCHIVED'
];

const List<Map<String, String>> _routeOptions = [
  {'value': 'ORAL', 'label': 'Oral'},
  {'value': 'IV', 'label': 'Intravenous (IV)'},
  {'value': 'IM', 'label': 'Intramuscular (IM)'},
  {'value': 'SC', 'label': 'Subcutaneous (SC)'},
  {'value': 'TOPICAL', 'label': 'Topical'},
  {'value': 'INHALED', 'label': 'Inhaled'},
  {'value': 'SUBLINGUAL', 'label': 'Sublingual'},
  {'value': 'RECTAL', 'label': 'Rectal'},
  {'value': 'OPHTHALMIC', 'label': 'Ophthalmic'},
  {'value': 'NASAL', 'label': 'Nasal'},
];

const List<String> _labStatusOptions = [
  'PENDING',
  'RECEIVED',
  'REVIEWED',
  'ABNORMAL',
  'CRITICAL'
];
const List<String> _labFlagOptions = ['NORMAL', 'ABNORMAL', 'CRITICAL'];
const List<String> _labItemFlagOptions = [
  'NORMAL',
  'HIGH',
  'LOW',
  'CRITICAL_HIGH',
  'CRITICAL_LOW',
  'ABNORMAL'
];

class _DoctorConsultationsScreenState
    extends ConsumerState<DoctorConsultationsScreen> {
  final _messageController = TextEditingController();
  final _messagesScrollController = ScrollController();
  bool _isLoading = false;
  bool _isUpdatingStatus = false;
  String? _doctorId;
  List<dynamic> _consultations = [];
  Map<String, dynamic>? _selectedConsultation;
  List<dynamic> _messages = [];
  String? _statusFormValue;

  Timer? _pollTimer;

  // ── Patient info (mirrors Angular's patient-info-sidebar) ───────────
  Map<String, dynamic>? _patientHealthProfile;
  List<dynamic> _patientAllergies = [];
  List<dynamic> _patientChronicConditions = [];

  // ── Prescriptions (mirrors Angular's rx-slide-panel) ─────────────────
  List<dynamic> _prescriptions = [];
  Map<String, dynamic>? _selectedPrescription;
  List<dynamic> _prescriptionItems = [];

  // ── Lab results (mirrors Angular's lab-slide-panel) ──────────────────
  List<dynamic> _labResults = [];
  Map<String, dynamic>? _selectedLabResult;
  List<dynamic> _labItems = [];

  @override
  void initState() {
    super.initState();
    _resolveDoctorIdAndLoad();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messagesScrollController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  String _errorMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
      return e.response?.statusMessage ?? e.message ?? 'Network error';
    }
    return e.toString();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _resolveDoctorIdAndLoad() async {
    setState(() => _isLoading = true);
    try {
      final userId = ref.read(authNotifierProvider).currentUser?.id;
      if (userId == null) {
        throw Exception('No logged-in user found.');
      }
      final doctors = await ref.read(doctorServiceProvider).getAllDoctors();
      final match = doctors.where((d) => d.userId == userId);
      if (match.isEmpty) {
        throw Exception('Doctor profile not found for this user.');
      }
      _doctorId = match.first.doctorId;
      await _loadConsultations();
    } catch (e) {
      _snack('Failed to resolve doctor profile: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadConsultations() async {
    if (_doctorId == null) return;
    setState(() => _isLoading = true);
    try {
      final res = await ref
          .read(consultationServiceProvider)
          .getConsultationsByDoctor(_doctorId!, page: 0, size: 50);
      setState(() => _consultations = res);
    } catch (e) {
      setState(() => _consultations = []);
      _snack('Failed to load consultations: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectConsultation(Map<String, dynamic> c) async {
    _pollTimer?.cancel();
    setState(() {
      _selectedConsultation = c;
      _statusFormValue = c['status'];
      _isLoading = true;
      _patientHealthProfile = null;
      _patientAllergies = [];
      _patientChronicConditions = [];
      _prescriptions = [];
      _selectedPrescription = null;
      _prescriptionItems = [];
      _labResults = [];
      _selectedLabResult = null;
      _labItems = [];
    });

    await _loadMessages(showSpinner: true);
    _loadPatientDetails(c['patientId']);

    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _loadMessages(showSpinner: false);
    });
  }

  Future<void> _loadMessages({required bool showSpinner}) async {
    if (_selectedConsultation == null) return;
    if (showSpinner && mounted) setState(() => _isLoading = true);
    try {
      final msgs = await ref
          .read(consultationServiceProvider)
          .getMessagesForConsultation(_selectedConsultation!['consultationId']);
      final changed = _messages.length != msgs.length;
      if (mounted) setState(() => _messages = msgs);
      if (changed) _scrollToBottom();
    } catch (e) {
      if (showSpinner) {
        setState(() => _messages = []);
        _snack('Failed to load messages: ${_errorMessage(e)}');
      }
    } finally {
      if (showSpinner && mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messagesScrollController.hasClients) return;
      _messagesScrollController.animateTo(
        _messagesScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _closeThread() {
    _pollTimer?.cancel();
    setState(() => _selectedConsultation = null);
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedConsultation == null) return;
    _messageController.clear();
    ref.read(consultationServiceProvider).sendMessage({
      'consultationId': _selectedConsultation!['consultationId'],
      'messageType': 'TEXT',
      'body': text,
    }).then((msg) {
      if (mounted) {
        setState(() => _messages.add(msg));
        _scrollToBottom();
      }
    }).catchError((e) {
      _snack('Failed to send message: ${_errorMessage(e)}');
    });
  }

  Future<void> _updateStatus() async {
    if (_selectedConsultation == null || _statusFormValue == null) return;
    setState(() => _isUpdatingStatus = true);
    try {
      final updated = await ref.read(consultationServiceProvider).updateStatus(
          _selectedConsultation!['consultationId'],
          {'status': _statusFormValue});
      _snack('Consultation status updated.');
      setState(() {
        _selectedConsultation = Map<String, dynamic>.from(updated);
        final idx = _consultations.indexWhere(
            (c) => c['consultationId'] == updated['consultationId']);
        if (idx != -1) _consultations[idx] = updated;
      });
    } catch (e) {
      _snack('Failed to update status: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'OPEN':
        return AppTheme.successGreen;
      case 'IN_PROGRESS':
        return AppTheme.warningAmber;
      case 'CLOSED':
        return AppTheme.textMuted;
      default:
        return AppTheme.infoBlue;
    }
  }

  String _shortTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  String _mediumDate(String? d) {
    if (d == null || d.isEmpty) return '-';
    final dt = DateTime.tryParse(d);
    if (dt == null) return d;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  // ── Patient details (mirrors Angular loadPatientDetails) ────────────
  void _loadPatientDetails(String? patientId) {
    if (patientId == null) return;
    ref
        .read(patientRecordServiceProvider)
        .getPatientHealthProfile(patientId)
        .then((profile) {
      if (mounted) setState(() => _patientHealthProfile = profile);
    }).catchError((_) {
      if (mounted) setState(() => _patientHealthProfile = null);
    });

    ref
        .read(patientRecordServiceProvider)
        .getPatientAllergies(patientId)
        .then((data) {
      if (mounted) setState(() => _patientAllergies = data);
    }).catchError((_) {
      if (mounted) setState(() => _patientAllergies = []);
    });

    ref
        .read(patientRecordServiceProvider)
        .getPatientChronicConditions(patientId)
        .then((data) {
      if (mounted) setState(() => _patientChronicConditions = data);
    }).catchError((_) {
      if (mounted) setState(() => _patientChronicConditions = []);
    });
  }

  // ── Prescriptions (mirrors Angular loadPrescriptions / submitPrescription) ──
  Future<void> _loadPrescriptions() async {
    if (_selectedConsultation == null) return;
    try {
      final page = await ref
          .read(clinicalRecordServiceProvider)
          .searchPrescriptions(
              patientId: _selectedConsultation!['patientId'],
              page: 0,
              size: 20);
      final all = page;
      final filtered = all
          .where((rx) =>
              rx['consultationId'] ==
                  _selectedConsultation!['consultationId'] ||
              rx['consultationId'] == null)
          .toList();
      if (mounted) {
        setState(() {
          _prescriptions = filtered;
          if (_prescriptions.isNotEmpty && _selectedPrescription == null) {
            _selectedPrescription = _prescriptions.first;
          }
        });
      }
      if (_selectedPrescription != null) {
        _loadPrescriptionItems(_selectedPrescription!['prescriptionId']);
      }
    } catch (e) {
      if (mounted) setState(() => _prescriptions = []);
    }
  }

  Future<void> _loadPrescriptionItems(String prescriptionId) async {
    try {
      final items = await ref
          .read(clinicalRecordServiceProvider)
          .getPrescriptionItems(prescriptionId);
      if (mounted) setState(() => _prescriptionItems = items);
    } catch (_) {
      if (mounted) setState(() => _prescriptionItems = []);
    }
  }

  Future<void> _createPrescription(Map<String, dynamic> payload) async {
    if (_selectedConsultation == null) return;
    setState(() => _isLoading = true);
    try {
      final full = {
        ...payload,
        'patientId': _selectedConsultation!['patientId'],
        'consultationId': _selectedConsultation!['consultationId'],
      };
      final rx = await ref
          .read(clinicalRecordServiceProvider)
          .createPrescription(full);
      _snack('Prescription created successfully.');
      setState(() {
        _prescriptions = [rx, ..._prescriptions];
        _selectedPrescription = rx;
        _prescriptionItems = [];
      });
    } catch (e) {
      _snack('Failed to create prescription: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addPrescriptionItem(Map<String, dynamic> payload) async {
    if (_selectedPrescription == null) return;
    try {
      final item = await ref
          .read(clinicalRecordServiceProvider)
          .addPrescriptionItem(
              _selectedPrescription!['prescriptionId'], payload);
      _snack('Medication added.');
      setState(() => _prescriptionItems = [..._prescriptionItems, item]);
    } catch (e) {
      _snack('Failed to add medication: ${_errorMessage(e)}');
    }
  }

  Future<void> _deletePrescriptionItem(String itemId) async {
    final confirmed = await _confirm('Remove this medication?');
    if (!confirmed) return;
    try {
      await ref
          .read(clinicalRecordServiceProvider)
          .deletePrescriptionItem(itemId);
      _snack('Medication removed.');
      setState(() => _prescriptionItems =
          _prescriptionItems.where((i) => i['itemId'] != itemId).toList());
    } catch (e) {
      _snack('Failed to remove medication: ${_errorMessage(e)}');
    }
  }

  Future<void> _deletePrescription(String prescriptionId) async {
    final confirmed = await _confirm('Delete this entire prescription?');
    if (!confirmed) return;
    try {
      await ref
          .read(clinicalRecordServiceProvider)
          .deletePrescription(prescriptionId);
      _snack('Prescription deleted.');
      setState(() {
        _prescriptions = _prescriptions
            .where((rx) => rx['prescriptionId'] != prescriptionId)
            .toList();
        _selectedPrescription = null;
        _prescriptionItems = [];
      });
    } catch (e) {
      _snack('Failed to delete prescription: ${_errorMessage(e)}');
    }
  }

  // ── Lab results (mirrors Angular loadLabResults / submitLabResult) ──
  Future<void> _loadLabResults() async {
    if (_selectedConsultation == null) return;
    try {
      final page = await ref
          .read(clinicalRecordServiceProvider)
          .searchLabResults(
              patientId: _selectedConsultation!['patientId'],
              page: 0,
              size: 20);
      if (mounted) {
        setState(() {
          _labResults = page;
          if (_labResults.isNotEmpty && _selectedLabResult == null) {
            _selectedLabResult = _labResults.first;
          }
        });
      }
      if (_selectedLabResult != null) {
        _loadLabItems(_selectedLabResult!['labResultId']);
      }
    } catch (e) {
      if (mounted) setState(() => _labResults = []);
    }
  }

  Future<void> _loadLabItems(String labResultId) async {
    try {
      final items = await ref
          .read(clinicalRecordServiceProvider)
          .getLabItems(labResultId);
      if (mounted) setState(() => _labItems = items ?? []);
    } catch (_) {
      if (mounted) setState(() => _labItems = []);
    }
  }

  Future<void> _createLabResult(
      Map<String, dynamic> payload, PlatformFile? file) async {
    if (_selectedConsultation == null) return;
    setState(() => _isLoading = true);
    try {
      final full = {
        ...payload,
        'patientId': _selectedConsultation!['patientId'],
      };
      final lab = await ref
          .read(clinicalRecordServiceProvider)
          .createLabResult(full, filePath: file?.path);
      _snack('Lab result created successfully.');
      setState(() {
        _labResults = [lab, ..._labResults];
        _selectedLabResult = lab;
        _labItems = [];
      });
    } catch (e) {
      _snack('Failed to create lab result: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addLabItem(Map<String, dynamic> payload) async {
    if (_selectedLabResult == null) return;
    try {
      final item = await ref
          .read(clinicalRecordServiceProvider)
          .addLabItem(_selectedLabResult!['labResultId'], payload);
      _snack('Lab item added.');
      setState(() => _labItems = [..._labItems, item]);
    } catch (e) {
      _snack('Failed to add lab item: ${_errorMessage(e)}');
    }
  }

  Future<void> _deleteLabItem(String itemId) async {
    final confirmed = await _confirm('Remove this test item?');
    if (!confirmed) return;
    try {
      await ref.read(clinicalRecordServiceProvider).deleteLabItem(itemId);
      _snack('Lab item removed.');
      setState(() =>
          _labItems = _labItems.where((i) => i['itemId'] != itemId).toList());
    } catch (e) {
      _snack('Failed to remove lab item: ${_errorMessage(e)}');
    }
  }

  Future<void> _deleteLabResult(String labResultId) async {
    final confirmed = await _confirm('Delete this entire lab result?');
    if (!confirmed) return;
    try {
      await ref
          .read(clinicalRecordServiceProvider)
          .deleteLabResult(labResultId);
      _snack('Lab result deleted.');
      setState(() {
        _labResults =
            _labResults.where((l) => l['labResultId'] != labResultId).toList();
        _selectedLabResult = null;
        _labItems = [];
      });
    } catch (e) {
      _snack('Failed to delete lab result: ${_errorMessage(e)}');
    }
  }

  Future<void> _downloadLabResultFile(String? fileId) async {
    if (fileId == null || fileId.isEmpty) return;
    try {
      final bytes =
          await ref.read(clinicalRecordServiceProvider).downloadFile(fileId);
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/Lab_Report_${fileId.substring(0, 8)}';
      final file = File(path);
      await file.writeAsBytes(bytes);
      _snack('Report saved to $path');
    } catch (e) {
      _snack('Could not download lab report file: ${_errorMessage(e)}');
    }
  }

  Future<bool> _confirm(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirm'),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.dangerRed)),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ── Bottom sheet shell, reused by patient-info / prescriptions / labs ──
  void _openSheet({
    required String title,
    required Color headerColor,
    required Color headerFg,
    required Widget Function(BuildContext, StateSetter) bodyBuilder,
    List<Widget> Function(BuildContext, StateSetter)? headerActions,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: DraggableScrollableSheet(
            initialChildSize: 0.88,
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
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                    decoration: BoxDecoration(
                      color: headerColor,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(title,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: headerFg)),
                        ),
                        if (headerActions != null)
                          ...headerActions(context, setSheetState),
                        IconButton(
                          icon: Icon(Icons.close, color: headerFg),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(18),
                      child: bodyBuilder(context, setSheetState),
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

  Widget _chip(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      );

  // ── Patient Info sheet ────────────────────────────────────────────
  void _openPatientInfoSheet() {
    _openSheet(
      title: '🩺 Patient Case Info',
      headerColor: AppTheme.primaryLightTeal,
      headerFg: AppTheme.primaryDarkTeal,
      bodyBuilder: (context, setSheetState) {
        final c = _selectedConsultation!;
        final rawAvatarUrl = (c['patientAvatarUrl'] ?? c['patientAvatar'] ?? c['avatarUrl'] ?? '').toString();
        final avatarUrl = rawAvatarUrl.isNotEmpty
            ? (rawAvatarUrl.startsWith('http')
                ? rawAvatarUrl
                : '$kBaseUrl${rawAvatarUrl.startsWith('/') ? '' : '/'}$rawAvatarUrl')
            : '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppTheme.primaryTeal,
                    backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    onBackgroundImageError: avatarUrl.isNotEmpty ? (_, __) {} : null,
                    child: avatarUrl.isEmpty
                        ? Text(
                            ((c['patientName'] as String?) ?? '?')
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(c['patientName'] ?? '',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  _chip(
                      'ID: ${(c['patientId'] ?? '').toString().length >= 8 ? (c['patientId'] as String).substring(0, 8) : (c['patientId'] ?? '')}',
                      AppTheme.backgroundApp,
                      AppTheme.textMuted),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_patientHealthProfile != null) ...[
              const Text('PHYSICAL STATS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMuted,
                      letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _statBox('Weight',
                          '${_patientHealthProfile!['weightKg'] ?? '--'} kg')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _statBox('Height',
                          '${_patientHealthProfile!['heightCm'] ?? '--'} cm')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _statBox(
                          'BMI', '${_patientHealthProfile!['bmi'] ?? '--'}')),
                ],
              ),
              const SizedBox(height: 18),
            ],
            Text('ALLERGIES (${_patientAllergies.length})',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            _patientAllergies.isEmpty
                ? const Text('No known allergies registered.',
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _patientAllergies
                        .map((a) => _chip(
                            '⚠️ ${a['allergen']}${a['severity'] != null ? ' (${a['severity']})' : ''}',
                            const Color(0xFFFEF2F2),
                            const Color(0xFFB91C1C)))
                        .toList(),
                  ),
            const SizedBox(height: 18),
            Text('CHRONIC CONDITIONS (${_patientChronicConditions.length})',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            _patientChronicConditions.isEmpty
                ? const Text('No chronic conditions registered.',
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted))
                : Column(
                    children: _patientChronicConditions
                        .map((cond) => Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.backgroundApp,
                                border: Border.all(color: AppTheme.borderGray),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(cond['conditionName'] ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                          'ICD10: ${cond['icd10Code'] ?? 'N/A'}',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppTheme.textMuted)),
                                      _chip(
                                          cond['status'] ?? '',
                                          AppTheme.primaryLightTeal,
                                          AppTheme.primaryDarkTeal),
                                    ],
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
            if (_patientHealthProfile != null &&
                ((_patientHealthProfile!['surgicalHistory'] ?? '')
                        .toString()
                        .isNotEmpty ||
                    (_patientHealthProfile!['familyHistory'] ?? '')
                        .toString()
                        .isNotEmpty ||
                    (_patientHealthProfile!['additionalNotes'] ?? '')
                        .toString()
                        .isNotEmpty)) ...[
              const SizedBox(height: 18),
              const Text('MEDICAL HISTORY',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMuted,
                      letterSpacing: 0.5)),
              const SizedBox(height: 8),
              if ((_patientHealthProfile!['surgicalHistory'] ?? '')
                  .toString()
                  .isNotEmpty)
                _historyItem('Surgical History',
                    _patientHealthProfile!['surgicalHistory']),
              if ((_patientHealthProfile!['familyHistory'] ?? '')
                  .toString()
                  .isNotEmpty)
                _historyItem(
                    'Family History', _patientHealthProfile!['familyHistory']),
              if ((_patientHealthProfile!['additionalNotes'] ?? '')
                  .toString()
                  .isNotEmpty)
                _historyItem('Notes / Observations',
                    _patientHealthProfile!['additionalNotes']),
            ],
          ],
        );
      },
    );
  }

  Widget _statBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundApp,
        border: Border.all(color: AppTheme.borderGray),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _historyItem(String label, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryTeal,
                  letterSpacing: 0.3)),
          const SizedBox(height: 3),
          Text(content, style: const TextStyle(fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }

  // ── Prescriptions sheet ──────────────────────────────────────────
  void _openPrescriptionsSheet() {
    _loadPrescriptions();
    bool creating = false;
    bool addingItem = false;
    final issuedDateCtrl = TextEditingController(
        text: DateTime.now().toIso8601String().split('T')[0]);
    final validUntilCtrl = TextEditingController();
    final diagnosisCtrl = TextEditingController();
    final pharmacistCtrl = TextEditingController();

    final drugNameCtrl = TextEditingController();
    final dosageCtrl = TextEditingController();
    String route = 'ORAL';
    final frequencyCtrl = TextEditingController();
    final durationCtrl = TextEditingController(text: '7');
    final quantityCtrl = TextEditingController(text: '1');
    final refillsCtrl = TextEditingController(text: '0');
    final specialCtrl = TextEditingController();

    _openSheet(
      title: '💊 Prescriptions',
      headerColor: const Color(0xFFF5F3FF),
      headerFg: const Color(0xFF4C1D95),
      headerActions: (context, setSheetState) => [
        if (!creating)
          TextButton(
            onPressed: () => setSheetState(() => creating = true),
            child: const Text('+ New'),
          ),
      ],
      bodyBuilder: (context, setSheetState) {
        if (creating) {
          return Form(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New Prescription Details',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: issuedDateCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Issued Date *'),
                      readOnly: true,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate:
                              DateTime.now().subtract(const Duration(days: 30)),
                          lastDate:
                              DateTime.now().add(const Duration(days: 30)),
                        );
                        if (picked != null) {
                          setSheetState(() => issuedDateCtrl.text =
                              picked.toIso8601String().split('T')[0]);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: validUntilCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Valid Until'),
                      readOnly: true,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setSheetState(() => validUntilCtrl.text =
                              picked.toIso8601String().split('T')[0]);
                        }
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextFormField(
                  controller: diagnosisCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Diagnosis Notes',
                      hintText: 'Primary diagnosis, ICD-10 code...'),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: pharmacistCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Pharmacist Notes',
                      hintText: 'Instructions for the pharmacist...'),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setSheetState(() => creating = false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        if (issuedDateCtrl.text.trim().isEmpty) return;
                        await _createPrescription({
                          'issuedDate': issuedDateCtrl.text,
                          if (validUntilCtrl.text.isNotEmpty)
                            'validUntil': validUntilCtrl.text,
                          'diagnosisNotes': diagnosisCtrl.text,
                          'pharmacistNotes': pharmacistCtrl.text,
                          'status': 'ACTIVE',
                        });
                        setSheetState(() => creating = false);
                      },
                      child: const Text('Create Prescription'),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        if (_prescriptions.isEmpty) {
          return Column(
            children: [
              const SizedBox(height: 20),
              const Text('💊', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 10),
              const Text('No prescriptions yet for this consultation.',
                  style: TextStyle(color: AppTheme.textMuted),
                  textAlign: TextAlign.center),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () => setSheetState(() => creating = true),
                child: const Text('+ Create First Prescription'),
              ),
            ],
          );
        }

        final rx = _selectedPrescription;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _prescriptions.map<Widget>((r) {
                final selected =
                    rx != null && rx['prescriptionId'] == r['prescriptionId'];
                return GestureDetector(
                  onTap: () {
                    setSheetState(() {
                      _selectedPrescription = r;
                      addingItem = false;
                    });
                    _loadPrescriptionItems(r['prescriptionId']);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : const Color(0xFFF5F3FF),
                      border: Border.all(
                          color: selected
                              ? const Color(0xFFC4B5FD)
                              : Colors.transparent),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Rx — ${_mediumDate(r['issuedDate'])}',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? const Color(0xFF5B21B6)
                                : AppTheme.textMuted)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            if (rx != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF5FF),
                  border: Border.all(color: const Color(0xFFE9D5FF)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _chip(
                                  '📅 ${_mediumDate(rx['issuedDate'])}',
                                  const Color(0xFFEDE9FE),
                                  const Color(0xFF5B21B6)),
                              if ((rx['validUntil'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                _chip(
                                    '⏳ Valid until ${_mediumDate(rx['validUntil'])}',
                                    const Color(0xFFEDE9FE),
                                    const Color(0xFF5B21B6)),
                              _chip(rx['status'] ?? '', const Color(0xFFDCFCE7),
                                  const Color(0xFF166534)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: AppTheme.dangerRed, size: 20),
                          onPressed: () =>
                              _deletePrescription(rx['prescriptionId']),
                        ),
                      ],
                    ),
                    if ((rx['diagnosisNotes'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('📋 Diagnosis: ${rx['diagnosisNotes']}',
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('💊 Medications (${_prescriptionItems.length})',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  if (!addingItem)
                    OutlinedButton(
                      onPressed: () => setSheetState(() => addingItem = true),
                      child: const Text('+ Add Medication'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (addingItem)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundApp,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: drugNameCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Drug Name *'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: dosageCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Dosage *'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: route,
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: 'Route'),
                            items: _routeOptions
                                .map((r) => DropdownMenuItem(
                                    value: r['value'],
                                    child: Text(r['label']!)))
                                .toList(),
                            onChanged: (v) =>
                                setSheetState(() => route = v ?? 'ORAL'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: frequencyCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Frequency *'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: durationCtrl,
                            decoration: const InputDecoration(
                                labelText: 'Duration (d) *'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: quantityCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Quantity *'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: refillsCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Refills'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: specialCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Special Instructions'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                setSheetState(() => addingItem = false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              if (drugNameCtrl.text.trim().isEmpty ||
                                  dosageCtrl.text.trim().isEmpty ||
                                  frequencyCtrl.text.trim().isEmpty) {
                                return;
                              }
                              await _addPrescriptionItem({
                                'drugName': drugNameCtrl.text,
                                'dosage': dosageCtrl.text,
                                'route': route,
                                'frequency': frequencyCtrl.text,
                                'durationDays':
                                    int.tryParse(durationCtrl.text) ?? 7,
                                'quantity':
                                    int.tryParse(quantityCtrl.text) ?? 1,
                                'refillsAllowed':
                                    int.tryParse(refillsCtrl.text) ?? 0,
                                'specialInstructions': specialCtrl.text,
                              });
                              drugNameCtrl.clear();
                              dosageCtrl.clear();
                              frequencyCtrl.clear();
                              specialCtrl.clear();
                              setSheetState(() => addingItem = false);
                            },
                            child: const Text('Add Medication'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (_prescriptionItems.isEmpty && !addingItem)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                      'No medications added yet. Tap "+ Add Medication" to start.',
                      style:
                          TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                ),
              ..._prescriptionItems.asMap().entries.map((entry) {
                final i = entry.key;
                final item = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.borderGray),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                              colors: [Color(0xFF7C3AED), Color(0xFFA855F7)]),
                        ),
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['drugName'] ?? '',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5)),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 5,
                              runSpacing: 5,
                              children: [
                                _chip(item['dosage'] ?? '',
                                    AppTheme.backgroundApp, AppTheme.textMuted),
                                _chip(item['route'] ?? '',
                                    AppTheme.backgroundApp, AppTheme.textMuted),
                                _chip(item['frequency'] ?? '',
                                    AppTheme.backgroundApp, AppTheme.textMuted),
                                _chip('${item['durationDays']}d',
                                    AppTheme.backgroundApp, AppTheme.textMuted),
                                _chip('Qty: ${item['quantity']}',
                                    AppTheme.backgroundApp, AppTheme.textMuted),
                              ],
                            ),
                            if ((item['specialInstructions'] ?? '')
                                .toString()
                                .isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('📝 ${item['specialInstructions']}',
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontStyle: FontStyle.italic,
                                      color: AppTheme.textMuted)),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            size: 18, color: AppTheme.textMuted),
                        onPressed: () =>
                            _deletePrescriptionItem(item['itemId']),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  // ── Lab Results sheet ────────────────────────────────────────────
  void _openLabResultsSheet() {
    _loadLabResults();
    bool creating = false;
    bool addingItem = false;
    final labNameCtrl = TextEditingController();
    final reportTypeCtrl = TextEditingController();
    final reportDateCtrl = TextEditingController(
        text: DateTime.now().toIso8601String().split('T')[0]);
    String labStatus = 'RECEIVED';
    String overallFlag = 'NORMAL';
    final annotationCtrl = TextEditingController();
    PlatformFile? selectedFile;

    final testNameCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final unitCtrl = TextEditingController();
    String itemFlag = 'NORMAL';
    final loincCtrl = TextEditingController();
    final refLowCtrl = TextEditingController();
    final refHighCtrl = TextEditingController();

    _openSheet(
      title: '🔬 Lab Results',
      headerColor: const Color(0xFFF0F9FF),
      headerFg: const Color(0xFF0369A1),
      headerActions: (context, setSheetState) => [
        if (!creating)
          TextButton(
            onPressed: () => setSheetState(() => creating = true),
            child: const Text('+ New'),
          ),
      ],
      bodyBuilder: (context, setSheetState) {
        if (creating) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New Lab Report Details',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextFormField(
                controller: labNameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Lab Facility Name *',
                    hintText: 'E.g. Al Borg Diagnostics'),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: reportTypeCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Report Type *',
                        hintText: 'E.g. Lipid Profile'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: reportDateCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Report Date *'),
                    readOnly: true,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setSheetState(() => reportDateCtrl.text =
                            picked.toIso8601String().split('T')[0]);
                      }
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: labStatus,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Status *'),
                    items: _labStatusOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) =>
                        setSheetState(() => labStatus = v ?? 'RECEIVED'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: overallFlag,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Overall Flag *'),
                    items: _labFlagOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) =>
                        setSheetState(() => overallFlag = v ?? 'NORMAL'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.attach_file, size: 16),
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
              const SizedBox(height: 10),
              TextFormField(
                controller: annotationCtrl,
                decoration: const InputDecoration(
                    labelText: 'Clinical Annotation Notes',
                    hintText: 'Diagnostic observations, abnormal flags...'),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setSheetState(() => creating = false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      if (labNameCtrl.text.trim().isEmpty ||
                          reportTypeCtrl.text.trim().isEmpty) {
                        return;
                      }
                      await _createLabResult({
                        'labName': labNameCtrl.text,
                        'reportType': reportTypeCtrl.text,
                        'reportDate': reportDateCtrl.text,
                        'status': labStatus,
                        'overallFlag': overallFlag,
                        'doctorAnnotation': annotationCtrl.text,
                      }, selectedFile);
                      setSheetState(() => creating = false);
                    },
                    child: const Text('Create Lab Result'),
                  ),
                ],
              ),
            ],
          );
        }

        if (_labResults.isEmpty) {
          return Column(
            children: [
              const SizedBox(height: 20),
              const Text('🔬', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 10),
              const Text('No lab results recorded yet for this consultation.',
                  style: TextStyle(color: AppTheme.textMuted),
                  textAlign: TextAlign.center),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: () => setSheetState(() => creating = true),
                child: const Text('+ Create First Lab Result'),
              ),
            ],
          );
        }

        final lab = _selectedLabResult;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _labResults.map<Widget>((l) {
                final selected =
                    lab != null && lab['labResultId'] == l['labResultId'];
                return GestureDetector(
                  onTap: () {
                    setSheetState(() {
                      _selectedLabResult = l;
                      addingItem = false;
                    });
                    _loadLabItems(l['labResultId']);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFF0F9FF) : Colors.white,
                      border: Border.all(
                          color: selected
                              ? const Color(0xFF0284C7)
                              : AppTheme.borderGray),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                        '🧪 ${l['reportType']} — ${_mediumDate(l['reportDate'])}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? const Color(0xFF0369A1)
                                : AppTheme.textMuted)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            if (lab != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _chip(
                                  '📅 ${_mediumDate(lab['reportDate'])}',
                                  const Color(0xFFE0F2FE),
                                  const Color(0xFF0369A1)),
                              _chip(
                                  '🏥 ${lab['labName']}',
                                  const Color(0xFFE0F2FE),
                                  const Color(0xFF0369A1)),
                              _chip(
                                  lab['overallFlag'] ?? '',
                                  lab['overallFlag'] == 'CRITICAL'
                                      ? const Color(0xFFFEE2E2)
                                      : lab['overallFlag'] == 'ABNORMAL'
                                          ? const Color(0xFFFFF7ED)
                                          : const Color(0xFFDCFCE7),
                                  lab['overallFlag'] == 'CRITICAL'
                                      ? const Color(0xFFB91C1C)
                                      : lab['overallFlag'] == 'ABNORMAL'
                                          ? const Color(0xFFB45309)
                                          : const Color(0xFF166534)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: AppTheme.dangerRed, size: 20),
                          onPressed: () => _deleteLabResult(lab['labResultId']),
                        ),
                      ],
                    ),
                    if (lab['fileId'] != null &&
                        lab['fileId'].toString().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Text('📄', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('Lab Attachment Document',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold)),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.download, size: 15),
                              label: const Text('Download'),
                              onPressed: () => _downloadLabResultFile(
                                  lab['fileId']?.toString()),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if ((lab['doctorAnnotation'] ?? '')
                        .toString()
                        .isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('📋 Clinical Notes: ${lab['doctorAnnotation']}',
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('🧪 Test Items (${_labItems.length})',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  if (!addingItem)
                    OutlinedButton(
                      onPressed: () => setSheetState(() => addingItem = true),
                      child: const Text('+ Add Test Item'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (addingItem)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundApp,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Row(children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: testNameCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Test Name *'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: valueCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Value *'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: unitCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Unit *'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: itemFlag,
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: 'Flag *'),
                            items: _labItemFlagOptions
                                .map((f) =>
                                    DropdownMenuItem(value: f, child: Text(f)))
                                .toList(),
                            onChanged: (v) =>
                                setSheetState(() => itemFlag = v ?? 'NORMAL'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: loincCtrl,
                            decoration:
                                const InputDecoration(labelText: 'LOINC'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            controller: refLowCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Ref Low'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: refHighCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Ref High'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                setSheetState(() => addingItem = false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              if (testNameCtrl.text.trim().isEmpty ||
                                  valueCtrl.text.trim().isEmpty ||
                                  unitCtrl.text.trim().isEmpty) {
                                return;
                              }
                              await _addLabItem({
                                'testName': testNameCtrl.text,
                                'value': valueCtrl.text,
                                'unit': unitCtrl.text,
                                'flag': itemFlag,
                                'loincCode': loincCtrl.text,
                                'referenceLow':
                                    double.tryParse(refLowCtrl.text),
                                'referenceHigh':
                                    double.tryParse(refHighCtrl.text),
                              });
                              testNameCtrl.clear();
                              valueCtrl.clear();
                              unitCtrl.clear();
                              loincCtrl.clear();
                              refLowCtrl.clear();
                              refHighCtrl.clear();
                              setSheetState(() => addingItem = false);
                            },
                            child: const Text('Add Item'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (_labItems.isEmpty && !addingItem)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                      'No test items added yet. Tap "+ Add Test Item" to start.',
                      style:
                          TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
                ),
              ..._labItems.asMap().entries.map((entry) {
                final item = entry.value;
                final flag = item['flag'];
                final flagBg = flag == 'NORMAL'
                    ? const Color(0xFFDCFCE7)
                    : (flag == 'CRITICAL_HIGH' ||
                            flag == 'CRITICAL_LOW' ||
                            flag == 'CRITICAL')
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFFFF7ED);
                final flagFg = flag == 'NORMAL'
                    ? const Color(0xFF166534)
                    : (flag == 'CRITICAL_HIGH' ||
                            flag == 'CRITICAL_LOW' ||
                            flag == 'CRITICAL')
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFFB45309);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.borderGray),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(item['testName'] ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5)),
                                ),
                                _chip(flag ?? '', flagBg, flagFg),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 5,
                              runSpacing: 5,
                              children: [
                                _chip(
                                    'Value: ${item['value']} ${item['unit'] ?? ''}',
                                    const Color(0xFFE0F2FE),
                                    const Color(0xFF0369A1)),
                                if (item['referenceLow'] != null ||
                                    item['referenceHigh'] != null)
                                  _chip(
                                      'Ref: ${item['referenceLow'] ?? '--'} - ${item['referenceHigh'] ?? '--'}',
                                      AppTheme.backgroundApp,
                                      AppTheme.textMuted),
                                if ((item['loincCode'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  _chip(
                                      'LOINC: ${item['loincCode']}',
                                      AppTheme.backgroundApp,
                                      AppTheme.textMuted),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            size: 18, color: AppTheme.textMuted),
                        onPressed: () => _deleteLabItem(item['itemId']),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  // Shared by mobile & desktop chat views.
  Widget _buildMessageBubble(dynamic msg, bool isDoctor, double maxWidth) {
    return Align(
      alignment: isDoctor ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment:
              isDoctor ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '${msg['senderName'] ?? ''} • ${_shortTime(msg['sentAt'])}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDoctor ? AppTheme.primaryTeal : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomRight: Radius.circular(isDoctor ? 4 : 12),
                  bottomLeft: Radius.circular(isDoctor ? 12 : 4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: Text(
                msg['body'] ?? '',
                style: TextStyle(
                    color: isDoctor ? Colors.white : AppTheme.textMain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList(double maxWidth) {
    if (_isLoading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No messages yet. Send a message to start the consultation.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _messagesScrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, idx) {
        final msg = _messages[idx];
        final myUserId = ref.read(authNotifierProvider).currentUser?.id;
        final isDoctor = msg['senderId'] == myUserId;
        return _buildMessageBubble(msg, isDoctor, maxWidth);
      },
    );
  }

  Widget _buildStatusRow() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _statusFormValue,
            decoration: const InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            style: const TextStyle(fontSize: 13, color: AppTheme.textMain),
            items: _statusOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (val) => setState(() => _statusFormValue = val),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 38,
          child: ElevatedButton(
            onPressed: _isUpdatingStatus ? null : _updateStatus,
            child: _isUpdatingStatus
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Update'),
          ),
        ),
      ],
    );
  }

  // Row of icon buttons: patient info / prescriptions / labs — mirrors
  // Angular's header-actions toggle buttons, badge counts included.
  Widget _buildInfoActionsRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Patient Info',
          icon: const Icon(Icons.info_outline, size: 20),
          onPressed: _openPatientInfoSheet,
        ),
        _badgedIcon(
          icon: Icons.medication_outlined,
          count: _prescriptions.length,
          color: const Color(0xFF7C3AED),
          onTap: _openPrescriptionsSheet,
        ),
        _badgedIcon(
          icon: Icons.science_outlined,
          count: _labResults.length,
          color: const Color(0xFF0284C7),
          onTap: _openLabResultsSheet,
        ),
      ],
    );
  }

  Widget _badgedIcon({
    required IconData icon,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(icon, size: 20, color: color),
          onPressed: onTap,
        ),
        if (count > 0)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$count',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }

  Widget _buildReplyBar({required double bottomPadding}) {
    if (_selectedConsultation!['status'] == 'CLOSED') {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.only(
            left: 12, right: 12, top: 12, bottom: bottomPadding + 12),
        color: AppTheme.backgroundApp,
        child: const Text(
          'This consultation has been closed. Messages cannot be sent.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
      );
    }
    return Container(
      padding: EdgeInsets.only(
          left: 12, right: 8, top: 8, bottom: bottomPadding + 8),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceWhite,
        border: Border(top: BorderSide(color: AppTheme.borderGray)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Type a reply...',
                filled: true,
                fillColor: AppTheme.backgroundApp,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.send, color: AppTheme.primaryTeal),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildMobileChatScreen() {
    final c = _selectedConsultation!;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppTheme.backgroundApp,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryLightTeal,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _closeThread,
        ),
        titleSpacing: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c['subject'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain),
            ),
            Text(
              'Patient: ${c['patientName'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
        actions: [
          if (c['isUrgent'] == true)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Chip(
                label: Text('Urgent',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
                backgroundColor: AppTheme.dangerRed,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          _buildInfoActionsRow(),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: _buildStatusRow(),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _buildMessagesList(MediaQuery.of(context).size.width),
            ),
            _buildReplyBar(bottomPadding: 0),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 576;

    if (isMobile && _selectedConsultation != null) {
      return _buildMobileChatScreen();
    }

    return Scaffold(
      body: Container(
        padding: EdgeInsets.all(isMobile ? 14 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Consultations',
              style: TextStyle(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain),
            ),
            const SizedBox(height: 4),
            const Text(
              'Manage patient tele-consultations and messages.',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _selectedConsultation == null
                  ? Card(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : (_consultations.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No consultations assigned to you.',
                                    style: TextStyle(color: AppTheme.textMuted),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _consultations.length,
                                  separatorBuilder: (context, index) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final c = _consultations[index];
                                    final rawAvatarUrl = (c['patientAvatarUrl'] ?? c['patientAvatar'] ?? c['avatarUrl'] ?? '').toString();
                                    final avatarUrl = rawAvatarUrl.isNotEmpty
                                        ? (rawAvatarUrl.startsWith('http')
                                            ? rawAvatarUrl
                                            : '$kBaseUrl${rawAvatarUrl.startsWith('/') ? '' : '/'}$rawAvatarUrl')
                                        : '';
                                    final status = c['status'] as String?;
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.grey[300],
                                        backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                                        onBackgroundImageError: avatarUrl.isNotEmpty ? (_, __) {} : null,
                                        child: avatarUrl.isEmpty
                                            ? Text(
                                                ((c['patientName'] as String?) ?? '?')
                                                    .substring(0, 1),
                                                style: const TextStyle(
                                                    color: AppTheme.textMain,
                                                    fontWeight: FontWeight.bold),
                                              )
                                            : null,
                                      ),
                                      title: Text(c['patientName'] ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(c['subject'] ?? '',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                          Text(
                                            'Opened: ${(c['openedAt']?.toString().split('T').first) ?? ''}',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.textMuted),
                                          ),
                                        ],
                                      ),
                                      trailing: Chip(
                                        label: Text(status ?? '',
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.white)),
                                        backgroundColor: _statusColor(status),
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onTap: () => _selectConsultation(c),
                                    );
                                  },
                                )),
                    )
                  : Card(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            color: AppTheme.primaryLightTeal,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.arrow_back,
                                          size: 20),
                                      onPressed: _closeThread,
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _selectedConsultation!['subject'] ??
                                                '',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            'Patient: ${_selectedConsultation!['patientName'] ?? ''}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.textMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_selectedConsultation!['isUrgent'] ==
                                        true)
                                      Container(
                                        margin: const EdgeInsets.only(right: 4),
                                        child: const Chip(
                                          label: Text('Urgent',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11)),
                                          backgroundColor: AppTheme.dangerRed,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ),
                                    _buildInfoActionsRow(),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                _buildStatusRow(),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _buildMessagesList(
                                MediaQuery.of(context).size.width * 0.6),
                          ),
                          _buildReplyBar(bottomPadding: 0),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

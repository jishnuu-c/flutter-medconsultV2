import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/websocket_service.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../doctor_dashboard/data/consultation_service.dart';
import '../data/patient_service.dart';

class PatientConsultationsScreen extends ConsumerStatefulWidget {
  const PatientConsultationsScreen({super.key});

  @override
  ConsumerState<PatientConsultationsScreen> createState() =>
      _PatientConsultationsScreenState();
}

class _PatientConsultationsScreenState
    extends ConsumerState<PatientConsultationsScreen> {
  final _msgController = TextEditingController();
  bool _isLoading = false;
  String? _patientId;
  List<dynamic> _consultations = [];
  List<dynamic> _doctors = [];
  Map<String, dynamic>? _selectedConsultation;
  List<dynamic> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadPatientProfile();
    _loadDoctors();
  }

  @override
  void dispose() {
    _msgController.dispose();
    super.dispose();
  }

  Future<void> _loadPatientProfile() async {
    setState(() => _isLoading = true);
    try {
      final profile = await ref.read(patientServiceProvider).getMyProfile();
      _patientId = profile['patientId'];
      await _loadConsultations();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load patient profile.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDoctors() async {
    try {
      final docs = await ref.read(doctorServiceProvider).getAllDoctors();
      if (mounted) setState(() => _doctors = docs);
    } catch (_) {}
  }

  Future<void> _loadConsultations() async {
    if (_patientId == null) return;
    final res = await ref
        .read(consultationServiceProvider)
        .getConsultationsByPatient(_patientId!, page: 0, size: 50);
    if (mounted) setState(() => _consultations = res);
  }

  Future<void> _selectConsultation(dynamic c) async {
    setState(() {
      _selectedConsultation = Map<String, dynamic>.from(c);
      _isLoading = true;
    });

    final ws = ref.read(webSocketServiceProvider);
    if (!ws.isConnected) {
      ws.connect('ws://192.168.1.110:8080/ws');
    }

    try {
      final msgs = await ref
          .read(consultationServiceProvider)
          .getMessagesForConsultation(c['consultationId']);
      if (mounted) setState(() => _messages = msgs);
    } catch (_) {
      if (mounted) setState(() => _messages = []);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _selectedConsultation == null) return;

    _msgController.clear();
    try {
      final msg = await ref.read(consultationServiceProvider).sendMessage({
        'consultationId': _selectedConsultation!['consultationId'],
        'messageType': 'TEXT',
        'body': text,
      });
      if (mounted) setState(() => _messages.add(msg));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message')),
        );
      }
    }
  }

  void _openBookDialog() {
    String? doctorId = _doctors.isNotEmpty ? _doctors.first.doctorId : null;
    final subjectController = TextEditingController();
    bool isUrgent = false;
    bool submitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Book New Consultation'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: doctorId,
                  decoration: const InputDecoration(labelText: 'Doctor'),
                  items: _doctors
                      .map((d) => DropdownMenuItem<String>(
                          value: d.doctorId, child: Text(d.fullName)))
                      .toList(),
                  onChanged: (val) => setDialogState(() => doctorId = val),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subjectController,
                  maxLength: 255,
                  decoration: const InputDecoration(labelText: 'Subject'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mark as urgent'),
                  value: isUrgent,
                  onChanged: (val) =>
                      setDialogState(() => isUrgent = val ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: submitting ||
                      doctorId == null ||
                      subjectController.text.trim().isEmpty
                  ? null
                  : () async {
                      setDialogState(() => submitting = true);
                      try {
                        await ref
                            .read(consultationServiceProvider)
                            .openConsultation({
                          'patientId': _patientId,
                          'doctorId': doctorId,
                          'subject': subjectController.text.trim(),
                          'isUrgent': isUrgent,
                        });
                        if (mounted) Navigator.pop(ctx);
                        _loadConsultations();
                      } catch (_) {
                        setDialogState(() => submitting = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Failed to book consultation.')),
                          );
                        }
                      }
                    },
              child: const Text('Book'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(authNotifierProvider).currentUser?.id;

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
                    Text('My Tele-Consultations',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textMain)),
                    SizedBox(height: 4),
                    Text(
                        'Virtual consultation sessions and direct doctor messaging portal.',
                        style:
                            TextStyle(fontSize: 14, color: AppTheme.textMuted)),
                  ],
                ),
                if (_selectedConsultation == null)
                  ElevatedButton.icon(
                    onPressed: _patientId == null ? null : _openBookDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Consultation'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _selectedConsultation == null
                  ? Card(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _consultations.isEmpty
                              ? const Center(
                                  child: Text(
                                      'No consultations yet. Start one above.'))
                              : ListView.separated(
                                  itemCount: _consultations.length,
                                  separatorBuilder: (context, index) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final c = _consultations[index];
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.grey[300],
                                        child: Icon(Icons.video_call,
                                            color: AppTheme.textMain),
                                      ),
                                      title: Text(c['doctorName'] ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      subtitle: Text(c['subject'] ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      trailing: Chip(
                                        label: Text(c['status'] ?? ''),
                                        backgroundColor:
                                            AppTheme.primaryLightTeal,
                                      ),
                                      onTap: () => _selectConsultation(c),
                                    );
                                  },
                                ),
                    )
                  : Card(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            color: AppTheme.primaryLightTeal,
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back, size: 20),
                                  onPressed: () => setState(
                                      () => _selectedConsultation = null),
                                ),
                                Expanded(
                                  child: Text(
                                    '${_selectedConsultation!['doctorName']} — ${_selectedConsultation!['subject'] ?? ''}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                      _selectedConsultation!['status'] ?? ''),
                                  backgroundColor: AppTheme.successGreen
                                      .withValues(alpha: 0.2),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _isLoading
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : _messages.isEmpty
                                    ? const Center(
                                        child:
                                            Text('No messages yet. Say hello!'))
                                    : ListView.builder(
                                        padding: const EdgeInsets.all(16),
                                        itemCount: _messages.length,
                                        itemBuilder: (context, idx) {
                                          final msg = _messages[idx];
                                          final isMine =
                                              msg['senderId'] == currentUserId;
                                          return Align(
                                            alignment: isMine
                                                ? Alignment.centerRight
                                                : Alignment.centerLeft,
                                            child: Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 4),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 10),
                                              decoration: BoxDecoration(
                                                color: isMine
                                                    ? AppTheme.primaryTeal
                                                    : Colors.grey[200],
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                msg['body'] ?? '',
                                                style: TextStyle(
                                                    color: isMine
                                                        ? Colors.white
                                                        : AppTheme.textMain),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _msgController,
                                    decoration: const InputDecoration(
                                        hintText:
                                            'Type your message to doctor...'),
                                    onSubmitted: (_) => _sendMessage(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.send,
                                      color: AppTheme.primaryTeal),
                                  onPressed: _sendMessage,
                                ),
                              ],
                            ),
                          ),
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

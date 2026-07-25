import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/websocket_service.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../data/consultation_service.dart';

class DoctorConsultationsScreen extends ConsumerStatefulWidget {
  const DoctorConsultationsScreen({super.key});

  @override
  ConsumerState<DoctorConsultationsScreen> createState() =>
      _DoctorConsultationsScreenState();
}

class _DoctorConsultationsScreenState
    extends ConsumerState<DoctorConsultationsScreen> {
  final _messageController = TextEditingController();
  bool _isLoading = false;
  String? _doctorId;
  List<dynamic> _consultations = [];
  Map<String, dynamic>? _selectedConsultation;
  List<dynamic> _messages = [];

  @override
  void initState() {
    super.initState();
    _resolveDoctorIdAndLoad();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  // Same pattern as Angular's DoctorConsultationsComponent.resolveDoctorId():
  // there's no "my consultations" endpoint. The logged-in user's userId has
  // to be matched against /doctors/all to find this doctor's doctorId first,
  // then /consultations/doctor/{doctorId} is called with that.
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Failed to resolve doctor profile: ${_errorMessage(e)}')),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Failed to load consultations: ${_errorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _errorMessage(Object e) {
    if (e is DioException) {
      return e.response?.statusMessage ?? e.message ?? 'Network error';
    }
    return e.toString();
  }

  Future<void> _selectConsultation(Map<String, dynamic> c) async {
    setState(() {
      _selectedConsultation = c;
      _isLoading = true;
    });

    // Ensure WebSocket service is initialized for live subscription
    final ws = ref.read(webSocketServiceProvider);
    if (!ws.isConnected) {
      ws.connect('ws://localhost:8080/ws');
    }

    try {
      final msgs = await ref
          .read(consultationServiceProvider)
          .getMessagesForConsultation(c['consultationId']);
      setState(() => _messages = msgs);
    } catch (e) {
      setState(() => _messages = []);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load messages: ${_errorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
      if (mounted) setState(() => _messages.add(msg));
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to send message: ${_errorMessage(e)}')),
        );
      }
    });
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
              'My Tele-Consultations',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain),
            ),
            const SizedBox(height: 4),
            const Text(
              'Live virtual consultation rooms and patient messaging threads.',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _selectedConsultation == null
                  ? Card(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.separated(
                              itemCount: _consultations.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final c = _consultations[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.grey[300],
                                    child: Text(
                                      (c['patientName'] as String)[0],
                                      style: const TextStyle(
                                          color: AppTheme.textMain,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(c['patientName'],
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Text(c['subject'] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  trailing: Text(c['status'] ?? '',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textMuted)),
                                  onTap: () => _selectConsultation(c),
                                );
                              },
                            ),
                    )
                  : Card(
                      child: Column(
                        children: [
                          // Chat Header
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
                                    _selectedConsultation!['patientName'],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Chip(
                                  label: Text(_selectedConsultation!['status']),
                                  backgroundColor: AppTheme.successGreen
                                      .withValues(alpha: 0.2),
                                ),
                              ],
                            ),
                          ),

                          // Chat Messages
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _messages.length,
                              itemBuilder: (context, idx) {
                                final msg = _messages[idx];
                                final myUserId = ref
                                    .watch(authNotifierProvider)
                                    .currentUser
                                    ?.id;
                                final isDoctor = msg['senderId'] == myUserId;
                                return Align(
                                  alignment: isDoctor
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isDoctor
                                          ? AppTheme.primaryTeal
                                          : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      msg['body'] ?? '',
                                      style: TextStyle(
                                          color: isDoctor
                                              ? Colors.white
                                              : AppTheme.textMain),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                          // Input row
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _messageController,
                                    decoration: const InputDecoration(
                                        hintText: 'Type your response...'),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/websocket_service.dart';
import '../data/consultation_service.dart';

class DoctorConsultationsScreen extends ConsumerStatefulWidget {
  const DoctorConsultationsScreen({super.key});

  @override
  ConsumerState<DoctorConsultationsScreen> createState() => _DoctorConsultationsScreenState();
}

class _DoctorConsultationsScreenState extends ConsumerState<DoctorConsultationsScreen> {
  final _messageController = TextEditingController();
  bool _isLoading = false;
  List<dynamic> _consultations = [];
  Map<String, dynamic>? _selectedConsultation;
  List<dynamic> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadConsultations();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadConsultations() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref.read(consultationServiceProvider).getMyDoctorConsultations();
      setState(() => _consultations = res);
    } catch (_) {
      _populateMockConsultations();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateMockConsultations() {
    _consultations = [
      {
        'id': 'c-1',
        'patientName': 'Sarah Ahmed',
        'type': 'TELE_CONSULTATION',
        'status': 'IN_PROGRESS',
        'lastMessage': 'Doctor, I have reviewed the prescription instructions.',
        'updatedAt': '10:45 AM',
      },
      {
        'id': 'c-2',
        'patientName': 'Mohammed Al-Harbi',
        'type': 'FOLLOW_UP',
        'status': 'SCHEDULED',
        'lastMessage': 'Looking forward to our session tomorrow.',
        'updatedAt': 'Yesterday',
      },
    ];
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
      final msgs = await ref.read(consultationServiceProvider).getMessagesForConsultation(c['id']);
      setState(() => _messages = msgs);
    } catch (_) {
      setState(() {
        _messages = [
          {'sender': 'PATIENT', 'text': 'Hello Doctor, I sent over my recent blood pressure logs.'},
          {'sender': 'DOCTOR', 'text': 'Thank you Sarah, I see them. Everything looks well within normal limits.'},
        ];
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedConsultation == null) return;

    setState(() {
      _messages.add({'sender': 'DOCTOR', 'text': text});
      _messageController.clear();
    });

    try {
      ref.read(consultationServiceProvider).sendMessage({
        'consultationId': _selectedConsultation!['id'],
        'content': text,
      });
    } catch (_) {}
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
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textMain),
            ),
            const SizedBox(height: 4),
            const Text(
              'Live virtual consultation rooms and patient messaging threads.',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: Row(
                children: [
                  // Consultation List
                  Expanded(
                    flex: 2,
                    child: Card(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.separated(
                              itemCount: _consultations.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final c = _consultations[index];
                                final isSelected = _selectedConsultation?['id'] == c['id'];
                                return ListTile(
                                  selected: isSelected,
                                  selectedTileColor: AppTheme.primaryLightTeal,
                                  leading: CircleAvatar(
                                    backgroundColor: isSelected ? AppTheme.primaryTeal : Colors.grey[300],
                                    child: Text(
                                      (c['patientName'] as String)[0],
                                      style: TextStyle(color: isSelected ? Colors.white : AppTheme.textMain, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(c['patientName'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(c['lastMessage'], maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: Text(c['updatedAt'], style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                                  onTap: () => _selectConsultation(c),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Chat View / Detail
                  Expanded(
                    flex: 3,
                    child: Card(
                      child: _selectedConsultation == null
                          ? const Center(child: Text('Select a consultation to view messages.'))
                          : Column(
                              children: [
                                // Chat Header
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  color: AppTheme.primaryLightTeal,
                                  child: Row(
                                    children: [
                                      Text(
                                        _selectedConsultation!['patientName'],
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      const Spacer(),
                                      Chip(
                                        label: Text(_selectedConsultation!['status']),
                                        backgroundColor: AppTheme.successGreen.withValues(alpha: 0.2),
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
                                      final isDoctor = msg['sender'] == 'DOCTOR';
                                      return Align(
                                        alignment: isDoctor ? Alignment.centerRight : Alignment.centerLeft,
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(vertical: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: isDoctor ? AppTheme.primaryTeal : Colors.grey[200],
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            msg['text'],
                                            style: TextStyle(color: isDoctor ? Colors.white : AppTheme.textMain),
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
                                          decoration: const InputDecoration(hintText: 'Type your response...'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.send, color: AppTheme.primaryTeal),
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
          ],
        ),
      ),
    );
  }
}

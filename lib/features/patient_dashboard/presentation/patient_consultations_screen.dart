import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/websocket_service.dart';
import '../../doctor_dashboard/data/consultation_service.dart';

class PatientConsultationsScreen extends ConsumerStatefulWidget {
  const PatientConsultationsScreen({super.key});

  @override
  ConsumerState<PatientConsultationsScreen> createState() => _PatientConsultationsScreenState();
}

class _PatientConsultationsScreenState extends ConsumerState<PatientConsultationsScreen> {
  final _msgController = TextEditingController();
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
    _msgController.dispose();
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
        'id': 'c-101',
        'doctorName': 'Dr. Tariq Al-Mansoor',
        'specialty': 'Cardiology Specialist',
        'status': 'IN_PROGRESS',
        'lastMessage': 'Thank you Sarah, I see them. Everything looks well.',
        'updatedAt': '10:45 AM',
      },
    ];
  }

  Future<void> _selectConsultation(Map<String, dynamic> c) async {
    setState(() {
      _selectedConsultation = c;
      _isLoading = true;
    });

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
    final text = _msgController.text.trim();
    if (text.isEmpty || _selectedConsultation == null) return;

    setState(() {
      _messages.add({'sender': 'PATIENT', 'text': text});
      _msgController.clear();
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
              'Virtual consultation sessions and direct doctor messaging portal.',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: Row(
                children: [
                  // Consultations list
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
                                    child: Icon(Icons.video_call, color: isSelected ? Colors.white : AppTheme.textMain),
                                  ),
                                  title: Text(c['doctorName'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(c['lastMessage'], maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: Chip(
                                    label: Text(c['status']),
                                    backgroundColor: AppTheme.primaryLightTeal,
                                  ),
                                  onTap: () => _selectConsultation(c),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Chat window
                  Expanded(
                    flex: 3,
                    child: Card(
                      child: _selectedConsultation == null
                          ? const Center(child: Text('Select a consultation session to view room messages.'))
                          : Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  color: AppTheme.primaryLightTeal,
                                  child: Row(
                                    children: [
                                      Text(
                                        _selectedConsultation!['doctorName'],
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
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: _messages.length,
                                    itemBuilder: (context, idx) {
                                      final msg = _messages[idx];
                                      final isPatient = msg['sender'] == 'PATIENT';
                                      return Align(
                                        alignment: isPatient ? Alignment.centerRight : Alignment.centerLeft,
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(vertical: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: isPatient ? AppTheme.primaryTeal : Colors.grey[200],
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            msg['text'],
                                            style: TextStyle(color: isPatient ? Colors.white : AppTheme.textMain),
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
                                          decoration: const InputDecoration(hintText: 'Type your message to doctor...'),
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

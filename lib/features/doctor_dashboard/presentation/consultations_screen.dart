import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../data/consultation_service.dart';

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

  // Angular has no live-push endpoint either (pure REST, plain
  // sendMessage()/getMessagesForConsultation() calls) — so instead of a
  // WebSocket stub that connects but is never listened to, poll for new
  // messages while a thread is open, using the same REST call Angular
  // already relies on.
  Timer? _pollTimer;

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
    _pollTimer?.cancel();
    setState(() {
      _selectedConsultation = c;
      _statusFormValue = c['status'];
      _isLoading = true;
    });

    await _loadMessages(showSpinner: true);

    // Poll every 4s so a message the patient sends while this thread is
    // open shows up without the doctor having to reselect the consultation.
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
      final wasAtBottomOrEmpty = _messages.length != msgs.length;
      if (mounted) setState(() => _messages = msgs);
      if (wasAtBottomOrEmpty) _scrollToBottom();
    } catch (e) {
      if (showSpinner) {
        setState(() => _messages = []);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Failed to load messages: ${_errorMessage(e)}')),
          );
        }
      }
      // Silent on background polling failures — same as Angular, which
      // has no retry/backoff logic for message loads either.
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to send message: ${_errorMessage(e)}')),
        );
      }
    });
  }

  // Mirrors Angular updateStatus(): patch status, refresh the selected
  // consultation and the matching row in the inbox list.
  Future<void> _updateStatus() async {
    if (_selectedConsultation == null || _statusFormValue == null) return;
    setState(() => _isUpdatingStatus = true);
    try {
      final updated = await ref.read(consultationServiceProvider).updateStatus(
          _selectedConsultation!['consultationId'],
          {'status': _statusFormValue});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Consultation status updated.')),
        );
        setState(() {
          _selectedConsultation = Map<String, dynamic>.from(updated);
          final idx = _consultations.indexWhere(
              (c) => c['consultationId'] == updated['consultationId']);
          if (idx != -1) _consultations[idx] = updated;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to update status: ${_errorMessage(e)}')),
        );
      }
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

  // Compact status row shared by mobile & desktop headers.
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

  // Reply input, bottom-anchored. `bottomPadding` should already include the
  // keyboard inset so the field sits right above the keyboard instead of
  // being covered by it.
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

  // ── Dedicated full-screen, keyboard-safe chat view for mobile ──────────
  // Angular's side-by-side inbox/chat layout doesn't translate well to a
  // narrow screen with a keyboard open, so on mobile the open thread takes
  // over as its own screen: slim AppBar, message list that shrinks with the
  // keyboard, and the reply bar pinned just above it via viewInsets.
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
              padding: EdgeInsets.only(right: 12),
              child: Chip(
                label: Text('Urgent',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
                backgroundColor: AppTheme.dangerRed,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
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

    // Mobile with an open thread → dedicated full-screen chat Scaffold so
    // the keyboard resizes just the message list, not the whole dashboard
    // chrome (title/subtitle/padding) around it.
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
                                    final status = c['status'] as String?;
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.grey[300],
                                        child: Text(
                                          ((c['patientName'] as String?) ?? '?')
                                              .substring(0, 1),
                                          style: const TextStyle(
                                              color: AppTheme.textMain,
                                              fontWeight: FontWeight.bold),
                                        ),
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
                  // Desktop/tablet: side-by-side inbox + chat panel (keyboard
                  // isn't a concern on these form factors, so the original
                  // two-pane Angular-style layout is kept as-is).
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
                                        margin: const EdgeInsets.only(right: 8),
                                        child: const Chip(
                                          label: Text('Urgent',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11)),
                                          backgroundColor: AppTheme.dangerRed,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ),
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

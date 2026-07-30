import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
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
  final _messagesScrollController = ScrollController();
  bool _isLoading = false;
  String? _patientId;
  List<dynamic> _consultations = [];
  List<dynamic> _doctors = [];
  Map<String, dynamic>? _selectedConsultation;
  List<dynamic> _messages = [];

  // Angular polls the messages endpoint every 3s while a thread is open
  // (setInterval in ConsultationsComponent.startPolling). Mirrored here
  // with a REST poll instead of a WebSocket stub that's never listened to.
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadPatientProfile();
    _loadDoctors();
  }

  @override
  void dispose() {
    _msgController.dispose();
    _messagesScrollController.dispose();
    _pollTimer?.cancel();
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
    _pollTimer?.cancel();
    setState(() {
      _selectedConsultation = Map<String, dynamic>.from(c);
      _isLoading = true;
    });

    await _loadMessages(showSpinner: true);

    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
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
      final isNewMessage = _messages.length != msgs.length;
      if (mounted) setState(() => _messages = msgs);
      if (showSpinner || isNewMessage) _scrollToBottom();
    } catch (_) {
      if (showSpinner && mounted) setState(() => _messages = []);
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
      if (mounted) {
        setState(() => _messages.add(msg));
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message')),
        );
      }
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'OPEN':
        return AppTheme.infoBlue;
      case 'IN_PROGRESS':
        return AppTheme.warningAmber;
      case 'CLOSED':
        return AppTheme.textMuted;
      default:
        return AppTheme.textMuted;
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

  String _mediumDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
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

  // Mirrors Angular's doctorSelectOptions getter — "Dr. {fullName}".
  String _doctorLabel(dynamic d) => 'Dr. ${d.fullName}';

  void _openBookDialog() {
    String? doctorId = _doctors.isNotEmpty ? _doctors.first.doctorId : null;
    final subjectController = TextEditingController();
    bool isUrgent = false;
    bool submitting = false;
    bool subjectTouched = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final subjectValid = subjectController.text.trim().isNotEmpty &&
              subjectController.text.trim().length <= 255;
          final formValid = doctorId != null && subjectValid;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: AppTheme.surfaceWhite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.borderGray,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const Text('Book a Tele-Consultation',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textMain)),
                    const SizedBox(height: 16),
                    const Text('Select Doctor',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: doctorId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: AppTheme.backgroundApp,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius:
                                BorderRadius.all(Radius.circular(10))),
                      ),
                      hint: const Text('-- Choose a Doctor --'),
                      items: _doctors
                          .map((d) => DropdownMenuItem<String>(
                              value: d.doctorId, child: Text(_doctorLabel(d))))
                          .toList(),
                      onChanged: (val) => setDialogState(() => doctorId = val),
                    ),
                    const SizedBox(height: 16),
                    const Text('Subject / Reason for Consultation',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: subjectController,
                      maxLength: 255,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: AppTheme.backgroundApp,
                        hintText: 'Briefly describe your health concern',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: const OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius:
                                BorderRadius.all(Radius.circular(10))),
                        errorText: subjectTouched && !subjectValid
                            ? 'Subject is required.'
                            : null,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      onTapOutside: (_) =>
                          setDialogState(() => subjectTouched = true),
                    ),
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Mark as Urgent'),
                      value: isUrgent,
                      onChanged: (val) =>
                          setDialogState(() => isUrgent = val ?? false),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: submitting || !formValid
                                ? null
                                : () async {
                                    setDialogState(() => submitting = true);
                                    try {
                                      await ref
                                          .read(consultationServiceProvider)
                                          .openConsultation({
                                        'patientId': _patientId,
                                        'doctorId': doctorId,
                                        'subject':
                                            subjectController.text.trim(),
                                        'isUrgent': isUrgent,
                                      });
                                      if (mounted) Navigator.pop(ctx);
                                      _loadConsultations();
                                    } catch (_) {
                                      setDialogState(() => submitting = false);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'Failed to book consultation.')),
                                        );
                                      }
                                    }
                                  },
                            child: submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Book Consultation'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Shared bubble builder for message list.
  Widget _buildMessageBubble(dynamic msg, bool isMine, double maxWidth) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                color: isMine ? AppTheme.primaryTeal : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomRight: Radius.circular(isMine ? 4 : 12),
                  bottomLeft: Radius.circular(isMine ? 12 : 4),
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
                style:
                    TextStyle(color: isMine ? Colors.white : AppTheme.textMain),
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
            'No messages yet. Send a message below to start the conversation.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted),
          ),
        ),
      );
    }
    final currentUserId = ref.read(authNotifierProvider).currentUser?.id;
    return ListView.builder(
      controller: _messagesScrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, idx) {
        final msg = _messages[idx];
        final isMine = msg['senderId'] == currentUserId;
        return _buildMessageBubble(msg, isMine, maxWidth);
      },
    );
  }

  // Reply bar, keyboard-safe; shows closed notice instead when relevant.
  Widget _buildReplyBar({required double bottomPadding}) {
    if (_selectedConsultation!['status'] == 'CLOSED') {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.only(
            left: 12, right: 12, top: 12, bottom: bottomPadding + 12),
        color: AppTheme.backgroundApp,
        child: const Text(
          'This consultation has been closed.',
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
              controller: _msgController,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Type your message here...',
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

  Widget _buildConsultationListItem(dynamic c) {
    final status = c['status'] as String?;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppTheme.primaryLightTeal,
        child: const Icon(Icons.video_call, color: AppTheme.primaryDarkTeal),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text('Dr. ${c['doctorName'] ?? ''}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (c['isUrgent'] == true)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.priority_high,
                  color: AppTheme.dangerRed, size: 16),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c['subject'] ?? '',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            'Opened: ${_mediumDate(c['openedAt'] as String?)}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
      trailing: Chip(
        label: Text(status ?? '',
            style: const TextStyle(fontSize: 11, color: Colors.white)),
        backgroundColor: _statusColor(status),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onTap: () => _selectConsultation(c),
    );
  }

  // ── Dedicated full-screen, keyboard-safe chat view for mobile ──────────
  // Angular's side-by-side list/chat layout doesn't fit a narrow screen
  // with a keyboard open, so on mobile the open thread becomes its own
  // screen: slim AppBar, message list that shrinks with the keyboard, and
  // the reply bar pinned just above it.
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
              'Dr. ${c['doctorName'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              label: Text(c['status'] ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 11)),
              backgroundColor: _statusColor(c['status'] as String?),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
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
      floatingActionButton: (isMobile && _selectedConsultation == null)
          ? FloatingActionButton.extended(
              onPressed: _patientId == null ? null : _openBookDialog,
              icon: const Icon(Icons.add),
              label: const Text('New Consultation'),
            )
          : null,
      body: Container(
        padding: EdgeInsets.all(isMobile ? 14 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('My Tele-Consultations',
                          style: TextStyle(
                              fontSize: isMobile ? 20 : 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMain)),
                      const SizedBox(height: 4),
                      const Text(
                          'Virtual consultation sessions and direct doctor messaging portal.',
                          style: TextStyle(
                              fontSize: 14, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
                if (!isMobile && _selectedConsultation == null)
                  ElevatedButton.icon(
                    onPressed: _patientId == null ? null : _openBookDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Consultation'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _selectedConsultation == null
                  ? Card(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _consultations.isEmpty
                              ? const Center(
                                  child: Text(
                                      'No consultations yet. Start one above.',
                                      style:
                                          TextStyle(color: AppTheme.textMuted)),
                                )
                              : ListView.separated(
                                  itemCount: _consultations.length,
                                  separatorBuilder: (context, index) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) =>
                                      _buildConsultationListItem(
                                          _consultations[index]),
                                ),
                    )
                  // Desktop/tablet: side panel-free single card, matches
                  // Angular's two-pane feel without a keyboard to worry about.
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
                                  onPressed: _closeThread,
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedConsultation!['subject'] ?? '',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Consulting with Dr. ${_selectedConsultation!['doctorName'] ?? ''}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_selectedConsultation!['isUrgent'] == true)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: Chip(
                                      label: Text('Urgent',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11)),
                                      backgroundColor: AppTheme.dangerRed,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                Chip(
                                  label: Text(
                                      _selectedConsultation!['status'] ?? '',
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 11)),
                                  backgroundColor: _statusColor(
                                      _selectedConsultation!['status']
                                          as String?),
                                  visualDensity: VisualDensity.compact,
                                ),
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

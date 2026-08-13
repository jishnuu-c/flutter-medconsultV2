import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../doctor_dashboard/data/consultation_service.dart';
import '../data/patient_service.dart';
import '../data/chat_file_service.dart';
import '../data/review_service.dart';
import '../data/consultation_realtime_service.dart';

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

  // Mirrors ConsultationsComponent's chatSubscription — live push over STOMP
  // (websocket.service.ts's watchConsultation), not a poll.
  final _realtime = ConsultationRealtimeService();
  StreamSubscription<Map<String, dynamic>>? _chatSubscription;

  // ── File sharing state (mirrors selectedFile/isUploadingFile/fileMetadataCache) ──
  PlatformFile? _selectedFile;
  bool _isUploadingFile = false;
  final Map<String, ChatFileMetadata> _fileMetadataCache = {};
  final Map<String, Uint8List> _fileBytesCache = {};
  final Map<String, String> _fileMimeCache = {};

  // ── Image lightbox state (mirrors previewImageUrl/previewImageTitle/previewFileId) ──
  Uint8List? _previewImageBytes;
  String _previewImageTitle = '';
  String? _previewFileId;

  // ── Review modal state (mirrors showReviewModal / reviewForm) ──
  bool _showReviewModal = false;
  int _doctorRating = 5;
  int _ratingBedside = 5;
  int _ratingKnowledge = 5;
  int _ratingWait = 5;
  final _reviewTextController = TextEditingController();
  bool _isAnonymous = false;
  bool _isSubmittingReview = false;

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
    _reviewTextController.dispose();
    _chatSubscription?.cancel();
    _realtime.dispose();
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
    _chatSubscription?.cancel();
    setState(() {
      _selectedConsultation = Map<String, dynamic>.from(c);
      _isLoading = true;
    });

    await _loadMessages();
    _setupRealtimeSubscription(_selectedConsultation!['consultationId']);
  }

  // Mirrors ConsultationsComponent.loadMessages: fetch history, and hydrate
  // fileMetadata for any attachment messages.
  Future<void> _loadMessages() async {
    if (_selectedConsultation == null) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      final msgs = await ref
          .read(consultationServiceProvider)
          .getMessagesForConsultation(_selectedConsultation!['consultationId']);
      if (mounted) setState(() => _messages = msgs);
      for (final m in msgs) {
        final fileId = (m is Map ? m['fileId'] : null)?.toString();
        if (fileId != null && fileId.isNotEmpty) {
          _ensureFileMetadata(fileId);
          _ensureFileBlob(fileId);
        }
      }
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _messages = []);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Mirrors ConsultationsComponent.setupWebSocketSubscription: live-push new
  // messages onto the thread instead of polling for them.
  void _setupRealtimeSubscription(String consultationId) {
    _chatSubscription?.cancel();
    _chatSubscription =
        _realtime.watchConsultation(consultationId).listen((msg) {
      if (!mounted) return;
      if (msg['consultationId'] != _selectedConsultation?['consultationId']) {
        return;
      }
      final exists =
          _messages.any((m) => m is Map && m['messageId'] == msg['messageId']);
      if (exists) return;
      final fileId = msg['fileId']?.toString();
      if (fileId != null && fileId.isNotEmpty) {
        _ensureFileMetadata(fileId);
        _ensureFileBlob(fileId);
      }
      setState(() => _messages.add(msg));
      _scrollToBottom();
    });
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
    _chatSubscription?.cancel();
    _realtime.disconnect();
    setState(() => _selectedConsultation = null);
  }

  // ── File attach (mirrors onFileSelected / clearSelectedFile) ────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(withData: true);
    if (result != null && result.files.isNotEmpty) {
      setState(() => _selectedFile = result.files.first);
    }
  }

  void _clearSelectedFile() {
    setState(() => _selectedFile = null);
  }

  // Mirrors ConsultationsComponent.sendMessage: plain text, or upload the
  // attachment first then send a FILE message referencing it.
  Future<void> _sendMessage() async {
    if (_selectedConsultation == null) return;
    final body = _msgController.text.trim();
    if (body.isEmpty && _selectedFile == null) return;

    if (_selectedFile != null) {
      final file = _selectedFile!;
      final bytes = file.bytes;
      if (bytes == null) return;
      setState(() => _isUploadingFile = true);
      try {
        final meta = await ref.read(chatFileServiceProvider).uploadChatFile(
              bytes,
              file.name,
              mimeType: _guessMimeType(file.extension),
              patientId: _patientId,
            );
        _fileMetadataCache[meta.fileId] = meta;
        _fileBytesCache[meta.fileId] = bytes;
        if (meta.mimeType != null) _fileMimeCache[meta.fileId] = meta.mimeType!;

        final msg = await ref.read(consultationServiceProvider).sendMessage({
          'consultationId': _selectedConsultation!['consultationId'],
          'messageType': 'FILE',
          'fileId': meta.fileId,
          'body': body.isNotEmpty
              ? body
              : (meta.originalFilename ?? 'Sent an attachment'),
        });
        if (mounted) {
          final msgMap = Map<String, dynamic>.from(msg);
          final exists = _messages
              .any((m) => m is Map && m['messageId'] == msgMap['messageId']);
          setState(() {
            if (!exists) _messages.add(msgMap);
            _isUploadingFile = false;
            _selectedFile = null;
          });
          _msgController.clear();
          _scrollToBottom();
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isUploadingFile = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to send attachment message.')),
          );
        }
      }
      return;
    }

    if (body.isEmpty) return;
    _msgController.clear();
    try {
      final msg = await ref.read(consultationServiceProvider).sendMessage({
        'consultationId': _selectedConsultation!['consultationId'],
        'messageType': 'TEXT',
        'body': body,
      });
      if (mounted) {
        final msgMap = Map<String, dynamic>.from(msg);
        final exists = _messages
            .any((m) => m is Map && m['messageId'] == msgMap['messageId']);
        if (!exists) setState(() => _messages.add(msgMap));
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

  String? _guessMimeType(String? extension) {
    if (extension == null) return null;
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return null;
    }
  }

  // ── File rendering / download (mirrors isImageFile / ensureFileBlob /
  //    downloadChatFile / formatFileSize) ──────────────────────────────────

  bool _isImageFile(dynamic msg) {
    final fileId = msg['fileId']?.toString();
    if (fileId == null || fileId.isEmpty) return false;
    final mime = _fileMimeCache[fileId] ?? _fileMetadataCache[fileId]?.mimeType;
    if (mime != null) return mime.startsWith('image/');
    final name =
        _fileMetadataCache[fileId]?.originalFilename ?? msg['body']?.toString();
    if (name != null) {
      return RegExp(r'\.(png|jpe?g|gif|webp|svg|bmp)$', caseSensitive: false)
          .hasMatch(name);
    }
    return false;
  }

  Future<void> _ensureFileMetadata(String fileId) async {
    if (_fileMetadataCache.containsKey(fileId)) return;
    try {
      final meta =
          await ref.read(chatFileServiceProvider).getFileMetadata(fileId);
      _fileMetadataCache[fileId] = meta;
      if (meta.mimeType != null) _fileMimeCache[fileId] = meta.mimeType!;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _ensureFileBlob(String fileId) async {
    if (_fileBytesCache.containsKey(fileId)) return;
    try {
      final bytes =
          await ref.read(chatFileServiceProvider).downloadFile(fileId);
      _fileBytesCache[fileId] = Uint8List.fromList(bytes);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _downloadChatFile(String fileId, String? filename) async {
    try {
      var bytes = _fileBytesCache[fileId];
      bytes ??= Uint8List.fromList(
          await ref.read(chatFileServiceProvider).downloadFile(fileId));
      final dir = await getApplicationDocumentsDirectory();
      final safeName = filename ?? 'attachment_${fileId.substring(0, 8)}';
      final path = '${dir.path}/$safeName';
      await File(path).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to $path')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to download file attachment.')),
        );
      }
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return 'File';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ── Image lightbox (mirrors openImageModal / closeImageModal) ───────────

  void _openImageModal(Uint8List bytes, String title, String fileId) {
    setState(() {
      _previewImageBytes = bytes;
      _previewImageTitle = title;
      _previewFileId = fileId;
    });
  }

  void _closeImageModal() {
    setState(() {
      _previewImageBytes = null;
      _previewImageTitle = '';
      _previewFileId = null;
    });
  }

  // ── Review modal (mirrors openReviewModal / submitReview) ───────────────

  void _openReviewModal() {
    setState(() {
      _doctorRating = 5;
      _ratingBedside = 5;
      _ratingKnowledge = 5;
      _ratingWait = 5;
      _reviewTextController.text = '';
      _isAnonymous = false;
      _showReviewModal = true;
    });
  }

  void _closeReviewModal() {
    setState(() => _showReviewModal = false);
  }

  Future<void> _submitReview() async {
    if (_selectedConsultation == null) return;
    setState(() => _isSubmittingReview = true);
    final appOrConsId = _selectedConsultation!['appointmentId'] ??
        _selectedConsultation!['consultationId'];
    try {
      await ref.read(reviewServiceProvider).submitDoctorReview({
        'doctorId': _selectedConsultation!['doctorId'],
        'appointmentId': appOrConsId,
        'rating': _doctorRating,
        'ratingBedside': _ratingBedside,
        'ratingKnowledge': _ratingKnowledge,
        'ratingWait': _ratingWait,
        'reviewText': _reviewTextController.text,
        'isAnonymous': _isAnonymous,
      });
      if (mounted) {
        setState(() => _isSubmittingReview = false);
        _closeReviewModal();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Thank you! Your feedback has been submitted successfully.')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSubmittingReview = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to submit feedback. Please try again.')),
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
    final fileId = msg['fileId']?.toString();
    final hasFile = fileId != null && fileId.isNotEmpty;
    final meta = hasFile ? _fileMetadataCache[fileId] : null;
    // Only show body text if it isn't just duplicating the uploaded filename
    // (mirrors the *ngIf on msg.body in consultations.component.html).
    final showBody = (msg['body'] ?? '').toString().isNotEmpty &&
        (!hasFile ||
            (msg['body'] != meta?.originalFilename &&
                msg['body'] != 'Sent an attachment'));

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showBody)
                    Text(
                      msg['body'] ?? '',
                      style: TextStyle(
                          color: isMine ? Colors.white : AppTheme.textMain),
                    ),
                  if (hasFile) _buildAttachment(msg, fileId, isMine),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mirrors the Image / Non-Image Attachment Display Cards in
  // consultations.component.html.
  Widget _buildAttachment(dynamic msg, String fileId, bool isMine) {
    final meta = _fileMetadataCache[fileId];
    final bytes = _fileBytesCache[fileId];
    final filename = meta?.originalFilename ?? 'Attachment';

    if (_isImageFile(msg)) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isMine
                  ? Colors.white.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.12)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (bytes == null)
              Container(
                height: 140,
                alignment: Alignment.center,
                color: Colors.black.withValues(alpha: 0.04),
                child: const Text('Loading media...',
                    style: TextStyle(fontSize: 11)),
              )
            else
              GestureDetector(
                onTap: () => _openImageModal(bytes, filename, fileId),
                child: Image.memory(bytes,
                    height: 160, width: double.infinity, fit: BoxFit.cover),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: isMine
                  ? Colors.black.withValues(alpha: 0.22)
                  : const Color(0xFFF8FAFC),
              child: Row(
                children: [
                  Expanded(
                    child: Text(filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isMine ? Colors.white : AppTheme.textMain)),
                  ),
                  TextButton(
                    onPressed: () => _downloadChatFile(fileId, filename),
                    style: TextButton.styleFrom(
                      backgroundColor:
                          isMine ? Colors.white : AppTheme.primaryTeal,
                      foregroundColor:
                          isMine ? AppTheme.primaryTeal : Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: const Size(0, 0),
                    ),
                    child: const Text('Save', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMine
            ? Colors.white.withValues(alpha: 0.18)
            : AppTheme.backgroundApp,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isMine
                ? Colors.white.withValues(alpha: 0.3)
                : AppTheme.borderGray),
      ),
      child: Row(
        children: [
          const Text('📄', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isMine ? Colors.white : AppTheme.textMain)),
                Text(_formatFileSize(meta?.sizeBytes),
                    style: TextStyle(
                        fontSize: 10,
                        color: isMine ? Colors.white70 : AppTheme.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => _downloadChatFile(fileId, filename),
            style: TextButton.styleFrom(
              backgroundColor: isMine ? Colors.white : AppTheme.primaryTeal,
              foregroundColor: isMine ? AppTheme.primaryTeal : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(0, 0),
            ),
            child: const Text('📥 Download', style: TextStyle(fontSize: 11)),
          ),
        ],
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

  // Reply bar, keyboard-safe; shows a "Rate Consultation" footer instead
  // when the thread is closed (mirrors the two chat-input-bar variants).
  Widget _buildReplyBar({required double bottomPadding}) {
    if (_selectedConsultation!['status'] == 'CLOSED') {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.only(
            left: 12, right: 12, top: 12, bottom: bottomPadding + 12),
        color: AppTheme.backgroundApp,
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'This consultation has been closed.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _openReviewModal,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  foregroundColor: Colors.white),
              icon: const Text('⭐', style: TextStyle(fontSize: 13)),
              label: const Text('Rate Consultation'),
            ),
          ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedFile != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundApp,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.borderGray),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        '📎 ${_selectedFile!.name} (${_formatFileSize(_selectedFile!.size)})',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryTeal),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 14),
                      color: AppTheme.dangerRed,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _clearSelectedFile,
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file, color: AppTheme.textMuted),
                tooltip: 'Attach Document / Image',
                onPressed: _isUploadingFile ? null : _pickFile,
              ),
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 6),
              _isUploadingFile
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      icon: const Icon(Icons.send, color: AppTheme.primaryTeal),
                      onPressed: _sendMessage,
                    ),
            ],
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
    return Stack(
      children: [
        _buildScreen(context),
        if (_showReviewModal && _selectedConsultation != null)
          _buildReviewModalOverlay(),
        if (_previewImageBytes != null) _buildImageLightbox(),
      ],
    );
  }

  Widget _buildScreen(BuildContext context) {
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

  // ── Review submission modal (mirrors the REVIEW SUBMISSION MODAL DIALOG) ─

  Widget _ratingDropdown({
    required int value,
    required List<int> options,
    required ValueChanged<int> onChanged,
    bool stars = false,
  }) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Color(0xFFF9FAFB),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
      items: options
          .map((v) => DropdownMenuItem(
              value: v,
              child: Text(
                  stars ? '${'⭐' * v} ($v/5)' : '${'★' * v}${'☆' * (5 - v)}')))
          .toList(),
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }

  Widget _buildReviewModalOverlay() {
    final doctorName =
        _doctorLabel(_selectedDoctor(_selectedConsultation!['doctorId']));
    return GestureDetector(
      onTap: _closeReviewModal,
      child: Container(
        color: Colors.black54,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {},
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              margin: const EdgeInsets.all(20),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    color: AppTheme.primaryTeal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('⭐ Rate Your Consultation',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: _closeReviewModal,
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('👨‍⚕️ Doctor Review: $doctorName',
                              style: const TextStyle(
                                  color: AppTheme.primaryTeal,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                          const SizedBox(height: 12),
                          const Text('Overall Doctor Rating (1-5) *',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 6),
                          _ratingDropdown(
                            value: _doctorRating,
                            options: const [5, 4, 3, 2, 1],
                            stars: true,
                            onChanged: (v) => setState(() => _doctorRating = v),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Bedside *',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textMuted)),
                                    const SizedBox(height: 4),
                                    _ratingDropdown(
                                      value: _ratingBedside,
                                      options: const [5, 4, 3, 2, 1],
                                      onChanged: (v) =>
                                          setState(() => _ratingBedside = v),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Knowledge *',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textMuted)),
                                    const SizedBox(height: 4),
                                    _ratingDropdown(
                                      value: _ratingKnowledge,
                                      options: const [5, 4, 3, 2, 1],
                                      onChanged: (v) =>
                                          setState(() => _ratingKnowledge = v),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Wait Time *',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textMuted)),
                                    const SizedBox(height: 4),
                                    _ratingDropdown(
                                      value: _ratingWait,
                                      options: const [5, 4, 3, 2, 1],
                                      onChanged: (v) =>
                                          setState(() => _ratingWait = v),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text('Written Feedback (Optional)',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _reviewTextController,
                            maxLength: 2000,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: 'Share details of your experience...',
                              filled: true,
                              fillColor: const Color(0xFFF9FAFB),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _isAnonymous,
                            title: const Text('Submit this review anonymously',
                                style: TextStyle(fontSize: 13)),
                            onChanged: (v) =>
                                setState(() => _isAnonymous = v ?? false),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF9FAFB),
                      border:
                          Border(top: BorderSide(color: AppTheme.borderGray)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: _closeReviewModal,
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _isSubmittingReview ? null : _submitReview,
                          child: _isSubmittingReview
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('⭐ Submit Feedback'),
                        ),
                      ],
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

  // Mirrors doctorSelectOptions's lookup — resolves the doctor object behind
  // a doctorId for the review header, falling back to the consultation's own
  // doctorName if the doctor list hasn't loaded.
  dynamic _selectedDoctor(String? doctorId) {
    try {
      return _doctors.firstWhere((d) => d.doctorId == doctorId);
    } catch (_) {
      return _FallbackDoctorName(_selectedConsultation?['doctorName'] ?? '');
    }
  }

  // ── Full image lightbox (mirrors the Full Image Lightbox Modal) ─────────

  Widget _buildImageLightbox() {
    return GestureDetector(
      onTap: _closeImageModal,
      child: Container(
        color: Colors.black.withValues(alpha: 0.88),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: GestureDetector(
          onTap: () {},
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    color: const Color(0xFF1E293B),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(_previewImageTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (_previewFileId != null)
                          TextButton.icon(
                            onPressed: () => _downloadChatFile(
                                _previewFileId!, _previewImageTitle),
                            icon: const Icon(Icons.download,
                                size: 14, color: Colors.white),
                            label: const Text('Save',
                                style: TextStyle(color: Colors.white)),
                            style: TextButton.styleFrom(
                                backgroundColor: AppTheme.primaryTeal),
                          ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: _closeImageModal,
                          icon: const Icon(Icons.close,
                              size: 14, color: Colors.white),
                          label: const Text('Close',
                              style: TextStyle(color: Colors.white)),
                          style: TextButton.styleFrom(
                              backgroundColor: Colors.white24),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Container(
                      color: const Color(0xFF020617),
                      padding: const EdgeInsets.all(16),
                      child: Image.memory(_previewImageBytes!,
                          fit: BoxFit.contain),
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

class _FallbackDoctorName {
  final String fullName;
  _FallbackDoctorName(this.fullName);
}

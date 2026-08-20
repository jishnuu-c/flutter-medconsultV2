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
import '../../clinic_admin/data/doctor_models.dart';
import '../../doctor_dashboard/data/consultation_service.dart';
import '../data/patient_service.dart';
import '../data/chat_file_service.dart';
import '../data/review_service.dart';
import '../data/consultation_realtime_service.dart';
import '../../../core/utils/image_utils.dart';

String? _resolveAvatarUrl(String? raw) => resolveImageUrl(raw);

String? _findDoctorAvatarUrl({
  String? explicitAvatarUrl,
  String? doctorId,
  String? doctorName,
  List<dynamic>? doctors,
}) {
  final resolvedExplicit = _resolveAvatarUrl(explicitAvatarUrl);
  if (resolvedExplicit != null) return resolvedExplicit;

  if (doctors != null) {
    if (doctorId != null && doctorId.isNotEmpty) {
      for (final d in doctors) {
        if (d is DoctorModel && d.doctorId == doctorId) {
          final res = _resolveAvatarUrl(d.avatarUrl);
          if (res != null) return res;
        } else if (d is Map && (d['doctorId'] == doctorId || d['id'] == doctorId)) {
          final res = _resolveAvatarUrl(d['avatarUrl']?.toString() ?? d['doctorAvatarUrl']?.toString());
          if (res != null) return res;
        }
      }
    }
    if (doctorName != null && doctorName.trim().isNotEmpty) {
      final cleanDoc = doctorName.replaceAll(RegExp(r'^(Dr\.\s*|dr\.\s*)', caseSensitive: false), '').trim().toLowerCase();
      if (cleanDoc.isNotEmpty) {
        for (final d in doctors) {
          if (d is DoctorModel) {
            final dName = d.fullName.replaceAll(RegExp(r'^(Dr\.\s*|dr\.\s*)', caseSensitive: false), '').trim().toLowerCase();
            if (dName == cleanDoc || (dName.isNotEmpty && (cleanDoc.contains(dName) || dName.contains(cleanDoc)))) {
              final res = _resolveAvatarUrl(d.avatarUrl);
              if (res != null) return res;
            }
          } else if (d is Map) {
            final rawName = (d['fullName'] ?? d['name'] ?? d['doctorName'] ?? '').toString();
            final dName = rawName.replaceAll(RegExp(r'^(Dr\.\s*|dr\.\s*)', caseSensitive: false), '').trim().toLowerCase();
            if (dName == cleanDoc || (dName.isNotEmpty && (cleanDoc.contains(dName) || dName.contains(cleanDoc)))) {
              final res = _resolveAvatarUrl(d['avatarUrl']?.toString() ?? d['doctorAvatarUrl']?.toString());
              if (res != null) return res;
            }
          }
        }
      }
    }
  }
  return null;
}

Widget _buildDoctorAvatarWidget(
  String doctorName, {
  double radius = 20,
  String? avatarUrl,
  String? doctorId,
  List<dynamic>? doctors,
}) {
  final resolvedUrl = _findDoctorAvatarUrl(
    explicitAvatarUrl: avatarUrl,
    doctorId: doctorId,
    doctorName: doctorName,
    doctors: doctors,
  );

  String initials = '';
  final nameClean = doctorName.replaceAll(RegExp(r'^(Dr\.\s*|dr\.\s*)', caseSensitive: false), '').trim();
  final nameParts = nameClean.split(' ');
  if (nameParts.isNotEmpty) {
    if (nameParts.length >= 2) {
      initials = (nameParts[0].isNotEmpty ? nameParts[0][0] : '') +
          (nameParts[nameParts.length - 1].isNotEmpty ? nameParts[nameParts.length - 1][0] : '');
    } else {
      initials = nameParts[0].isNotEmpty ? nameParts[0][0] : '';
    }
  }
  initials = initials.toUpperCase();
  if (initials.isEmpty) initials = 'D';

  return CircleAvatar(
    radius: radius,
    backgroundColor: AppTheme.primaryLightTeal,
    backgroundImage: resolvedUrl != null ? NetworkImage(resolvedUrl) : null,
    onBackgroundImageError: resolvedUrl != null ? (_, __) {} : null,
    child: resolvedUrl == null
        ? Text(
            initials,
            style: TextStyle(
              color: AppTheme.primaryDarkTeal,
              fontWeight: FontWeight.bold,
              fontSize: radius * 0.8,
            ),
          )
        : null,
  );
}


class PatientConsultationsScreen extends ConsumerStatefulWidget {
  const PatientConsultationsScreen({super.key});

  @override
  ConsumerState<PatientConsultationsScreen> createState() =>
      _PatientConsultationsScreenState();
}

class _PatientConsultationsScreenState
    extends ConsumerState<PatientConsultationsScreen> {
  bool _isLoading = false;
  String? _patientId;
  List<dynamic> _consultations = [];
  List<dynamic> _doctors = [];

  @override
  void initState() {
    super.initState();
    _loadPatientProfile();
    _loadDoctors();
  }

  Future<void> _loadPatientProfile() async {
    setState(() => _isLoading = true);
    try {
      final profile = await ref.read(patientServiceProvider).getMyProfile();
      if (profile != null && profile is Map && profile['patientId'] != null) {
        _patientId = profile['patientId'];
        await _loadConsultations();
      }
    } catch (_) {
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

  void _selectConsultation(dynamic c) {
    // Push chat screen as a fullscreen route on root navigator.
    // This completely hides the ShellRoute's top bar, sidebar, and bottom navigation bar.
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: ConsultationChatView(
            consultation: Map<String, dynamic>.from(c),
            patientId: _patientId,
            doctors: _doctors,
            isMobile: true,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    ).then((_) {
      _loadConsultations();
    });
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'OPEN':
        return AppTheme.primaryTeal;
      case 'IN_PROGRESS':
        return AppTheme.warningAmber;
      case 'CLOSED':
        return AppTheme.textMuted;
      default:
        return AppTheme.textMuted;
    }
  }

  String _formatStatus(String? status) {
    if (status == null) return '';
    switch (status) {
      case 'OPEN':
        return 'Open';
      case 'IN_PROGRESS':
        return 'In Progress';
      case 'CLOSED':
        return 'Closed';
      default:
        return status;
    }
  }

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
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: AppTheme.borderGray,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const Text(
                      'Book a Tele-Consultation',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Select Doctor',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: doctorId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: AppTheme.backgroundApp,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderSide: BorderSide.none,
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ),
                      ),
                      hint: const Text('-- Choose a Doctor --'),
                      items: _doctors
                          .map((d) => DropdownMenuItem<String>(
                                value: d.doctorId,
                                child: Text(_doctorLabel(d)),
                              ))
                          .toList(),
                      onChanged: (val) => setDialogState(() => doctorId = val),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Subject / Reason for Consultation',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: subjectController,
                      maxLength: 255,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: AppTheme.backgroundApp,
                        hintText: 'Briefly describe your health concern',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: const OutlineInputBorder(
                          borderSide: BorderSide.none,
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ),
                        errorText: subjectTouched && !subjectValid
                            ? 'Subject is required.'
                            : null,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      onTapOutside: (_) => setDialogState(() => subjectTouched = true),
                    ),
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'Mark as Urgent',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      value: isUrgent,
                      activeColor: AppTheme.primaryTeal,
                      onChanged: (val) => setDialogState(() => isUrgent = val ?? false),
                    ),
                    const SizedBox(height: 16),
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
                                      await ref.read(consultationServiceProvider).openConsultation({
                                        'patientId': _patientId,
                                        'doctorId': doctorId,
                                        'subject': subjectController.text.trim(),
                                        'isUrgent': isUrgent,
                                      });
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      _loadConsultations();
                                    } catch (_) {
                                      setDialogState(() => submitting = false);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Failed to book consultation.'),
                                          ),
                                        );
                                      }
                                    }
                                  },
                            child: submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
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

  Widget _buildDoctorAvatar(
    String doctorName, {
    double radius = 20,
    String? avatarUrl,
    String? doctorId,
  }) {
    return _buildDoctorAvatarWidget(
      doctorName,
      radius: radius,
      avatarUrl: avatarUrl,
      doctorId: doctorId,
      doctors: _doctors,
    );
  }

  Widget _buildStatusBadge(String? status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        _formatStatus(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _mediumDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Widget _buildConsultationListItem(dynamic c, bool isSelected) {
    final status = c['status'] as String?;
    final doctorName = c['doctorName'] ?? '';
    final doctorId = c['doctorId']?.toString();
    final avatarUrl = (c['doctorAvatarUrl'] ??
            c['avatarUrl'] ??
            c['doctorProfileImage'] ??
            c['imageUrl'])
        ?.toString();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryLightTeal.withValues(alpha: 0.4) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppTheme.primaryTeal : AppTheme.borderGray,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: _buildDoctorAvatar(
          doctorName,
          avatarUrl: avatarUrl,
          doctorId: doctorId,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Dr. $doctorName',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.textMain,
                ),
              ),
            ),
            if (c['isUrgent'] == true)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.dangerRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.dangerRed.withValues(alpha: 0.2)),
                ),
                child: const Text(
                  'Urgent',
                  style: TextStyle(
                    color: AppTheme.dangerRed,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              c['subject'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'Opened: ${_mediumDate(c['openedAt'] as String?)}',
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
        trailing: _buildStatusBadge(status),
        onTap: () => _selectConsultation(c),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppTheme.primaryLightTeal,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                size: 48,
                color: AppTheme.primaryTeal,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Consultations Yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textMain,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Start a new consultation with a doctor.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width <= 768;

    return Scaffold(
      backgroundColor: AppTheme.backgroundApp,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _patientId == null ? null : _openBookDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Consultation', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadConsultations();
            await _loadDoctors();
          },
          color: AppTheme.primaryTeal,
          child: ListView(
            padding: EdgeInsets.all(isMobile ? 14 : 24),
            children: [
              // Hero Header Card
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isMobile ? 18 : 22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF042F2E), Color(0xFF0F766E), Color(0xFF14B8A6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'TELEMEDICINE & CHAT',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'My Consultations',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Chat directly with your verified specialists and review medical advice',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.white.withValues(alpha: 0.88),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _patientId == null ? null : _openBookDialog,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('New', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F766E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Search and consultation count
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Active Threads (${_consultations.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const Text(
                    'Tap a consultation to enter chat',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // List of Consultations
              if (_isLoading && _consultations.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal)),
                )
              else if (_consultations.isEmpty)
                _buildEmptyState()
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _consultations.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final c = _consultations[index];
                    return _buildConsultationListItem(c, false);
                  },
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class ConsultationChatView extends ConsumerStatefulWidget {
  final Map<String, dynamic> consultation;
  final String? patientId;
  final List<dynamic> doctors;
  final bool isMobile;
  final VoidCallback? onClose;

  const ConsultationChatView({
    super.key,
    required this.consultation,
    required this.patientId,
    required this.doctors,
    required this.isMobile,
    this.onClose,
  });

  @override
  ConsumerState<ConsultationChatView> createState() => _ConsultationChatViewState();
}

class _ConsultationChatViewState extends ConsumerState<ConsultationChatView> {
  final _msgController = TextEditingController();
  final _messagesScrollController = ScrollController();
  bool _isLoading = false;
  List<dynamic> _messages = [];

  final _realtime = ConsultationRealtimeService();
  StreamSubscription<Map<String, dynamic>>? _chatSubscription;

  PlatformFile? _selectedFile;
  bool _isUploadingFile = false;
  final Map<String, ChatFileMetadata> _fileMetadataCache = {};
  final Map<String, Uint8List> _fileBytesCache = {};
  final Map<String, String> _fileMimeCache = {};

  Uint8List? _previewImageBytes;
  String _previewImageTitle = '';
  String? _previewFileId;

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
    _loadMessages();
    _setupRealtimeSubscription(widget.consultation['consultationId']);
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

  @override
  void didUpdateWidget(covariant ConsultationChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.consultation['consultationId'] != oldWidget.consultation['consultationId']) {
      _chatSubscription?.cancel();
      _selectedFile = null;
      _isUploadingFile = false;
      _messages.clear();
      _loadMessages();
      _setupRealtimeSubscription(widget.consultation['consultationId']);
    }
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final msgs = await ref
          .read(consultationServiceProvider)
          .getMessagesForConsultation(widget.consultation['consultationId']);
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

  void _setupRealtimeSubscription(String consultationId) {
    _chatSubscription?.cancel();
    _chatSubscription =
        _realtime.watchConsultation(consultationId).listen((msg) {
      if (!mounted) return;
      if (msg['consultationId'] != widget.consultation['consultationId']) {
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

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(withData: true);
    if (result != null && result.files.isNotEmpty) {
      setState(() => _selectedFile = result.files.first);
    }
  }

  void _clearSelectedFile() {
    setState(() => _selectedFile = null);
  }

  Future<void> _sendMessage() async {
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
              patientId: widget.patientId,
            );
        _fileMetadataCache[meta.fileId] = meta;
        _fileBytesCache[meta.fileId] = bytes;
        if (meta.mimeType != null) _fileMimeCache[meta.fileId] = meta.mimeType!;

        final msg = await ref.read(consultationServiceProvider).sendMessage({
          'consultationId': widget.consultation['consultationId'],
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
        'consultationId': widget.consultation['consultationId'],
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
    setState(() => _isSubmittingReview = true);
    final appOrConsId = widget.consultation['appointmentId'] ??
        widget.consultation['consultationId'];
    try {
      await ref.read(reviewServiceProvider).submitDoctorReview({
        'doctorId': widget.consultation['doctorId'],
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
        return AppTheme.primaryTeal;
      case 'IN_PROGRESS':
        return AppTheme.warningAmber;
      case 'CLOSED':
        return AppTheme.textMuted;
      default:
        return AppTheme.textMuted;
    }
  }

  String _formatStatus(String? status) {
    if (status == null) return '';
    switch (status) {
      case 'OPEN':
        return 'Open';
      case 'IN_PROGRESS':
        return 'In Progress';
      case 'CLOSED':
        return 'Closed';
      default:
        return status;
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

  String _doctorLabel(dynamic d) => 'Dr. ${d.fullName}';

  Widget _buildDoctorAvatar(
    String doctorName, {
    double radius = 20,
    String? avatarUrl,
    String? doctorId,
  }) {
    return _buildDoctorAvatarWidget(
      doctorName,
      radius: radius,
      avatarUrl: avatarUrl,
      doctorId: doctorId,
      doctors: widget.doctors,
    );
  }

  Widget _buildStatusBadge(String? status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        _formatStatus(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildMessageBubble(dynamic msg, bool isMine, double maxWidth) {
    final fileId = msg['fileId']?.toString();
    final hasFile = fileId != null && fileId.isNotEmpty;
    final meta = hasFile ? _fileMetadataCache[fileId] : null;
    final showBody = (msg['body'] ?? '').toString().isNotEmpty &&
        (!hasFile ||
            (msg['body'] != meta?.originalFilename &&
                msg['body'] != 'Sent an attachment'));
    final senderName = (msg['senderName'] ?? '').toString();

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth * 0.80),
        margin: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMine && senderName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 3),
                child: Text(
                  senderName,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryTeal,
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: isMine
                    ? const LinearGradient(
                        colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isMine ? null : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomRight: Radius.circular(isMine ? 3 : 18),
                  bottomLeft: Radius.circular(isMine ? 18 : 3),
                ),
                border: isMine
                    ? null
                    : Border.all(color: const Color(0xFFE2E8F0), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.035),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
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
                        fontSize: 14,
                        color: isMine ? Colors.white : const Color(0xFF1E293B),
                        height: 1.35,
                      ),
                    ),
                  if (hasFile) _buildAttachment(msg, fileId, isMine),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _shortTime(msg['sentAt']),
                        style: TextStyle(
                          fontSize: 10,
                          color: isMine
                              ? Colors.white.withValues(alpha: 0.75)
                              : AppTheme.textMuted,
                        ),
                      ),
                      if (isMine) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.done_all_rounded,
                          size: 13,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                ? Colors.white.withValues(alpha: 0.3)
                : const Color(0xFFE2E8F0),
          ),
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
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Loading media...', style: TextStyle(fontSize: 11)),
                  ],
                ),
              )
            else
              GestureDetector(
                onTap: () => _openImageModal(bytes, filename, fileId),
                child: Image.memory(bytes, height: 160, width: double.infinity, fit: BoxFit.cover),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: isMine ? Colors.black.withValues(alpha: 0.22) : const Color(0xFFF8FAFC),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isMine ? Colors.white : AppTheme.textMain,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _downloadChatFile(fileId, filename),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isMine ? Colors.white : AppTheme.primaryTeal,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: isMine ? AppTheme.primaryTeal : Colors.white,
                        ),
                      ),
                    ),
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMine ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMine ? Colors.white.withValues(alpha: 0.3) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isMine ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.description_rounded,
              size: 20,
              color: isMine ? Colors.white : const Color(0xFF0284C7),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: isMine ? Colors.white : AppTheme.textMain,
                  ),
                ),
                Text(
                  _formatFileSize(meta?.sizeBytes),
                  style: TextStyle(
                    fontSize: 10,
                    color: isMine ? Colors.white70 : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(
              Icons.download_rounded,
              size: 18,
              color: isMine ? Colors.white : AppTheme.primaryTeal,
            ),
            onPressed: () => _downloadChatFile(fileId, filename),
            tooltip: 'Download File',
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(double maxWidth) {
    if (_isLoading && _messages.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryTeal),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Color(0xFFCCFBF1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.forum_outlined, size: 28, color: Color(0xFF0F766E)),
              ),
              const SizedBox(height: 12),
              const Text(
                'No messages yet',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Type your clinical question below to start the conversation.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );
    }
    final currentUserId = ref.read(authNotifierProvider).currentUser?.id;
    return ListView.builder(
      controller: _messagesScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      itemCount: _messages.length,
      itemBuilder: (context, idx) {
        final msg = _messages[idx];
        final isMine = msg['senderId'] == currentUserId;
        return _buildMessageBubble(msg, isMine, maxWidth);
      },
    );
  }

  Widget _buildReplyBar({required double bottomPadding}) {
    if (widget.consultation['status'] == 'CLOSED') {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 14,
          bottom: bottomPadding + 14,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline_rounded, size: 18, color: AppTheme.textMuted),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'This consultation is closed.',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _openReviewModal,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
              label: const Text('Rate Doctor', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: bottomPadding + 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedFile != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFCCFBF1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF99F6E4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.attach_file_rounded, size: 14, color: Color(0xFF0F766E)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${_selectedFile!.name} (${_formatFileSize(_selectedFile!.size)})',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _clearSelectedFile,
                      child: const Icon(Icons.cancel, size: 16, color: Color(0xFFDC2626)),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF0F766E), size: 24),
                tooltip: 'Attach file',
                onPressed: _isUploadingFile ? null : _pickFile,
              ),
              Expanded(
                child: TextField(
                  controller: _msgController,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Type your message...',
                    hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13.5),
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.2),
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              _isUploadingFile
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F766E)),
                      ),
                    )
                  : CircleAvatar(
                      backgroundColor: const Color(0xFF0F766E),
                      radius: 20,
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 17),
                        onPressed: _sendMessage,
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStarRatingSelector({
    required int rating,
    required ValueChanged<int> onChanged,
    double size = 28,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        final isSelected = starValue <= rating;
        return GestureDetector(
          onTap: () => onChanged(starValue),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              isSelected ? Icons.star_rounded : Icons.star_outline_rounded,
              color: isSelected ? Colors.amber : AppTheme.textMuted,
              size: size,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSubRatingItem(String label, int rating, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 4),
        _buildStarRatingSelector(rating: rating, onChanged: onChanged, size: 22),
      ],
    );
  }

  Widget _buildReviewModalOverlay() {
    final doctorName = _doctorLabel(_selectedDoctor(widget.consultation['doctorId']));
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
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Rate Your Consultation',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
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
                          Text(
                            'Doctor Review: $doctorName',
                            style: const TextStyle(
                              color: AppTheme.primaryTeal,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Overall Doctor Rating *',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          _buildStarRatingSelector(
                            rating: _doctorRating,
                            onChanged: (v) => setState(() => _doctorRating = v),
                            size: 32,
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildSubRatingItem('Bedside Manner *', _ratingBedside, (v) => setState(() => _ratingBedside = v)),
                              _buildSubRatingItem('Knowledge *', _ratingKnowledge, (v) => setState(() => _ratingKnowledge = v)),
                              _buildSubRatingItem('Wait Time *', _ratingWait, (v) => setState(() => _ratingWait = v)),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Written Feedback (Optional)',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _reviewTextController,
                            maxLength: 2000,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: 'Share details of your experience...',
                              hintStyle: const TextStyle(color: AppTheme.textMuted),
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
                            title: const Text(
                              'Submit this review anonymously',
                              style: TextStyle(fontSize: 13),
                            ),
                            onChanged: (v) => setState(() => _isAnonymous = v ?? false),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF9FAFB),
                      border: Border(top: BorderSide(color: AppTheme.borderGray)),
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
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Submit Feedback'),
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

  dynamic _selectedDoctor(String? doctorId) {
    try {
      return widget.doctors.firstWhere((d) => d.doctorId == doctorId);
    } catch (_) {
      return _FallbackDoctorName(widget.consultation['doctorName'] ?? '');
    }
  }

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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _previewImageTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_previewFileId != null)
                          TextButton.icon(
                            onPressed: () => _downloadChatFile(_previewFileId!, _previewImageTitle),
                            icon: const Icon(Icons.download, size: 14, color: Colors.white),
                            label: const Text('Save', style: TextStyle(color: Colors.white)),
                            style: TextButton.styleFrom(backgroundColor: AppTheme.primaryTeal),
                          ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: _closeImageModal,
                          icon: const Icon(Icons.close, size: 14, color: Colors.white),
                          label: const Text('Close', style: TextStyle(color: Colors.white)),
                          style: TextButton.styleFrom(backgroundColor: Colors.white24),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: Container(
                      color: const Color(0xFF020617),
                      padding: const EdgeInsets.all(16),
                      child: Image.memory(_previewImageBytes!, fit: BoxFit.contain),
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Stack(
      children: [
        SafeArea(
          child: Column(
            children: [
              // Modern Elevated Chat Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    if (widget.isMobile)
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: AppTheme.textMain),
                        onPressed: widget.onClose,
                      ),
                    Stack(
                      children: [
                        _buildDoctorAvatar(
                          widget.consultation['doctorName'] ?? '',
                          radius: 20,
                          avatarUrl: (widget.consultation['doctorAvatarUrl'] ??
                                  widget.consultation['avatarUrl'] ??
                                  widget.consultation['doctorProfileImage'] ??
                                  widget.consultation['imageUrl'])
                              ?.toString(),
                          doctorId: widget.consultation['doctorId']?.toString(),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Dr. ${widget.consultation['doctorName'] ?? 'Consulting Specialist'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppTheme.textMain,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.consultation['subject'] ?? 'Medical Consultation',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.textMuted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (widget.consultation['isUrgent'] == true)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: const Text(
                          'URGENT',
                          style: TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    _buildStatusBadge(widget.consultation['status'] as String?),
                    if (!widget.isMobile) ...[
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppTheme.textMuted),
                        onPressed: widget.onClose,
                        tooltip: 'Close Chat View',
                      ),
                    ],
                  ],
                ),
              ),
              // Message List
              Expanded(
                child: _buildMessagesList(widget.isMobile ? size.width : size.width - 320),
              ),
              // Reply Bar
              _buildReplyBar(bottomPadding: widget.isMobile ? 8 : 12),
            ],
          ),
        ),
        if (_showReviewModal) _buildReviewModalOverlay(),
        if (_previewImageBytes != null) _buildImageLightbox(),
      ],
    );
  }
}

class _FallbackDoctorName {
  final String fullName;
  _FallbackDoctorName(this.fullName);
}

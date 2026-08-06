import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../data/appointment_service.dart';
import '../data/caseroom_service.dart';
import '../data/clinical_record_service.dart';
import '../data/consultation_service.dart';

// Mirrors case-rooms.component.ts (Angular): a two-pane inbox (case room
// list + selected room's post stream) with a create-room modal, live status
// updates, per-room specialist membership, and a lightweight post composer
// that supports notes, action items and file attachments.
class DoctorCaseRoomsScreen extends ConsumerStatefulWidget {
  const DoctorCaseRoomsScreen({super.key});

  @override
  ConsumerState<DoctorCaseRoomsScreen> createState() =>
      _DoctorCaseRoomsScreenState();
}

const List<String> _priorityOptions = ['ROUTINE', 'URGENT', 'CRITICAL'];
const List<String> _statusOptions = [
  'ACTIVE',
  'PENDING_REVIEW',
  'RESOLVED',
  'ARCHIVED'
];
const List<String> _postTypeOptions = ['NOTE', 'ACTION_ITEM', 'FILE'];

class _DoctorCaseRoomsScreenState extends ConsumerState<DoctorCaseRoomsScreen> {
  final _postController = TextEditingController();
  final _postsScrollController = ScrollController();

  bool _isLoading = false;
  bool _isChatActive = false; // mobile pane toggle, mirrors Angular's flag
  List<dynamic> _caseRooms = [];
  Map<String, dynamic>? _selectedRoom;
  List<dynamic> _posts = [];
  List<dynamic> _roomMembers = [];

  List<Map<String, String>> _patientsList = [];
  List<dynamic> _doctorsList = [];
  PlatformFile? _chatFile;
  String? _downloadingFileId;
  String _postType = 'NOTE';

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadCaseRooms();
    _loadDoctorPatients();
    _loadDoctors();
  }

  @override
  void dispose() {
    _postController.dispose();
    _postsScrollController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  String _errorMessage(Object e) {
    if (e is DioException) {
      return e.response?.statusMessage ?? e.message ?? 'Network error';
    }
    return e.toString();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Data loading ─────────────────────────────────────────────────────

  Future<void> _loadCaseRooms() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref.read(caseRoomServiceProvider).searchCaseRooms({
        'page': 0,
        'size': 50,
      });
      setState(() => _caseRooms = res);
    } catch (e) {
      setState(() => _caseRooms = []);
      _toast('Failed to load case rooms: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDoctors() async {
    try {
      final userId = ref.read(authNotifierProvider).currentUser?.id;
      final userName = ref.read(authNotifierProvider).currentUser?.fullName;
      final docs = await ref.read(doctorServiceProvider).getAllDoctors();
      setState(() {
        // Exclude the current doctor from the specialist-invite list.
        _doctorsList = docs
            .where((d) =>
                !(userId != null && d.userId == userId) &&
                !(userName != null &&
                    d.fullName.toLowerCase() == userName.toLowerCase()))
            .toList();
      });
    } catch (_) {
      setState(() => _doctorsList = []);
    }
  }

  // Mirrors Angular's loadDoctorPatients(): union of patients from upcoming
  // appointments and this doctor's tele-consultations, deduped by
  // patientId. Angular calls a "my consultations" endpoint directly; this
  // app's consultation_service only exposes getConsultationsByDoctor, so we
  // resolve the doctor record for the current user first.
  Future<void> _loadDoctorPatients() async {
    final map = <String, String>{};

    void updateList() {
      if (!mounted) return;
      setState(() {
        _patientsList = map.entries
            .map((e) => {'patientId': e.key, 'patientName': e.value})
            .toList();
      });
    }

    try {
      final apps = await ref
          .read(appointmentServiceProvider)
          .getDoctorUpcomingAppointments();
      for (final a in apps) {
        if (a['patientId'] != null && a['patientName'] != null) {
          map[a['patientId']] = a['patientName'];
        }
      }
      updateList();
    } catch (_) {
      // Non-fatal — fall through to consultations.
    }

    try {
      final userId = ref.read(authNotifierProvider).currentUser?.id;
      final docs = await ref.read(doctorServiceProvider).getAllDoctors();
      final me = docs.where((d) => d.userId == userId);
      if (me.isNotEmpty) {
        final consults = await ref
            .read(consultationServiceProvider)
            .getConsultationsByDoctor(me.first.doctorId, page: 0, size: 100);
        for (final c in consults) {
          if (c['patientId'] != null && c['patientName'] != null) {
            map[c['patientId']] = c['patientName'];
          }
        }
        updateList();
      }
    } catch (_) {
      // Non-fatal — the create-room patient list just stays appointment-only.
    }
  }

  // ── Room selection / posts ──────────────────────────────────────────

  Future<void> _selectRoom(Map<String, dynamic> room) async {
    setState(() {
      _selectedRoom = room;
      _isChatActive = true;
      _roomMembers = [];
      _postType = 'NOTE';
      _chatFile = null;
      _postController.clear();
    });

    ref
        .read(caseRoomServiceProvider)
        .getMembersForRoom(room['caseRoomId'])
        .then((mems) {
      if (mounted) setState(() => _roomMembers = mems);
    }).catchError((_) {
      if (mounted) setState(() => _roomMembers = []);
    });

    await _loadPosts(room['caseRoomId']);
    _startPolling(room['caseRoomId']);
  }

  void _backToInbox() {
    setState(() => _isChatActive = false);
  }

  Future<void> _loadPosts(String roomId, {bool isPolling = false}) async {
    if (!isPolling) setState(() => _isLoading = true);
    try {
      final res = await ref
          .read(caseRoomServiceProvider)
          .getPostsForRoom(roomId, page: 0, size: 100);
      final isNewMessage = _posts.length != res.length;
      if (mounted) setState(() => _posts = res);
      if (!isPolling || isNewMessage) _scrollToBottom();
    } catch (e) {
      if (!isPolling) {
        setState(() => _posts = []);
        _toast('Failed to load posts: ${_errorMessage(e)}');
      }
      // Silent on background polling failures, same as Angular.
    } finally {
      if (!isPolling && mounted) setState(() => _isLoading = false);
    }
  }

  void _startPolling(String roomId) {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadPosts(roomId, isPolling: true);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_postsScrollController.hasClients) return;
      _postsScrollController.animateTo(
        _postsScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  // ── File attach / download ──────────────────────────────────────────

  Future<void> _pickChatFile() async {
    final result = await FilePicker.pickFiles();
    if (result != null && result.files.isNotEmpty) {
      setState(() => _chatFile = result.files.first);
    }
  }

  void _clearChatFile() {
    setState(() => _chatFile = null);
  }

  Future<void> _downloadChatFile(String fileId, String filename) async {
    if (fileId.isEmpty) return;
    setState(() => _downloadingFileId = fileId);
    try {
      final bytes =
          await ref.read(clinicalRecordServiceProvider).downloadFile(fileId);
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Save Attachment',
        fileName: filename.isNotEmpty ? filename : 'attachment',
        bytes: Uint8List.fromList(bytes),
      );
      _toast(savedPath != null
          ? 'Attachment saved to $savedPath'
          : 'Download cancelled.');
    } catch (e) {
      _toast('Failed to download attachment: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _downloadingFileId = null);
    }
  }

  // ── Posting ──────────────────────────────────────────────────────────

  Future<void> _submitPost(String postType) async {
    if (_selectedRoom == null) return;
    final text = _postController.text.trim();
    if (text.isEmpty && _chatFile == null) return;

    setState(() => _isLoading = true);
    try {
      String? fileId;
      String effectiveType = postType;
      String body = text;

      if (_chatFile != null) {
        if (_chatFile!.path == null) {
          throw Exception('Selected file has no accessible path.');
        }
        final fileMeta = await ref.read(caseRoomServiceProvider).uploadFile(
              _chatFile!.path!,
              _chatFile!.name,
              category: 'MEDICAL_RECORD',
              patientId: _selectedRoom!['patientId'],
            );
        fileId = fileMeta['fileId'];
        effectiveType = 'FILE';
        body = text.isNotEmpty ? text : _chatFile!.name;
      }

      final post = await ref.read(caseRoomServiceProvider).createPost({
        'caseRoomId': _selectedRoom!['caseRoomId'],
        'postType': effectiveType,
        'body': body,
        if (fileId != null) 'fileId': fileId,
      });

      if (mounted) {
        setState(() {
          _posts = [..._posts, post];
          _postController.clear();
          _chatFile = null;
          _postType = 'NOTE';
        });
        _scrollToBottom();
      }
    } catch (e) {
      _toast('Failed to post: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateRoomStatus(String status) async {
    if (_selectedRoom == null) return;
    setState(() => _isLoading = true);
    try {
      final updated = await ref
          .read(caseRoomServiceProvider)
          .updateStatus(_selectedRoom!['caseRoomId'], {'status': status});
      if (mounted) {
        setState(() {
          _selectedRoom = Map<String, dynamic>.from(updated);
          final idx = _caseRooms
              .indexWhere((r) => r['caseRoomId'] == updated['caseRoomId']);
          if (idx != -1) _caseRooms[idx] = updated;
        });
      }
      _toast('Status updated');
    } catch (e) {
      _toast('Failed to update status: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Create room modal ───────────────────────────────────────────────

  void _openCreateModal() {
    showDialog(
      context: context,
      builder: (_) => _CreateCaseRoomDialog(
        patientsList: _patientsList,
        doctorsList: _doctorsList,
        onSubmit: _submitCreateRoom,
      ),
    );
  }

  Future<void> _submitCreateRoom({
    required String patientId,
    required String title,
    required String description,
    required String priority,
    required List<String> doctorIds,
  }) async {
    setState(() => _isLoading = true);
    try {
      final room = await ref.read(caseRoomServiceProvider).openCaseRoom({
        'patientId': patientId,
        'title': title,
        if (description.isNotEmpty) 'description': description,
        'priority': priority,
      });

      if (doctorIds.isNotEmpty) {
        await _addCaseRoomMembers(room['caseRoomId'], doctorIds);
      } else {
        _toast('Case Room opened successfully');
      }

      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await _loadCaseRooms();
      if (mounted) _selectRoom(room);
    } catch (e) {
      _toast('Failed to open Case Room: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addCaseRoomMembers(
      String caseRoomId, List<String> doctorIds) async {
    try {
      await Future.wait(doctorIds
          .map((doctorId) => ref.read(caseRoomServiceProvider).addMember({
                'caseRoomId': caseRoomId,
                'doctorId': doctorId,
                'role': 'CONTRIBUTOR',
              })));
      _toast('Case Room opened and ${doctorIds.length} specialists invited.');
    } catch (e) {
      _toast('Case Room opened, but inviting some specialists failed.');
    }
  }

  // ── Presentation helpers ────────────────────────────────────────────

  Color _priorityColor(String? priority) {
    switch (priority) {
      case 'CRITICAL':
        return AppTheme.dangerRed;
      case 'URGENT':
        return AppTheme.warningAmber;
      default:
        return AppTheme.primaryTeal;
    }
  }

  Color _postTypeColor(String? postType) {
    switch (postType) {
      case 'ACTION_ITEM':
        return AppTheme.warningAmber;
      case 'FILE':
        return AppTheme.primaryTeal;
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

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;
    // Mobile chat view goes edge-to-edge — no wasted outer padding once a
    // room is open, since that space belongs to the post stream.
    final mobileChatOpen = !isDesktop && _isChatActive && _selectedRoom != null;

    return Scaffold(
      body: Padding(
        padding: isDesktop
            ? const EdgeInsets.all(24)
            : EdgeInsets.all(mobileChatOpen ? 0 : 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDesktop) ...[
              const Text(
                'Clinical Case Rooms',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMain),
              ),
              const SizedBox(height: 2),
              const Text(
                'Multi-specialty collaborative case discussions and clinical decision support.',
                style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: Card(
                margin: isDesktop ? null : EdgeInsets.zero,
                shape: mobileChatOpen
                    ? const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero)
                    : null,
                clipBehavior: Clip.antiAlias,
                child: isDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 320, child: _buildSidebar()),
                          const VerticalDivider(width: 1),
                          Expanded(child: _buildDetailPane(isDesktop: true)),
                        ],
                      )
                    : (_isChatActive
                        ? _buildDetailPane(isDesktop: false)
                        : _buildSidebar()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Active Cases',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('${_caseRooms.length} total',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
              ElevatedButton(
                onPressed: _openCreateModal,
                child: const Text('+ Open Case'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _isLoading && _caseRooms.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _caseRooms.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No active case rooms available.',
                            style: TextStyle(color: AppTheme.textMuted)),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _caseRooms.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final room = _caseRooms[index];
                        final isActive = _selectedRoom != null &&
                            _selectedRoom!['caseRoomId'] == room['caseRoomId'];
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          selected: isActive,
                          selectedTileColor: AppTheme.primaryLightTeal,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppTheme.primaryLightTeal,
                            child: Text(
                              (room['patientName'] as String?)?.isNotEmpty ==
                                      true
                                  ? (room['patientName'] as String)
                                      .substring(0, 1)
                                      .toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: AppTheme.primaryDarkTeal),
                            ),
                          ),
                          title: Text(
                            room['title'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Patient: ${room['patientName'] ?? ''}',
                                  style: const TextStyle(fontSize: 11)),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                        'By Dr. ${room['openedByName'] ?? ''}',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 10)),
                                  ),
                                  _priorityBadge(room['priority']),
                                ],
                              ),
                            ],
                          ),
                          trailing: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: room['status'] == 'ACTIVE'
                                  ? AppTheme.successGreen
                                  : AppTheme.textMuted,
                            ),
                          ),
                          onTap: () => _selectRoom(room),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _priorityBadge(String? priority) {
    final color = _priorityColor(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(priority ?? '',
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _postTypeBadge(String? postType) {
    final color = _postTypeColor(postType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text((postType ?? '').replaceAll('_', ' '),
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _buildDetailPane({required bool isDesktop}) {
    if (_selectedRoom == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🏥', style: TextStyle(fontSize: 40)),
              SizedBox(height: 12),
              Text('No Case Room Selected',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text(
                'Choose an active case room from the sidebar to review clinical notes and contribute to discussions.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    final room = _selectedRoom!;
    final isClosed =
        room['status'] == 'RESOLVED' || room['status'] == 'ARCHIVED';
    final myUserId = ref.watch(authNotifierProvider).currentUser?.id;
    final hasDescription = (room['description'] ?? '').toString().isNotEmpty;

    return Column(
      children: [
        // Header — kept as compact as possible (tight paddings, single-line
        // meta row, small chip strip) so the post stream below — the part
        // people actually came here for — gets the rest of the vertical
        // space instead of sitting under a tall, mostly-empty banner.
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 16 : 10, vertical: isDesktop ? 10 : 6),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.borderGray)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!isDesktop)
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back to Inbox',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(),
                      onPressed: _backToInbox,
                    ),
                  if (!isDesktop) const SizedBox(width: 6),
                  Expanded(
                    child: Text(room['title'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isDesktop ? 16 : 14)),
                  ),
                  const SizedBox(width: 8),
                  if (isDesktop)
                    _StatusUpdateControl(
                      initialStatus: room['status'],
                      isLoading: _isLoading,
                      onUpdate: _updateRoomStatus,
                    )
                  else
                    _priorityBadge(room['priority']),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'Patient: ${room['patientName'] ?? ''} • Dr. ${room['openedByName'] ?? ''}'
                '${hasDescription ? ' • ${room['description']}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
              if (_roomMembers.isNotEmpty) ...[
                const SizedBox(height: 4),
                SizedBox(
                  height: 24,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _roomMembers.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 4),
                    itemBuilder: (context, i) {
                      final m = _roomMembers[i];
                      return Chip(
                        label: Text('👨‍⚕️ ${m['doctorName'] ?? ''}',
                            style: const TextStyle(fontSize: 10)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        backgroundColor: AppTheme.primaryLightTeal,
                      );
                    },
                  ),
                ),
              ],
              if (!isDesktop) ...[
                const SizedBox(height: 6),
                _StatusUpdateControl(
                  initialStatus: room['status'],
                  isLoading: _isLoading,
                  onUpdate: _updateRoomStatus,
                ),
              ],
            ],
          ),
        ),

        // Posts — Expanded so it always absorbs whatever height the
        // (now-compact) header and footer don't use, on every screen size.
        Expanded(
          child: _isLoading && _posts.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _posts.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No posts in this case room yet. Start the collaborative discussion below!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _postsScrollController,
                      padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? 16 : 10, vertical: 10),
                      itemCount: _posts.length,
                      itemBuilder: (context, idx) {
                        final post = _posts[idx];
                        final sentByMe = post['authorId'] == myUserId;
                        return _buildPostBubble(post, sentByMe);
                      },
                    ),
        ),

        // Footer
        if (isClosed)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: AppTheme.backgroundApp,
            child: Text(
              '🔒 This Collaborative Case Room is marked as ${room['status']}. Discussion is read-only.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted),
            ),
          )
        else
          _buildComposer(isDesktop: isDesktop),
      ],
    );
  }

  Widget _buildPostBubble(dynamic post, bool sentByMe) {
    return Align(
      alignment: sentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: sentByMe ? AppTheme.primaryLightTeal : Colors.white,
          border: Border.all(color: AppTheme.borderGray),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Dr. ${post['authorName'] ?? ''}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                Text(_shortTime(post['postedAt']),
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted)),
                const SizedBox(width: 6),
                _postTypeBadge(post['postType']),
              ],
            ),
            const SizedBox(height: 4),
            Text(post['body'] ?? '', style: const TextStyle(fontSize: 13)),
            if ((post['fileId'] ?? '').toString().isNotEmpty) ...[
              const Divider(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4)),
                icon: _downloadingFileId == post['fileId']
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.attach_file, size: 16),
                label:
                    const Text('Download File', style: TextStyle(fontSize: 12)),
                onPressed: () => _downloadChatFile(
                    post['fileId'], post['body'] ?? 'attachment'),
              ),
            ],
            if (post['postType'] == 'ACTION_ITEM' &&
                (post['actionAssignedToName'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundApp,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text('👤 Assignee: Dr. ${post['actionAssignedToName']}',
                        style: const TextStyle(fontSize: 12)),
                    Text('📅 Due: ${post['actionDueDate'] ?? ''}',
                        style: const TextStyle(fontSize: 12)),
                    if ((post['actionStatus'] ?? '').toString().isNotEmpty)
                      _postTypeBadge(post['actionStatus']),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildComposer({required bool isDesktop}) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 12 : 8, vertical: isDesktop ? 12 : 8),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceWhite,
        border: Border(top: BorderSide(color: AppTheme.borderGray)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_chatFile != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('📄 staged: ${_chatFile!.name}',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textMuted),
                          overflow: TextOverflow.ellipsis),
                    ),
                    TextButton(
                      onPressed: _clearChatFile,
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              ),
            // Type selector collapses to an icon menu on mobile so the text
            // field — the thing actually being typed into — gets the width.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (isDesktop)
                  SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<String>(
                      initialValue: _postType,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textMain),
                      items: _postTypeOptions
                          .map((t) => DropdownMenuItem(
                              value: t, child: Text(t.replaceAll('_', ' '))))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _postType = val ?? 'NOTE'),
                    ),
                  )
                else
                  PopupMenuButton<String>(
                    tooltip: 'Post type: ${_postType.replaceAll('_', ' ')}',
                    padding: EdgeInsets.zero,
                    onSelected: (val) => setState(() => _postType = val),
                    itemBuilder: (context) => _postTypeOptions
                        .map((t) => PopupMenuItem(
                            value: t, child: Text(t.replaceAll('_', ' '))))
                        .toList(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _postTypeBadge(_postType),
                    ),
                  ),
                if (isDesktop) const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _postController,
                    minLines: 1,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: isDesktop
                          ? 'Share clinical notes, assign action items, or post files...'
                          : 'Write a note...',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Attach file',
                  onPressed: _pickChatFile,
                ),
                IconButton(
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  color: AppTheme.primaryTeal,
                  tooltip: 'Post',
                  onPressed: _isLoading ? null : () => _submitPost(_postType),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status update dropdown + button, kept as its own tiny stateful widget
// so choosing a status doesn't require rebuilding the whole detail pane. ──
class _StatusUpdateControl extends StatefulWidget {
  final String? initialStatus;
  final bool isLoading;
  final ValueChanged<String> onUpdate;

  const _StatusUpdateControl({
    required this.initialStatus,
    required this.isLoading,
    required this.onUpdate,
  });

  @override
  State<_StatusUpdateControl> createState() => _StatusUpdateControlState();
}

class _StatusUpdateControlState extends State<_StatusUpdateControl> {
  late String? _value = widget.initialStatus;

  @override
  void didUpdateWidget(covariant _StatusUpdateControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStatus != widget.initialStatus) {
      _value = widget.initialStatus;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _value,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              style: const TextStyle(fontSize: 11, color: AppTheme.textMain),
              items: _statusOptions
                  .map((s) => DropdownMenuItem(
                      value: s, child: Text(s.replaceAll('_', ' '))))
                  .toList(),
              onChanged: (val) => setState(() => _value = val),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: widget.isLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: 'Update status',
            onPressed: (_value == null || widget.isLoading)
                ? null
                : () => widget.onUpdate(_value!),
          ),
        ],
      ),
    );
  }
}

// ── Create Case Room modal ─────────────────────────────────────────────
class _CreateCaseRoomDialog extends StatefulWidget {
  final List<Map<String, String>> patientsList;
  final List<dynamic> doctorsList;
  final Future<void> Function({
    required String patientId,
    required String title,
    required String description,
    required String priority,
    required List<String> doctorIds,
  }) onSubmit;

  const _CreateCaseRoomDialog({
    required this.patientsList,
    required this.doctorsList,
    required this.onSubmit,
  });

  @override
  State<_CreateCaseRoomDialog> createState() => _CreateCaseRoomDialogState();
}

class _CreateCaseRoomDialogState extends State<_CreateCaseRoomDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _doctorSearchController = TextEditingController();

  String? _patientId;
  String _priority = 'ROUTINE';
  final Set<String> _selectedDoctorIds = {};
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _doctorSearchController.dispose();
    super.dispose();
  }

  List<dynamic> get _filteredDoctors {
    final term = _doctorSearchController.text.trim().toLowerCase();
    if (term.isEmpty) return widget.doctorsList;
    return widget.doctorsList
        .where((d) => (d.fullName as String).toLowerCase().contains(term))
        .toList();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        patientId: _patientId!,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        priority: _priority,
        doctorIds: _selectedDoctorIds.toList(),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('🏥 Open Collaborative Case Room',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Select Patient Case *',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<String>(
                          initialValue: _patientId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              hintText: '-- Choose Patient --'),
                          items: widget.patientsList
                              .map((p) => DropdownMenuItem(
                                  value: p['patientId'],
                                  child: Text(p['patientName'] ?? '')))
                              .toList(),
                          onChanged: (v) => setState(() => _patientId = v),
                          validator: (v) => v == null
                              ? 'Patient selection is required.'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        const Text('Case Room Title *',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _titleController,
                          maxLength: 255,
                          decoration: const InputDecoration(
                              hintText:
                                  'e.g. Consultation on unexplained chronic fatigue'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Title is required.'
                              : null,
                        ),
                        const Text('Clinical Background Description',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _descriptionController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                              hintText:
                                  'Provide preliminary case details, symptoms, and diagnostic observations...'),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Invite Specialists & Colleagues',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            if (_selectedDoctorIds.isNotEmpty)
                              Chip(
                                label: Text(
                                    '${_selectedDoctorIds.length} selected'),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _doctorSearchController,
                          decoration: const InputDecoration(
                              hintText: '🔍 Search doctors by name...'),
                          onChanged: (_) => setState(() {}),
                        ),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 160),
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.borderGray),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _filteredDoctors.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text('No specialists found.',
                                      style:
                                          TextStyle(color: AppTheme.textMuted)),
                                )
                              : ListView(
                                  shrinkWrap: true,
                                  children: _filteredDoctors
                                      .map((doc) => CheckboxListTile(
                                            dense: true,
                                            value: _selectedDoctorIds
                                                .contains(doc.doctorId),
                                            title: Text('Dr. ${doc.fullName}'),
                                            onChanged: (checked) {
                                              setState(() {
                                                if (checked == true) {
                                                  _selectedDoctorIds
                                                      .add(doc.doctorId);
                                                } else {
                                                  _selectedDoctorIds
                                                      .remove(doc.doctorId);
                                                }
                                              });
                                            },
                                          ))
                                      .toList(),
                                ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Priority Level *',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<String>(
                          initialValue: _priority,
                          isExpanded: true,
                          items: _priorityOptions
                              .map((p) =>
                                  DropdownMenuItem(value: p, child: Text(p)))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _priority = v ?? 'ROUTINE'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Open Room'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

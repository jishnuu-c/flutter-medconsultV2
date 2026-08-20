import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_notification.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../data/appointment_service.dart';
import '../data/caseroom_service.dart';
import '../data/clinical_record_service.dart';
import '../data/consultation_service.dart';

const List<String> _priorityOptions = ['ROUTINE', 'URGENT', 'CRITICAL'];
const List<String> _statusOptions = [
  'ACTIVE',
  'PENDING_REVIEW',
  'RESOLVED',
  'ARCHIVED'
];

// ══════════════════════════════════════════════════════════════════════════════
// Doctor Case Rooms Directory Screen
// ══════════════════════════════════════════════════════════════════════════════
class DoctorCaseRoomsScreen extends ConsumerStatefulWidget {
  const DoctorCaseRoomsScreen({super.key});

  @override
  ConsumerState<DoctorCaseRoomsScreen> createState() =>
      _DoctorCaseRoomsScreenState();
}

class _DoctorCaseRoomsScreenState extends ConsumerState<DoctorCaseRoomsScreen> {
  final _searchController = TextEditingController();
  String _selectedStatusFilter = 'ALL';
  String _selectedPriorityFilter = 'ALL';
  bool _isLoading = false;

  List<dynamic> _caseRooms = [];
  List<Map<String, String>> _patientsList = [];
  List<dynamic> _doctorsList = [];

  @override
  void initState() {
    super.initState();
    _loadCaseRooms();
    _loadDoctorPatients();
    _loadDoctors();
  }

  @override
  void dispose() {
    _searchController.dispose();
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

  void _snack(String msg, {bool? isError}) {
    if (!mounted) return;
    final lower = msg.toLowerCase();
    final isErr = isError ??
        (lower.contains('fail') ||
            lower.contains('error') ||
            lower.contains('could not') ||
            lower.contains('invalid') ||
            lower.contains('exception'));
    final isWarn = lower.contains('notice') ||
        lower.contains('please') ||
        lower.contains('already');
    if (isErr) {
      AppNotification.showError(context, msg);
    } else if (isWarn) {
      AppNotification.showWarning(context, msg);
    } else {
      AppNotification.showSuccess(context, msg);
    }
  }

  // ── Data Loading ─────────────────────────────────────────────────────────
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
      _snack('Failed to load case rooms: ${_errorMessage(e)}');
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
    } catch (_) {}

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
    } catch (_) {}
  }

  void _selectCaseRoom(Map<String, dynamic> room) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (ctx) => DoctorCaseRoomChatScreen(
          caseRoom: Map<String, dynamic>.from(room),
          doctorsList: _doctorsList,
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    ).then((_) {
      _loadCaseRooms();
    });
  }

  void _openCreateModal() {
    showDialog(
      context: context,
      builder: (ctx) => _CreateCaseRoomDialog(
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
        _snack('Case Room opened successfully.');
      }

      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await _loadCaseRooms();
      if (mounted) _selectCaseRoom(room);
    } catch (e) {
      _snack('Failed to open Case Room: ${_errorMessage(e)}');
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
      _snack('Case Room opened and ${doctorIds.length} specialists invited.');
    } catch (e) {
      _snack('Case Room opened, but inviting some specialists failed.');
    }
  }

  List<dynamic> get _filteredCaseRooms {
    final q = _searchController.text.trim().toLowerCase();
    return _caseRooms.where((room) {
      final status = (room['status'] ?? '').toString().toUpperCase();
      final priority = (room['priority'] ?? '').toString().toUpperCase();

      if (_selectedStatusFilter != 'ALL' && status != _selectedStatusFilter) {
        return false;
      }
      if (_selectedPriorityFilter != 'ALL' &&
          priority != _selectedPriorityFilter) {
        return false;
      }

      if (q.isNotEmpty) {
        final title = (room['title'] ?? '').toString().toLowerCase();
        final patientName =
            (room['patientName'] ?? '').toString().toLowerCase();
        final openedByName =
            (room['openedByName'] ?? '').toString().toLowerCase();
        if (!title.contains(q) &&
            !patientName.contains(q) &&
            !openedByName.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  int _countForStatus(String status) {
    if (status == 'ALL') return _caseRooms.length;
    return _caseRooms
        .where((r) => (r['status'] ?? '').toString().toUpperCase() == status)
        .length;
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

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 768;
    final filtered = _filteredCaseRooms;

    return Scaffold(
      backgroundColor: AppTheme.backgroundApp,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadCaseRooms,
          color: AppTheme.primaryTeal,
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: isMobile ? 16 : 24,
            ),
            children: [
              // 1. Sleek Compact Header
              _buildHeaderBanner(isMobile, filtered.length),
              const SizedBox(height: 12),

              // 2. Search & Filter Tabs
              _buildSearchAndFilters(),
              const SizedBox(height: 14),

              // 3. Case Rooms List
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryTeal),
                  ),
                )
              else if (filtered.isEmpty)
                _buildEmptyState()
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final room = filtered[index];
                    return _buildCaseRoomCard(room);
                  },
                ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header Section ────────────────────────────────────────────────────────
  Widget _buildHeaderBanner(bool isMobile, int activeCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Expanded(
          child: Text(
            'Specialist Case Rooms',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMain,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: _openCreateModal,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Open Case'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryTeal,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }

  // ── Search & Filter Tabs ────────────────────────────────────────────────
  Widget _buildSearchAndFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search Input
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppTheme.borderGray.withValues(alpha: 0.8)),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search by case title, patient name or doctor...',
              hintStyle:
                  const TextStyle(fontSize: 13, color: AppTheme.textMuted),
              prefixIcon: const Icon(Icons.search,
                  size: 18, color: AppTheme.textMuted),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close,
                          size: 16, color: AppTheme.textMuted),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              isDense: true,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Status Tabs Carousel
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTabPill('All', 'ALL', _countForStatus('ALL')),
              _buildTabPill('Active', 'ACTIVE', _countForStatus('ACTIVE')),
              _buildTabPill('Pending Review', 'PENDING_REVIEW',
                  _countForStatus('PENDING_REVIEW')),
              _buildTabPill('Resolved', 'RESOLVED', _countForStatus('RESOLVED')),
              _buildTabPill('Archived', 'ARCHIVED', _countForStatus('ARCHIVED')),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Priority Filter Carousel
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildPriorityPill('All Priority', 'ALL'),
              _buildPriorityPill('Critical', 'CRITICAL'),
              _buildPriorityPill('Urgent', 'URGENT'),
              _buildPriorityPill('Routine', 'ROUTINE'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriorityPill(String label, String value) {
    final isSelected = _selectedPriorityFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() => _selectedPriorityFilter = value),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? (value == 'CRITICAL'
                    ? const Color(0xFFFEE2E2)
                    : (value == 'URGENT'
                        ? const Color(0xFFFEF3C7)
                        : (value == 'ROUTINE'
                            ? const Color(0xFFE0F2FE)
                            : const Color(0xFFE2E8F0))))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? (value == 'CRITICAL'
                      ? const Color(0xFFDC2626)
                      : (value == 'URGENT'
                          ? const Color(0xFFD97706)
                          : (value == 'ROUTINE'
                              ? const Color(0xFF0284C7)
                              : const Color(0xFF94A3B8))))
                  : const Color(0xFFCBD5E1).withValues(alpha: 0.6),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? (value == 'CRITICAL'
                      ? const Color(0xFFDC2626)
                      : (value == 'URGENT'
                          ? const Color(0xFFD97706)
                          : (value == 'ROUTINE'
                              ? const Color(0xFF0284C7)
                              : const Color(0xFF334155))))
                  : AppTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabPill(String label, String value, int count) {
    final isSelected = _selectedStatusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => setState(() => _selectedStatusFilter = value),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryTeal : AppTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? AppTheme.primaryTeal
                  : AppTheme.borderGray.withValues(alpha: 0.8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : AppTheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Empty State ─────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(36),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppTheme.borderGray.withValues(alpha: 0.7)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9), shape: BoxShape.circle),
            child: const Icon(Icons.meeting_room_outlined,
                size: 28, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 10),
          const Text('No Case Rooms Found',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          const Text(
            'No collaborative case rooms match your current search or filter query. Click "+ Open Case" to start a new multidisciplinary case.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Case Room Card ──────────────────────────────────────────────────────
  Widget _buildCaseRoomCard(Map<String, dynamic> room) {
    final status = (room['status'] ?? 'ACTIVE').toString().toUpperCase();
    final priority = (room['priority'] ?? 'ROUTINE').toString().toUpperCase();
    final patientName = (room['patientName'] ?? 'Unknown Patient').toString();
    final openedByName = (room['openedByName'] ?? 'Doctor').toString();
    final rawAvatarUrl = (room['patientAvatarUrl'] ??
            room['patientAvatar'] ??
            room['avatarUrl'] ??
            '')
        .toString();
    final avatarUrl = rawAvatarUrl.isNotEmpty
        ? (rawAvatarUrl.startsWith('http')
            ? rawAvatarUrl
            : '$kBaseUrl${rawAvatarUrl.startsWith('/') ? '' : '/'}$rawAvatarUrl')
        : '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: priority == 'CRITICAL'
              ? AppTheme.dangerRed.withValues(alpha: 0.35)
              : (priority == 'URGENT'
                  ? AppTheme.warningAmber.withValues(alpha: 0.35)
                  : AppTheme.borderGray.withValues(alpha: 0.7)),
          width: priority == 'CRITICAL' ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _selectCaseRoom(room),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Patient Avatar
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFFCCFBF1),
                      backgroundImage: avatarUrl.isNotEmpty
                          ? NetworkImage(avatarUrl)
                          : null,
                      onBackgroundImageError:
                          avatarUrl.isNotEmpty ? (_, __) {} : null,
                      child: avatarUrl.isEmpty
                          ? Text(
                              patientName.isNotEmpty
                                  ? patientName[0].toUpperCase()
                                  : 'P',
                              style: const TextStyle(
                                color: Color(0xFF0F766E),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: status == 'ACTIVE'
                              ? const Color(0xFF22C55E)
                              : (status == 'PENDING_REVIEW'
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF94A3B8)),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              room['title'] ?? 'Clinical Case Discussion',
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textMain,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _priorityBadge(priority),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.person_outline_rounded,
                              size: 13, color: AppTheme.textMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Patient: $patientName',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.medical_services_outlined,
                              size: 12, color: AppTheme.textMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Dr. ${openedByName.startsWith('Dr') ? openedByName.replaceFirst('Dr.', '').trim() : openedByName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.textMuted),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _mediumDate(room['createdAt']),
                            style: const TextStyle(
                                fontSize: 10.5, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Status & Chevron
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _statusPill(status),
                    const SizedBox(height: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.textMuted,
                      size: 18,
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

  Widget _priorityBadge(String priority) {
    Color bg;
    Color fg;
    switch (priority) {
      case 'CRITICAL':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFDC2626);
        break;
      case 'URGENT':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        break;
      default:
        bg = const Color(0xFFE0F2FE);
        fg = const Color(0xFF0284C7);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        priority,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _statusPill(String status) {
    Color bg;
    Color fg;
    switch (status) {
      case 'ACTIVE':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF166534);
        break;
      case 'PENDING_REVIEW':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFF92400E);
        break;
      case 'RESOLVED':
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF475569);
        break;
      default:
        bg = const Color(0xFFE2E8F0);
        fg = const Color(0xFF334155);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Dedicated Doctor Case Room Discussion Screen (Full Screen View)
// ══════════════════════════════════════════════════════════════════════════════
class DoctorCaseRoomChatScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> caseRoom;
  final List<dynamic> doctorsList;
  final VoidCallback? onClose;

  const DoctorCaseRoomChatScreen({
    super.key,
    required this.caseRoom,
    required this.doctorsList,
    this.onClose,
  });

  @override
  ConsumerState<DoctorCaseRoomChatScreen> createState() =>
      _DoctorCaseRoomChatScreenState();
}

class _DoctorCaseRoomChatScreenState
    extends ConsumerState<DoctorCaseRoomChatScreen> {
  late Map<String, dynamic> _selectedRoom;
  final _postController = TextEditingController();
  final _postsScrollController = ScrollController();
  bool _isLoading = false;
  List<dynamic> _posts = [];
  List<dynamic> _roomMembers = [];

  String _postType = 'NOTE'; // NOTE, ACTION_ITEM, FILE
  String? _actionAssignedTo;
  DateTime? _actionDueDate;
  PlatformFile? _chatFile;
  Timer? _pollTimer;
  bool _isDescriptionExpanded = false;

  @override
  void initState() {
    super.initState();
    _selectedRoom = widget.caseRoom;
    _loadPosts(showSpinner: true);
    _loadMembers();

    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _loadPosts(showSpinner: false);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _postController.dispose();
    _postsScrollController.dispose();
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

  void _snack(String msg, {bool? isError}) {
    if (!mounted) return;
    final lower = msg.toLowerCase();
    final isErr = isError ??
        (lower.contains('fail') ||
            lower.contains('error') ||
            lower.contains('could not') ||
            lower.contains('invalid') ||
            lower.contains('exception'));
    final isWarn = lower.contains('notice') ||
        lower.contains('please') ||
        lower.contains('already');
    if (isErr) {
      AppNotification.showError(context, msg);
    } else if (isWarn) {
      AppNotification.showWarning(context, msg);
    } else {
      AppNotification.showSuccess(context, msg);
    }
  }

  Future<void> _loadPosts({required bool showSpinner}) async {
    if (showSpinner && mounted) setState(() => _isLoading = true);
    try {
      final res = await ref.read(caseRoomServiceProvider).getPostsForRoom(
            _selectedRoom['caseRoomId'],
            page: 0,
            size: 100,
          );
      final changed = _posts.length != res.length;
      if (mounted) {
        setState(() {
          _posts = res;
          _isLoading = false;
        });
      }
      if (changed) _scrollToBottom();
    } catch (e) {
      if (showSpinner && mounted) {
        setState(() {
          _posts = [];
          _isLoading = false;
        });
        _snack('Failed to load discussion posts: ${_errorMessage(e)}');
      }
    } finally {
      if (showSpinner && mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMembers() async {
    try {
      final mems = await ref
          .read(caseRoomServiceProvider)
          .getMembersForRoom(_selectedRoom['caseRoomId']);
      if (mounted) setState(() => _roomMembers = mems);
    } catch (_) {
      if (mounted) setState(() => _roomMembers = []);
    }
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

  Future<void> _pickChatFile() async {
    final result = await FilePicker.pickFiles(withData: true);
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _chatFile = result.files.first;
        _postType = 'FILE';
      });
    }
  }

  void _clearChatFile() {
    setState(() {
      _chatFile = null;
      if (_postType == 'FILE') _postType = 'NOTE';
    });
  }

  Future<void> _submitPost() async {
    final text = _postController.text.trim();
    if (text.isEmpty && _chatFile == null) return;

    setState(() => _isLoading = true);
    try {
      String? fileId;
      String effectiveType = _postType;
      String body = text;

      if (_chatFile != null) {
        final fileMeta = await ref.read(caseRoomServiceProvider).uploadFile(
              filePath: _chatFile!.path,
              bytes: _chatFile!.bytes,
              fileName: _chatFile!.name,
              category: 'MEDICAL_RECORD',
              patientId: _selectedRoom['patientId'],
            );
        fileId = fileMeta['fileId']?.toString();
        effectiveType = 'FILE';
        body = text.isNotEmpty ? text : _chatFile!.name;
      }

      final payload = <String, dynamic>{
        'caseRoomId': _selectedRoom['caseRoomId'],
        'postType': effectiveType,
        'body': body,
        if (fileId != null) 'fileId': fileId,
        if (effectiveType == 'ACTION_ITEM' && _actionAssignedTo != null)
          'actionAssignedTo': _actionAssignedTo,
        if (effectiveType == 'ACTION_ITEM' && _actionDueDate != null)
          'actionDueDate':
              '${_actionDueDate!.year.toString().padLeft(4, '0')}-${_actionDueDate!.month.toString().padLeft(2, '0')}-${_actionDueDate!.day.toString().padLeft(2, '0')}',
      };

      final post = await ref.read(caseRoomServiceProvider).createPost(payload);

      if (mounted) {
        setState(() {
          _posts = [..._posts, post];
          _postController.clear();
          _chatFile = null;
          _postType = 'NOTE';
          _actionAssignedTo = null;
          _actionDueDate = null;
        });
        _scrollToBottom();
      }
    } catch (e) {
      _snack('Failed to post message: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateRoomStatus(String status) async {
    setState(() => _isLoading = true);
    try {
      final updated = await ref
          .read(caseRoomServiceProvider)
          .updateStatus(_selectedRoom['caseRoomId'], {'status': status});
      _snack('Case room status updated.');
      if (mounted) {
        setState(() {
          _selectedRoom = Map<String, dynamic>.from(updated);
        });
      }
    } catch (e) {
      _snack('Failed to update status: ${_errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleActionStatus(Map<String, dynamic> post) async {
    final current = (post['actionStatus'] ?? 'PENDING').toString().toUpperCase();
    final newStatus = current == 'PENDING' ? 'DONE' : 'PENDING';
    try {
      final updated = await ref
          .read(caseRoomServiceProvider)
          .updatePostActionStatus(post['postId'], {'actionStatus': newStatus});
      if (mounted) {
        setState(() {
          final idx = _posts.indexWhere((p) => p['postId'] == post['postId']);
          if (idx != -1) _posts[idx] = updated;
        });
        _snack('Action item marked as $newStatus.');
      }
    } catch (e) {
      _snack('Failed to update action status: ${_errorMessage(e)}');
    }
  }

  void _openInviteSpecialistModal() {
    showDialog(
      context: context,
      builder: (ctx) => _InviteSpecialistDialog(
        doctorsList: widget.doctorsList,
        existingMemberDoctorIds:
            _roomMembers.map((m) => m['doctorId']?.toString() ?? '').toList(),
        onInvite: (doctorId) async {
          try {
            await ref.read(caseRoomServiceProvider).addMember({
              'caseRoomId': _selectedRoom['caseRoomId'],
              'doctorId': doctorId,
              'role': 'CONTRIBUTOR',
            });
            _snack('Specialist added to case room.');
            _loadMembers();
          } catch (e) {
            _snack('Failed to add specialist: ${_errorMessage(e)}');
          }
        },
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final room = _selectedRoom;
    final isClosed =
        room['status'] == 'RESOLVED' || room['status'] == 'ARCHIVED';
    final currentUserId = ref.read(authNotifierProvider).currentUser?.id;

    final patientName = (room['patientName'] ?? 'Patient').toString();
    final rawAvatarUrl = (room['patientAvatarUrl'] ??
            room['patientAvatar'] ??
            room['avatarUrl'] ??
            '')
        .toString();
    final patientAvatarUrl = rawAvatarUrl.isNotEmpty
        ? (rawAvatarUrl.startsWith('http')
            ? rawAvatarUrl
            : '$kBaseUrl${rawAvatarUrl.startsWith('/') ? '' : '/'}$rawAvatarUrl')
        : '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textMain),
          onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFCCFBF1),
              backgroundImage: patientAvatarUrl.isNotEmpty
                  ? NetworkImage(patientAvatarUrl)
                  : null,
              onBackgroundImageError:
                  patientAvatarUrl.isNotEmpty ? (_, __) {} : null,
              child: patientAvatarUrl.isEmpty
                  ? Text(
                      patientName.isNotEmpty ? patientName[0].toUpperCase() : 'P',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F766E),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room['title'] ?? 'Clinical Case Discussion',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMain,
                    ),
                  ),
                  Text(
                    'Patient: $patientName • By Dr. ${room['openedByName'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Status Dropdown
          PopupMenuButton<String>(
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (room['status'] ?? 'ACTIVE').toString().replaceAll('_', ' '),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_drop_down,
                      size: 14, color: Color(0xFF0F766E)),
                ],
              ),
            ),
            onSelected: _updateRoomStatus,
            itemBuilder: (ctx) => _statusOptions
                .map((s) => PopupMenuItem(
                      value: s,
                      child: Text(s.replaceAll('_', ' '),
                          style: const TextStyle(fontSize: 12)),
                    ))
                .toList(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Specialists Bar & Description
            _buildSpecialistsAndDescriptionHeader(),

            // Discussion Posts List
            Expanded(
              child: _buildPostsList(
                  currentUserId, MediaQuery.of(context).size.width),
            ),

            // Composer
            if (isClosed)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 16, color: AppTheme.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      'Case Room is marked as ${room['status']}. Discussion is read-only.',
                      style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              )
            else
              _buildPostComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialistsAndDescriptionHeader() {
    final desc = (_selectedRoom['description'] ?? '').toString();

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Specialists Row
          Row(
            children: [
              const Text(
                'Case Specialists:',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ..._roomMembers.map((m) {
                        return Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('👨‍⚕️', style: TextStyle(fontSize: 11)),
                              const SizedBox(width: 4),
                              Text(
                                m['doctorName'] ?? 'Doctor',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      InkWell(
                        onTap: _openInviteSpecialistModal,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFCCFBF1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: const Color(0xFF14B8A6).withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_add_alt_1_outlined,
                                  size: 12, color: Color(0xFF0F766E)),
                              SizedBox(width: 4),
                              Text(
                                'Invite',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Description Snippet
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () =>
                  setState(() => _isDescriptionExpanded = !_isDescriptionExpanded),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📝', style: TextStyle(fontSize: 11)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        desc,
                        maxLines: _isDescriptionExpanded ? 10 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: Color(0xFF475569)),
                      ),
                    ),
                    Icon(
                      _isDescriptionExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 14,
                      color: AppTheme.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPostsList(String? currentUserId, double maxWidth) {
    if (_isLoading && _posts.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryTeal),
      );
    }
    if (_posts.isEmpty) {
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
                child: const Icon(Icons.meeting_room_outlined,
                    size: 28, color: Color(0xFF0F766E)),
              ),
              const SizedBox(height: 12),
              const Text(
                'No discussion posts yet',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Share clinical observations, assign action items, or upload files to begin the case discussion.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _postsScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        final post = _posts[index];
        final isMine = post['authorId'] == currentUserId;
        return _buildPostCard(post, isMine, maxWidth);
      },
    );
  }

  Widget _buildPostCard(
      Map<String, dynamic> post, bool isMine, double maxWidth) {
    final type = (post['postType'] ?? 'NOTE').toString().toUpperCase();
    final authorName = (post['authorName'] ?? 'Doctor').toString();
    final authorAvatar = (post['authorAvatarUrl'] ?? '').toString();
    final fileId = post['fileId']?.toString();
    final isActionItem = type == 'ACTION_ITEM';

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth * 0.82),
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Author Meta
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 9,
                    backgroundColor: const Color(0xFFCCFBF1),
                    backgroundImage: authorAvatar.isNotEmpty
                        ? NetworkImage(authorAvatar.startsWith('http')
                            ? authorAvatar
                            : '$kBaseUrl$authorAvatar')
                        : null,
                    child: authorAvatar.isEmpty
                        ? Text(
                            authorName.isNotEmpty
                                ? authorName[0].toUpperCase()
                                : 'D',
                            style: const TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F766E)),
                          )
                        : null,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Dr. $authorName',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '• ${_shortTime(post['postedAt'])}',
                    style: const TextStyle(
                        fontSize: 10, color: AppTheme.textMuted),
                  ),
                  const SizedBox(width: 6),
                  _postTypeBadge(type),
                ],
              ),
            ),

            // Card Bubble
            Container(
              padding: const EdgeInsets.all(12),
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
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomRight: Radius.circular(isMine ? 3 : 16),
                  bottomLeft: Radius.circular(isMine ? 16 : 3),
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
                  // Text Content
                  if ((post['body'] ?? '').toString().isNotEmpty)
                    Text(
                      post['body'] ?? '',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: isMine ? Colors.white : const Color(0xFF1E293B),
                        height: 1.35,
                      ),
                    ),

                  // Action Item Details Box
                  if (isActionItem) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isMine
                            ? Colors.white.withValues(alpha: 0.15)
                            : const Color(0xFFFEF3C7).withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isMine
                              ? Colors.white.withValues(alpha: 0.25)
                              : const Color(0xFFFDE68A),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (post['actionAssignedToName'] != null)
                                  Text(
                                    '👤 Assignee: Dr. ${post['actionAssignedToName']}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: isMine
                                          ? Colors.white
                                          : const Color(0xFF92400E),
                                    ),
                                  ),
                                if (post['actionDueDate'] != null)
                                  Text(
                                    '📅 Due: ${post['actionDueDate']}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isMine
                                          ? Colors.white.withValues(alpha: 0.85)
                                          : const Color(0xFFB45309),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () => _toggleActionStatus(post),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: (post['actionStatus'] ?? 'PENDING') ==
                                        'DONE'
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFFF59E0B),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    (post['actionStatus'] ?? 'PENDING') == 'DONE'
                                        ? Icons.check_circle_rounded
                                        : Icons.pending_actions_rounded,
                                    size: 13,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    (post['actionStatus'] ?? 'PENDING')
                                        .toString(),
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
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

                  // File Attachment Box
                  if (fileId != null && fileId.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildFileAttachmentCard(post, isMine, fileId),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileAttachmentCard(
      Map<String, dynamic> post, bool isMine, String fileId) {
    final isImg = _isImage(post['body']?.toString() ?? '');
    return Container(
      decoration: BoxDecoration(
        color: isMine
            ? Colors.black.withValues(alpha: 0.18)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMine
              ? Colors.white.withValues(alpha: 0.25)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (isImg) {
              _openImageLightbox(
                url: '$kBaseUrl/api/medconsult/files/$fileId/download',
                title: post['body'] ?? 'Attachment',
                fileId: fileId,
              );
            } else {
              _downloadChatFile(fileId, post['body'] ?? 'attachment');
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isImg ? Icons.image_rounded : Icons.insert_drive_file_rounded,
                  size: 20,
                  color: isMine ? Colors.white : const Color(0xFF0F766E),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post['body'] ?? 'Attachment',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isMine ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        isImg ? 'Click to preview' : 'Click to download',
                        style: TextStyle(
                          fontSize: 10,
                          color: isMine
                              ? Colors.white.withValues(alpha: 0.75)
                              : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isImg ? Icons.zoom_in : Icons.download_rounded,
                  size: 16,
                  color: isMine
                      ? Colors.white.withValues(alpha: 0.85)
                      : const Color(0xFF0F766E),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isImage(String filename) {
    return RegExp(r'\.(png|jpe?g|gif|webp|bmp)$', caseSensitive: false)
        .hasMatch(filename);
  }

  void _openImageLightbox({
    required String url,
    required String title,
    required String fileId,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _ImageLightboxDialog(
        url: url,
        title: title,
        onDownload: () => _downloadChatFile(fileId, title),
      ),
    );
  }

  Future<void> _downloadChatFile(String fileId, String filename) async {
    try {
      final bytes =
          await ref.read(clinicalRecordServiceProvider).downloadFile(fileId);
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Save Attachment',
        fileName: filename.isNotEmpty ? filename : 'attachment',
        bytes: Uint8List.fromList(bytes),
      );
      if (savedPath != null) {
        _snack('Attachment saved to $savedPath.');
      }
    } catch (e) {
      _snack('Failed to download attachment: ${_errorMessage(e)}');
    }
  }

  Widget _postTypeBadge(String type) {
    Color bg;
    Color fg;
    switch (type) {
      case 'ACTION_ITEM':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        break;
      case 'FILE':
        bg = const Color(0xFFCCFBF1);
        fg = const Color(0xFF0F766E);
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF64748B);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }

  // ── Composer ─────────────────────────────────────────────────────────────
  Widget _buildPostComposer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        children: [
          // Staged File Chip
          if (_chatFile != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.attach_file_rounded,
                      size: 16, color: Color(0xFF0F766E)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _chatFile!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: _clearChatFile,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ],

          // Post Type Selector
          Row(
            children: [
              _buildTypePill('NOTE', 'Note', Icons.chat_bubble_outline),
              const SizedBox(width: 6),
              _buildTypePill(
                  'ACTION_ITEM', 'Action Item', Icons.task_alt_outlined),
              const SizedBox(width: 6),
              _buildTypePill('FILE', 'File', Icons.attachment_outlined),
            ],
          ),
          const SizedBox(height: 8),

          // Action Item Inline Config
          if (_postType == 'ACTION_ITEM') ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7).withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _actionAssignedTo,
                      decoration: const InputDecoration(
                        labelText: 'Assign Specialist',
                        labelStyle: TextStyle(fontSize: 11),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textMain),
                      items: widget.doctorsList
                          .map((d) => DropdownMenuItem<String>(
                                value: d.doctorId,
                                child: Text('Dr. ${d.fullName}'),
                              ))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _actionAssignedTo = val),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _actionDueDate ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => _actionDueDate = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_today, size: 14),
                    label: Text(
                      _actionDueDate == null
                          ? 'Due Date'
                          : '${_actionDueDate!.month}/${_actionDueDate!.day}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Text Field & Actions
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file,
                    color: Color(0xFF0F766E), size: 20),
                onPressed: _pickChatFile,
                tooltip: 'Attach File or Image',
              ),
              Expanded(
                child: TextField(
                  controller: _postController,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: _postType == 'ACTION_ITEM'
                        ? 'Describe action task...'
                        : 'Share clinical notes with specialists...',
                    hintStyle: const TextStyle(
                        fontSize: 13, color: AppTheme.textMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18),
                  onPressed: _submitPost,
                  tooltip: 'Post',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypePill(String type, String label, IconData icon) {
    final isSelected = _postType == type;
    return InkWell(
      onTap: () {
        if (type == 'FILE' && _chatFile == null) {
          _pickChatFile();
        } else {
          setState(() => _postType = type);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F766E) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isSelected ? const Color(0xFF0F766E) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 12,
                color: isSelected ? Colors.white : const Color(0xFF64748B)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Open Collaborative Case Room Dialog
// ══════════════════════════════════════════════════════════════════════════════
class _CreateCaseRoomDialog extends StatefulWidget {
  final List<Map<String, String>> patientsList;
  final List<dynamic> doctorsList;
  final Function({
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
  final _descController = TextEditingController();
  final _doctorSearchController = TextEditingController();

  String? _selectedPatientId;
  String _selectedPriority = 'ROUTINE';
  final Set<String> _selectedDoctorIds = {};

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _doctorSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _doctorSearchController.text.trim().toLowerCase();
    final filteredDoctors = widget.doctorsList.where((d) {
      if (query.isEmpty) return true;
      final name = d.fullName.toString().toLowerCase();
      final spec = (d.specialization ?? '').toString().toLowerCase();
      return name.contains(query) || spec.contains(query);
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 650),
        padding: const EdgeInsets.all(22),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.meeting_room_outlined,
                          color: Color(0xFF0F766E), size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Open Collaborative Case Room',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMain,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),

              Expanded(
                child: ListView(
                  children: [
                    // Patient Selection
                    const Text('Select Patient Case *',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedPatientId,
                      decoration: InputDecoration(
                        hintText: '-- Choose Patient --',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      validator: (v) =>
                          v == null ? 'Patient selection is required' : null,
                      items: widget.patientsList
                          .map((p) => DropdownMenuItem(
                                value: p['patientId'],
                                child: Text(p['patientName'] ?? ''),
                              ))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedPatientId = val),
                    ),
                    const SizedBox(height: 14),

                    // Case Title
                    const Text('Case Room Title *',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        hintText:
                            'e.g. Consultation on unexplained chronic fatigue',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Title is required'
                          : null,
                    ),
                    const SizedBox(height: 14),

                    // Description
                    const Text('Clinical Background Description',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _descController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText:
                            'Provide preliminary case details, symptoms, and diagnostic observations...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Priority Selector
                    const Text('Priority Level *',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: _priorityOptions.map((p) {
                        final isSel = _selectedPriority == p;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () => setState(() => _selectedPriority = p),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSel
                                      ? (p == 'CRITICAL'
                                          ? const Color(0xFFDC2626)
                                          : (p == 'URGENT'
                                              ? const Color(0xFFD97706)
                                              : const Color(0xFF0F766E)))
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  p,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isSel
                                        ? Colors.white
                                        : const Color(0xFF475569),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    // Specialist Invite Multi-select
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Invite Specialists & Colleagues',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.bold)),
                        if (_selectedDoctorIds.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFCCFBF1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_selectedDoctorIds.length} selected',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    TextField(
                      controller: _doctorSearchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: '🔍 Search doctors by name...',
                        hintStyle: const TextStyle(fontSize: 12),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 6),

                    Container(
                      height: 140,
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: filteredDoctors.isEmpty
                          ? const Center(
                              child: Text('No specialists found.',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textMuted)),
                            )
                          : ListView.builder(
                              itemCount: filteredDoctors.length,
                              itemBuilder: (context, index) {
                                final doc = filteredDoctors[index];
                                final isChecked =
                                    _selectedDoctorIds.contains(doc.doctorId);
                                return CheckboxListTile(
                                  dense: true,
                                  value: isChecked,
                                  title: Text('Dr. ${doc.fullName}',
                                      style: const TextStyle(fontSize: 12)),
                                  subtitle: doc.specialization != null
                                      ? Text(doc.specialization!,
                                          style: const TextStyle(fontSize: 10))
                                      : null,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedDoctorIds.add(doc.doctorId);
                                      } else {
                                        _selectedDoctorIds.remove(doc.doctorId);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      if (_formKey.currentState?.validate() ?? false) {
                        widget.onSubmit(
                          patientId: _selectedPatientId!,
                          title: _titleController.text.trim(),
                          description: _descController.text.trim(),
                          priority: _selectedPriority,
                          doctorIds: _selectedDoctorIds.toList(),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Open Room'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Invite Specialist Dialog
// ══════════════════════════════════════════════════════════════════════════════
class _InviteSpecialistDialog extends StatefulWidget {
  final List<dynamic> doctorsList;
  final List<String> existingMemberDoctorIds;
  final Function(String doctorId) onInvite;

  const _InviteSpecialistDialog({
    required this.doctorsList,
    required this.existingMemberDoctorIds,
    required this.onInvite,
  });

  @override
  State<_InviteSpecialistDialog> createState() =>
      _InviteSpecialistDialogState();
}

class _InviteSpecialistDialogState extends State<_InviteSpecialistDialog> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final availableDoctors = widget.doctorsList.where((d) {
      if (widget.existingMemberDoctorIds.contains(d.doctorId)) return false;
      if (query.isEmpty) return true;
      final name = d.fullName.toString().toLowerCase();
      final spec = (d.specialization ?? '').toString().toLowerCase();
      return name.contains(query) || spec.contains(query);
    }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Invite Specialist to Case Room',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search by doctor name or specialty...',
                prefixIcon: const Icon(Icons.search, size: 16),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: availableDoctors.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No additional specialists available.',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: availableDoctors.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, idx) {
                        final doc = availableDoctors[idx];
                        return ListTile(
                          dense: true,
                          leading: const CircleAvatar(
                            radius: 16,
                            backgroundColor: Color(0xFFCCFBF1),
                            child: Icon(Icons.medical_services_outlined,
                                size: 14, color: Color(0xFF0F766E)),
                          ),
                          title: Text('Dr. ${doc.fullName}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: doc.specialization != null
                              ? Text(doc.specialization!,
                                  style: const TextStyle(fontSize: 11))
                              : null,
                          trailing: ElevatedButton(
                            onPressed: () {
                              widget.onInvite(doc.doctorId);
                              Navigator.of(context).pop();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              textStyle: const TextStyle(fontSize: 11),
                            ),
                            child: const Text('Invite'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Full Image Lightbox Dialog
// ══════════════════════════════════════════════════════════════════════════════
class _ImageLightboxDialog extends StatelessWidget {
  final String url;
  final String title;
  final VoidCallback onDownload;

  const _ImageLightboxDialog({
    required this.url,
    required this.title,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFF1E293B),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download, size: 14),
                    label: const Text('Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Image
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(16),
                color: const Color(0xFF020617),
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text('Failed to load image preview.',
                          style: TextStyle(color: Colors.white70)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

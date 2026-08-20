import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/appointment_service.dart';

class DoctorScheduleScreen extends ConsumerStatefulWidget {
  const DoctorScheduleScreen({super.key});

  @override
  ConsumerState<DoctorScheduleScreen> createState() =>
      _DoctorScheduleScreenState();
}

class _DoctorScheduleScreenState extends ConsumerState<DoctorScheduleScreen> {
  bool _isLoading = false;
  List<dynamic> _appointments = [];
  String _selectedStatusFilter = 'ALL';
  String _searchQuery = '';
  String _selectedModeFilter = 'ALL';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSchedule() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref
          .read(appointmentServiceProvider)
          .getDoctorUpcomingAppointments();
      setState(() => _appointments = res);
    } catch (e) {
      setState(() => _appointments = []);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Failed to load schedule'),
            content: SingleChildScrollView(
              child: SelectableText(_errorMessage(e)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _errorMessage(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      String? detail = e.response?.statusMessage;
      if (detail == null || detail.trim().isEmpty) detail = e.message;
      if (detail == null || detail.trim().isEmpty) {
        detail = e.type.toString().replaceFirst('DioExceptionType.', '');
      }
      return status != null ? '[$status] $detail' : detail;
    }
    final s = e.toString();
    return s.trim().isEmpty ? 'Unknown error' : s;
  }

  Future<void> _changeStatus(String appointmentId, String newStatus) async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(appointmentServiceProvider)
          .updateStatus(appointmentId, {'status': newStatus});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Appointment updated to $newStatus successfully'),
              ],
            ),
            backgroundColor: newStatus == 'NO_SHOW'
                ? AppTheme.dangerRed
                : const Color(0xFF0F766E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      await _loadSchedule();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: ${_errorMessage(e)}'),
            backgroundColor: AppTheme.dangerRed,
          ),
        );
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _mediumDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final d = DateTime.parse(raw);
      return '${_months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return raw;
    }
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'CONFIRMED':
        return const Color(0xFF0F766E);
      case 'COMPLETED':
        return const Color(0xFF16A34A);
      case 'SCHEDULED':
        return const Color(0xFFD97706);
      case 'CANCELLED':
      case 'NO_SHOW':
        return const Color(0xFFDC2626);
      default:
        return AppTheme.textMuted;
    }
  }

  List<dynamic> get _filteredAppointments {
    return _appointments.where((apt) {
      final status = (apt['status'] ?? 'SCHEDULED').toString().toUpperCase();
      final sessionType = (apt['sessionType'] ?? '').toString().toUpperCase();
      final patientName = (apt['patientName'] ?? '').toString().toLowerCase();

      final matchesStatus = _selectedStatusFilter == 'ALL' ||
          (_selectedStatusFilter == 'CONFIRMED' && status == 'CONFIRMED') ||
          (_selectedStatusFilter == 'SCHEDULED' && status == 'SCHEDULED') ||
          (_selectedStatusFilter == 'COMPLETED' && status == 'COMPLETED') ||
          (_selectedStatusFilter == 'OTHER' && (status == 'CANCELLED' || status == 'NO_SHOW'));

      final matchesMode = _selectedModeFilter == 'ALL' ||
          (_selectedModeFilter == 'IN_CLINIC' && sessionType == 'IN_CLINIC') ||
          (_selectedModeFilter == 'VIDEO_CALL' && sessionType != 'IN_CLINIC');

      final matchesSearch = _searchQuery.isEmpty ||
          patientName.contains(_searchQuery.toLowerCase());

      return matchesStatus && matchesMode && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    final totalCount = _appointments.length;
    final scheduledCount = _appointments.where((a) => a['status'] == 'SCHEDULED').length;
    final confirmedCount = _appointments.where((a) => a['status'] == 'CONFIRMED').length;
    final completedCount = _appointments.where((a) => a['status'] == 'COMPLETED').length;

    return Scaffold(
      backgroundColor: AppTheme.backgroundApp,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryTeal),
            )
          : RefreshIndicator(
              onRefresh: _loadSchedule,
              color: AppTheme.primaryTeal,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(isMobile ? 14 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 1. Hero Header Banner with Live Stats ──────────────────
                    _buildHeaderBanner(isMobile, totalCount, scheduledCount, confirmedCount, completedCount),
                    const SizedBox(height: 18),

                    // ── 2. Filter Strip & Search Tray ─────────────────────────
                    _buildFilterAndSearchControls(isMobile, totalCount, scheduledCount, confirmedCount, completedCount),
                    const SizedBox(height: 18),

                    // ── 3. Consultation Timeline Cards List ───────────────────
                    if (_filteredAppointments.isEmpty)
                      _buildEmptyState()
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _filteredAppointments.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final apt = _filteredAppointments[i];
                          return _buildTimelineCard(apt, isMobile, i);
                        },
                      ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // HERO HEADER BANNER
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHeaderBanner(
    bool isMobile,
    int total,
    int scheduled,
    int confirmed,
    int completed,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF042F2E), Color(0xFF0F766E), Color(0xFF14B8A6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 12, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'CLINICAL OPERATIONS',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Consultation Schedule',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Live timeline of scheduled patient appointments for today',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loadSchedule,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                tooltip: 'Refresh Schedule',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // 4-Card KPI Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                _buildKpiCard('TOTAL TODAY', '$total', Icons.people_alt_outlined),
                _buildHeroDivider(),
                _buildKpiCard('NEEDS CONFIRM', '$scheduled', Icons.pending_actions_outlined,
                    highlightColor: const Color(0xFFFDE68A)),
                _buildHeroDivider(),
                _buildKpiCard('CONFIRMED', '$confirmed', Icons.verified_outlined,
                    highlightColor: const Color(0xFF86EFAC)),
                _buildHeroDivider(),
                _buildKpiCard('COMPLETED', '$completed', Icons.task_alt_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, {Color? highlightColor}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: highlightColor ?? Colors.white),
                const SizedBox(width: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: highlightColor ?? Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroDivider() {
    return Container(
      width: 1,
      height: 26,
      color: Colors.white.withValues(alpha: 0.2),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // FILTER STRIP & SEARCH CONTROLS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildFilterAndSearchControls(
    bool isMobile,
    int total,
    int scheduled,
    int confirmed,
    int completed,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search box
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Search patient by name...',
              hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
              prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.primaryTeal),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.borderGray),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.borderGray),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.primaryTeal, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Horizontal status pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildStatusFilterPill('ALL', 'All ($total)'),
                const SizedBox(width: 8),
                _buildStatusFilterPill('SCHEDULED', 'Pending ($scheduled)',
                    activeBg: const Color(0xFFD97706)),
                const SizedBox(width: 8),
                _buildStatusFilterPill('CONFIRMED', 'Confirmed ($confirmed)',
                    activeBg: const Color(0xFF0F766E)),
                const SizedBox(width: 8),
                _buildStatusFilterPill('COMPLETED', 'Completed ($completed)',
                    activeBg: const Color(0xFF16A34A)),
                const SizedBox(width: 8),
                _buildStatusFilterPill('OTHER', 'Cancelled / No-Show',
                    activeBg: const Color(0xFFDC2626)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilterPill(String key, String label, {Color? activeBg}) {
    final active = _selectedStatusFilter == key;
    final bg = activeBg ?? const Color(0xFF0F766E);

    return InkWell(
      onTap: () => setState(() => _selectedStatusFilter = key),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? bg : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? bg : AppTheme.borderGray,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.w600,
            color: active ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // TIMELINE APPOINTMENT CARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildTimelineCard(dynamic apt, bool isMobile, int index) {
    final status = (apt['status'] ?? 'SCHEDULED').toString().toUpperCase();
    final appointmentId = apt['appointmentId']?.toString() ?? '';
    final patientName = apt['patientName'] ?? 'Registered Patient';
    final scheduledDate = apt['scheduledDate'] as String?;
    final rawStartTime = (apt['startTime'] as String?) ?? '';
    final startTime = rawStartTime.length >= 5 ? rawStartTime.substring(0, 5) : rawStartTime;
    final rawEndTime = (apt['endTime'] as String?) ?? '';
    final endTime = rawEndTime.length >= 5 ? rawEndTime.substring(0, 5) : rawEndTime;
    final sessionType = (apt['sessionType'] as String? ?? 'IN_CLINIC').toUpperCase();
    final isClinic = sessionType == 'IN_CLINIC';
    final statusColor = _statusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: statusColor, width: 5),
            ),
          ),
          padding: EdgeInsets.all(isMobile ? 14 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Time badge, Mode tag, and Status chip
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFCCFBF1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF99F6E4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time_rounded,
                                size: 13, color: Color(0xFF0F766E)),
                            const SizedBox(width: 4),
                            Text(
                              endTime.isNotEmpty ? '$startTime - $endTime' : startTime,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isClinic ? const Color(0xFFEFF6FF) : const Color(0xFFFAF5FF),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isClinic ? const Color(0xFFDBEAFE) : const Color(0xFFF3E8FF),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isClinic ? Icons.local_hospital_outlined : Icons.videocam_outlined,
                              size: 12,
                              color: isClinic ? const Color(0xFF1D4ED8) : const Color(0xFF6D28D9),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isClinic ? 'In-Clinic' : 'Video Call',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isClinic ? const Color(0xFF1D4ED8) : const Color(0xFF6D28D9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Row 2: Patient Info Meta Block
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.primaryLightTeal,
                    child: Text(
                      patientName.isNotEmpty ? patientName[0].toUpperCase() : 'P',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryTeal,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patientName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textMain,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined,
                                size: 12, color: AppTheme.textMuted),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _mediumDate(scheduledDate),
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
                ],
              ),
              const SizedBox(height: 14),

              // Row 3: Action Buttons Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (status == 'SCHEDULED') ...[
                    OutlinedButton(
                      onPressed: () => _changeStatus(appointmentId, 'NO_SHOW'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.dangerRed,
                        side: const BorderSide(color: Color(0xFFFECACA)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: const Size(0, 34),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('No Show', style: TextStyle(fontSize: 11.5)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _changeStatus(appointmentId, 'CONFIRMED'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: const Size(0, 34),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 15),
                      label: const Text('Confirm',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ] else if (status == 'CONFIRMED') ...[
                    OutlinedButton(
                      onPressed: () => _changeStatus(appointmentId, 'NO_SHOW'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.dangerRed,
                        side: const BorderSide(color: Color(0xFFFECACA)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: const Size(0, 34),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('No Show', style: TextStyle(fontSize: 11.5)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _changeStatus(appointmentId, 'COMPLETED'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: const Size(0, 34),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.task_alt_rounded, size: 15),
                      label: const Text('Mark Complete',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ] else if (status == 'COMPLETED') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.done_all_rounded, size: 14, color: Color(0xFF16A34A)),
                          SizedBox(width: 4),
                          Text(
                            'Consultation Completed',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // ILLUSTRATED EMPTY STATE
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFCCFBF1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_available_rounded,
                size: 32, color: Color(0xFF0F766E)),
          ),
          const SizedBox(height: 14),
          const Text(
            'No Consultations Found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textMain,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'There are no patient consultations matching your selected status filter for today.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
          ),
          if (_selectedStatusFilter != 'ALL' || _searchQuery.isNotEmpty) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _selectedStatusFilter = 'ALL';
                  _selectedModeFilter = 'ALL';
                  _searchQuery = '';
                });
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryTeal,
                side: const BorderSide(color: AppTheme.primaryTeal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Clear All Filters'),
            ),
          ],
        ],
      ),
    );
  }
}

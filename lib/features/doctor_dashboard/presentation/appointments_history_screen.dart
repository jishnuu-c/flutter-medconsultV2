import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_notification.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../doctor_dashboard/data/appointment_service.dart';
import '../../../core/network/api_client.dart';

/// Doctor-side Appointments History screen — mobile optimized.
class DoctorAppointmentsHistoryScreen extends ConsumerStatefulWidget {
  const DoctorAppointmentsHistoryScreen({super.key});

  @override
  ConsumerState<DoctorAppointmentsHistoryScreen> createState() =>
      _DoctorAppointmentsHistoryScreenState();
}

class _DoctorAppointmentsHistoryScreenState
    extends ConsumerState<DoctorAppointmentsHistoryScreen> {
  bool _isLoading = false;
  String? _doctorId;
  List<dynamic> _appointments = [];

  // Filters
  String _selectedStatus = '';
  String _selectedSessionType = '';
  DateTime? _fromDate;
  DateTime? _toDate;

  // Pagination
  int _page = 0;
  final int _size = 10;
  int _totalPages = 1;
  int _totalElements = 0;

  static const _statusOptions = [
    {'label': 'All Statuses', 'value': ''},
    {'label': 'Scheduled', 'value': 'SCHEDULED'},
    {'label': 'Confirmed', 'value': 'CONFIRMED'},
    {'label': 'Completed', 'value': 'COMPLETED'},
    {'label': 'Cancelled', 'value': 'CANCELLED'},
    {'label': 'No Show', 'value': 'NO_SHOW'},
  ];

  static const _sessionTypeOptions = [
    {'label': 'All Modes', 'value': ''},
    {'label': 'In-Clinic Visit', 'value': 'IN_CLINIC'},
    {'label': 'Video Call', 'value': 'VIDEO_CALL'},
  ];

  static const _avatarBgColors = [
    Color(0xFFE0F2FE),
    Color(0xFFF0FDFA),
    Color(0xFFEDE9FE),
    Color(0xFFFEF3C7),
    Color(0xFFECFDF5),
  ];
  static const _avatarFgColors = [
    Color(0xFF0369A1),
    Color(0xFF0F766E),
    Color(0xFF6D28D9),
    Color(0xFFB45309),
    Color(0xFF047857),
  ];

  @override
  void initState() {
    super.initState();
    _resolveDoctorIdAndLoad();
  }

  Future<void> _resolveDoctorIdAndLoad() async {
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authNotifierProvider).currentUser;
      if (user == null) throw Exception('No logged-in user found.');
      final doctors = await ref.read(doctorServiceProvider).getAllDoctors();
      final match = doctors.where((d) =>
          (d.email.isNotEmpty &&
              d.email.toLowerCase() == user.email.toLowerCase()) ||
          (d.fullName.trim().isNotEmpty &&
              d.fullName.trim().toLowerCase() ==
                  user.fullName.trim().toLowerCase()));
      if (match.isEmpty) {
        throw Exception('Doctor profile not found for this user.');
      }
      _doctorId = match.first.doctorId;
      await _loadAppointments();
    } catch (e) {
      if (mounted) {
        AppNotification.showError(
          context,
          'Failed to load appointments: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAppointments() async {
    setState(() => _isLoading = true);
    try {
      final searchRequest = <String, dynamic>{
        'doctorId': _doctorId,
        'page': _page,
        'size': _size,
        'sortBy': 'scheduledDate',
        'sortDir': 'DESC',
      };
      if (_selectedStatus.isNotEmpty) searchRequest['status'] = _selectedStatus;
      if (_selectedSessionType.isNotEmpty) {
        searchRequest['sessionType'] = _selectedSessionType;
      }
      if (_fromDate != null) {
        searchRequest['fromDate'] =
            _fromDate!.toIso8601String().split('T').first;
      }
      if (_toDate != null) {
        searchRequest['toDate'] = _toDate!.toIso8601String().split('T').first;
      }

      final res = await ref
          .read(appointmentServiceProvider)
          .searchAppointments(searchRequest);
      final content = (res is Map ? res['content'] : null) ?? [];
      if (mounted) {
        setState(() {
          _appointments = content;
          _totalPages = (res is Map ? res['totalPages'] : null) ?? 1;
          _totalElements = (res is Map ? res['totalElements'] : null) ?? 0;
        });
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showError(
          context,
          'Failed to load appointments history: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    _page = 0;
    _loadAppointments();
  }

  void _clearFilters() {
    setState(() {
      _selectedStatus = '';
      _selectedSessionType = '';
      _fromDate = null;
      _toDate = null;
      _page = 0;
    });
    _loadAppointments();
  }

  void _nextPage() {
    if (_page < _totalPages - 1) {
      setState(() => _page++);
      _loadAppointments();
    }
  }

  void _prevPage() {
    if (_page > 0) {
      setState(() => _page--);
      _loadAppointments();
    }
  }

  Color _statusBg(String status) {
    switch (status.toUpperCase()) {
      case 'COMPLETED':
        return const Color(0xFFDCFCE7);
      case 'CONFIRMED':
        return const Color(0xFFCCFBF1);
      case 'SCHEDULED':
        return const Color(0xFFE0F2FE);
      case 'CANCELLED':
        return const Color(0xFFFEE2E2);
      case 'NO_SHOW':
        return const Color(0xFFFEF3C7);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  Color _statusFg(String status) {
    switch (status.toUpperCase()) {
      case 'COMPLETED':
        return const Color(0xFF166534);
      case 'CONFIRMED':
        return const Color(0xFF0F766E);
      case 'SCHEDULED':
        return const Color(0xFF0369A1);
      case 'CANCELLED':
        return const Color(0xFFB91C1C);
      case 'NO_SHOW':
        return const Color(0xFFB45309);
      default:
        return const Color(0xFF4B5563);
    }
  }

  int _colorIdx(String name) => name.isNotEmpty
      ? name.codeUnitAt(0) % _avatarBgColors.length
      : 0;

  String _initials(String name) {
    if (name.isEmpty) return 'PT';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return Scaffold(
      backgroundColor: AppTheme.backgroundApp,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _resolveDoctorIdAndLoad,
          color: AppTheme.primaryTeal,
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: isMobile ? 16 : 24,
            ),
            children: [
              // 1. Header Banner
              _buildHeaderBanner(isMobile),
              const SizedBox(height: 16),

              // 2. Filters Card
              _buildFiltersCard(isMobile),
              const SizedBox(height: 16),

              // 3. Appointments List
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryTeal),
                  ),
                )
              else if (_appointments.isEmpty)
                _buildEmptyState()
              else ...[
                ..._appointments.map((a) => _buildAppointmentCard(a, isMobile)),
                const SizedBox(height: 12),
                _buildPaginationFooter(),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 1. HEADER BANNER
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHeaderBanner(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F766E), Color(0xFF115E59)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withOpacity(0.2),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history_rounded, size: 13, color: Colors.white),
                    SizedBox(width: 5),
                    Text(
                      'CLINICAL ARCHIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF14B8A6).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Total: $_totalElements',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Appointments History',
            style: TextStyle(
              color: Colors.white,
              fontSize: isMobile ? 22 : 26,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Search, filter, and review details of all patient clinical appointments',
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: isMobile ? 12 : 13.5,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. FILTERS CARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildFiltersCard(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  'Status',
                  _selectedStatus,
                  _statusOptions,
                  (v) {
                    setState(() => _selectedStatus = v);
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdown(
                  'Mode',
                  _selectedSessionType,
                  _sessionTypeOptions,
                  (v) {
                    setState(() => _selectedSessionType = v);
                    _applyFilters();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDateField('From Date', _fromDate, (d) {
                  setState(() => _fromDate = d);
                  _applyFilters();
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDateField('To Date', _toDate, (d) {
                  setState(() => _toDate = d);
                  _applyFilters();
                }),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _clearFilters,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textMuted,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Clear Filters', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _loadAppointments,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('Refresh', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(String label, String value,
      List<Map<String, String>> options, ValueChanged<String> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMain),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppTheme.backgroundApp,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.borderGray.withOpacity(0.8)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: AppTheme.textMuted),
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textMain),
              items: options
                  .map((o) => DropdownMenuItem(
                      value: o['value'], child: Text(o['label']!)))
                  .toList(),
              onChanged: (v) => onChanged(v ?? ''),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField(
      String label, DateTime? value, ValueChanged<DateTime?> onPicked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMain),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            onPicked(picked);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.backgroundApp,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderGray.withOpacity(0.8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value == null
                      ? 'Select date'
                      : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: value == null ? AppTheme.textMuted : AppTheme.textMain,
                  ),
                ),
                const Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(36),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.7)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
            child: const Icon(Icons.event_busy, size: 28, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 10),
          const Text('No Appointments History Found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          const Text(
            'No appointment records match the current status or date range.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. APPOINTMENT CARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildAppointmentCard(dynamic a, bool isMobile) {
    final status = (a['status'] ?? 'SCHEDULED').toString();
    final sessionType = (a['sessionType'] ?? 'IN_CLINIC').toString();
    final patientName = (a['patientName'] ?? 'Patient').toString();
    final rawAvatarUrl = (a['patientAvatarUrl'] ??
            a['patientAvatar'] ??
            a['avatarUrl'] ??
            '')
        .toString();
    final avatarUrl = rawAvatarUrl.isNotEmpty
        ? (rawAvatarUrl.startsWith('http')
            ? rawAvatarUrl
            : '$kBaseUrl${rawAvatarUrl.startsWith('/') ? '' : '/'}$rawAvatarUrl')
        : '';
    final scheduledDate = (a['scheduledDate'] ?? '').toString();
    final startTime = (a['startTime'] ?? '').toString();
    final clinicName = (a['clinicNameEn'] ?? '').toString();
    final department = (a['department'] ?? '').toString();
    final idx = _colorIdx(patientName);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _avatarBgColors[idx],
                backgroundImage:
                    avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                onBackgroundImageError:
                    avatarUrl.isNotEmpty ? (_, __) {} : null,
                child: avatarUrl.isEmpty
                    ? Text(
                        _initials(patientName),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: _avatarFgColors[idx],
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patientName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: sessionType == 'IN_CLINIC'
                                ? const Color(0xFFEFF6FF)
                                : const Color(0xFFF5F3FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            sessionType == 'IN_CLINIC' ? '🏢 In-Clinic' : '💻 Video Call',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: sessionType == 'IN_CLINIC'
                                  ? const Color(0xFF2563EB)
                                  : const Color(0xFF7C3AED),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusBg(status),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.replaceAll('_', ' '),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: _statusFg(status),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Date & Time + Location
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 13, color: AppTheme.textMuted),
              const SizedBox(width: 5),
              Text(
                '$scheduledDate • ${startTime.length >= 5 ? startTime.substring(0, 5) : startTime}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMain),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.local_hospital_outlined, size: 13, color: AppTheme.textMuted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${clinicName.isEmpty ? "Private Clinic" : clinicName}${department.isNotEmpty ? " ($department)" : ""}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Action Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openDetails(a),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8),
                side: const BorderSide(color: AppTheme.borderGray),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.visibility_outlined, size: 14),
              label: const Text('View Full Details', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.7)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Page ${_page + 1} of $_totalPages',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
          ),
          Row(
            children: [
              OutlinedButton(
                onPressed: _page == 0 ? null : _prevPage,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: const Size(60, 30),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('◀ Prev', style: TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _page >= _totalPages - 1 ? null : _nextPage,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: const Size(60, 30),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Next ▶', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 4. APPOINTMENT DETAILS BOTTOM SHEET
  // ─────────────────────────────────────────────────────────────────────────
  void _openDetails(dynamic a) {
    final status = (a['status'] ?? 'SCHEDULED').toString();
    final patientName = (a['patientName'] ?? 'Patient').toString();
    final rawAvatarUrl = (a['patientAvatarUrl'] ??
            a['patientAvatar'] ??
            a['avatarUrl'] ??
            '')
        .toString();
    final avatarUrl = rawAvatarUrl.isNotEmpty
        ? (rawAvatarUrl.startsWith('http')
            ? rawAvatarUrl
            : '$kBaseUrl${rawAvatarUrl.startsWith('/') ? '' : '/'}$rawAvatarUrl')
        : '';
    final idx = _colorIdx(patientName);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.92,
          builder: (ctx, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.borderGray,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0F766E), Color(0xFF115E59)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: _avatarBgColors[idx],
                          backgroundImage:
                              avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl.isEmpty
                              ? Text(
                                  _initials(patientName),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: _avatarFgColors[idx],
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                patientName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'ID: ${(a['patientId'] ?? '').toString().length > 10 ? '${(a['patientId'] ?? '').toString().substring(0, 8)}...' : (a['patientId'] ?? '')}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _statusBg(status),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status.replaceAll('_', ' '),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: _statusFg(status),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Detail Body
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        _detailRow('Appointment ID', (a['appointmentId'] ?? '--').toString()),
                        _detailRow('Scheduled Date', (a['scheduledDate'] ?? '--').toString()),
                        _detailRow('Slot Time', '${a['startTime'] ?? '--'} - ${a['endTime'] ?? '--'} (${a['durationMinutes'] ?? '30'} mins)'),
                        _detailRow('Session Mode', a['sessionType'] == 'IN_CLINIC' ? 'In-Clinic Consultation' : 'Telehealth Video Call'),
                        _detailRow('Clinic Location', a['clinicNameEn'] ?? 'Main Branch'),
                        _detailRow('Department', a['department'] ?? 'General Medicine'),
                        if (a['patientPhone'] != null)
                          _detailRow('Patient Phone', a['patientPhone'].toString()),
                        if (a['patientEmail'] != null)
                          _detailRow('Patient Email', a['patientEmail'].toString()),
                        if (a['reasonForVisit'] != null && a['reasonForVisit'].toString().isNotEmpty)
                          _detailRow('Reason for Visit', a['reasonForVisit'].toString()),
                        if (a['cancellationReason'] != null && a['cancellationReason'].toString().isNotEmpty)
                          _detailRow('Cancellation Reason', a['cancellationReason'].toString(), isWarning: true),
                      ],
                    ),
                  ),

                  Container(
                    padding: EdgeInsets.fromLTRB(20, 10, 20, 12 + MediaQuery.of(context).padding.bottom),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: AppTheme.borderGray)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailRow(String label, String value, {bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: isWarning ? AppTheme.dangerRed : AppTheme.textMain,
            ),
          ),
        ],
      ),
    );
  }
}
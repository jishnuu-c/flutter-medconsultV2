import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../doctor_dashboard/data/appointment_service.dart';

/// Mirrors Angular's doctor-dashboard/appointments-history — mobile view.
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

  // Filters — mirrors Angular's selectedStatus / selectedSessionType / fromDate / toDate
  String _selectedStatus = '';
  String _selectedSessionType = '';
  DateTime? _fromDate;
  DateTime? _toDate;

  // Pagination — mirrors Angular's page / size / totalPages / totalElements
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
      // Match by email/fullName, not userId — mirrors Angular
      // (appointments-history.component.ts). `userId` on the doctor
      // record isn't reliable for self-lookup on this backend; matching
      // on it can pick the wrong doctor's record and send the wrong
      // doctorId downstream (→ 403).
      final match = doctors.where((d) =>
          (d.email.isNotEmpty &&
              d.email.toLowerCase() == user.email.toLowerCase()) ||
          (d.fullName.trim().isNotEmpty &&
              d.fullName.trim().toLowerCase() ==
                  user.fullName.trim().toLowerCase()));
      if (match.isEmpty)
        throw Exception('Doctor profile not found for this user.');
      _doctorId = match.first.doctorId;
      await _loadAppointments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load appointments: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAppointments() async {
    setState(() => _isLoading = true);
    try {
      // Mirrors Angular: uses the POST /search endpoint with doctorId in
      // the body, not GET /doctor/{doctorId} — the latter 403s for a
      // plain DOCTOR-role token on this backend.
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
        searchRequest['fromDate'] = _fromDate!.toIso8601String().split('T').first;
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load appointments history: $e')));
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

  // ---- Angular-matching palette helpers ----

  Color _statusBg(String status) {
    switch (status) {
      case 'COMPLETED':
        return const Color(0xFFDEF7EC);
      case 'CONFIRMED':
        return const Color(0xFFE1EFFE);
      case 'SCHEDULED':
        return const Color(0xFFFDF6B2);
      case 'CANCELLED':
      case 'NO_SHOW':
        return const Color(0xFFFDE8E8);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  Color _statusFg(String status) {
    switch (status) {
      case 'COMPLETED':
        return const Color(0xFF03543F);
      case 'CONFIRMED':
        return const Color(0xFF1E429F);
      case 'SCHEDULED':
        return const Color(0xFF723B13);
      case 'CANCELLED':
      case 'NO_SHOW':
        return const Color(0xFF9B1C1C);
      default:
        return const Color(0xFF4B5563);
    }
  }

  static const _avatarBgColors = [
    Color(0xFFE1F5EE),
    Color(0xFFDBEAFE),
    Color(0xFFEDE9FE),
    Color(0xFFFEF3C7),
    Color(0xFFDCFCE7),
  ];
  static const _avatarFgColors = [
    Color(0xFF085041),
    Color(0xFF1E40AF),
    Color(0xFF5B21B6),
    Color(0xFF92400E),
    Color(0xFF166534),
  ];

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
    return RefreshIndicator(
      onRefresh: _resolveDoctorIdAndLoad,
      color: const Color(0xFF085041),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildFiltersCard(),
          const SizedBox(height: 16),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF085041))),
            )
          else if (_appointments.isEmpty)
            _buildEmptyState()
          else ...[
            ..._appointments.map(_buildAppointmentCard),
            const SizedBox(height: 8),
            _buildPaginationFooter(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('📜 Appointments History',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF085041))),
              const SizedBox(height: 4),
              const Text(
                  'All appointments booked with you, past and upcoming.',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFCCFBF1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('Total: $_totalElements',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F766E))),
        ),
      ],
    );
  }

  Widget _buildFiltersCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildDropdown('Status', _selectedStatus,
                  _statusOptions, (v) {
                setState(() => _selectedStatus = v);
                _applyFilters();
              })),
              const SizedBox(width: 10),
              Expanded(child: _buildDropdown('Mode', _selectedSessionType,
                  _sessionTypeOptions, (v) {
                setState(() => _selectedSessionType = v);
                _applyFilters();
              })),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _buildDateField('From Date', _fromDate, (d) {
                setState(() => _fromDate = d);
                _applyFilters();
              })),
              const SizedBox(width: 10),
              Expanded(child: _buildDateField('To Date', _toDate, (d) {
                setState(() => _toDate = d);
                _applyFilters();
              })),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _clearFilters,
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF4B5563),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                child: const Text('🧹 Clear', style: TextStyle(fontSize: 12.5)),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                onPressed: _loadAppointments,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF085041),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('🔍 Refresh', style: TextStyle(fontSize: 12.5)),
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
        Text(label,
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151))),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD1D5DB)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF1F2937)),
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
        Text(label,
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151))),
        const SizedBox(height: 4),
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
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD1D5DB)),
            ),
            child: Text(
              value == null
                  ? '—'
                  : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF1F2937)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: const Text('No appointments history matches the current filters.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
    );
  }

  Widget _buildAppointmentCard(dynamic a) {
    final status = (a['status'] ?? '').toString();
    final sessionType = (a['sessionType'] ?? '').toString();
    final patientName = (a['patientName'] ?? 'Patient').toString();
    final scheduledDate = (a['scheduledDate'] ?? '').toString();
    final startTime = (a['startTime'] ?? '').toString();
    final clinicName = (a['clinicNameEn'] ?? '').toString();
    final idx = _colorIdx(patientName);

    return InkWell(
      onTap: () => _openDetails(a),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _avatarBgColors[idx],
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(_initials(patientName),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: _avatarFgColors[idx])),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(patientName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusBg(status),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(status,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _statusFg(status))),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '🗓️ $scheduledDate  @ ⏰ ${startTime.length >= 5 ? startTime.substring(0, 5) : startTime}',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF374151)),
            ),
            const SizedBox(height: 4),
            Text(
              '🏢 ${clinicName.isEmpty ? 'Private Clinic' : clinicName} (${sessionType == 'IN_CLINIC' ? 'In-Clinic' : 'Video Call'})',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => _openDetails(a),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4B5563),
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('👁️ View Details',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Page ${_page + 1} of $_totalPages',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          Row(
            children: [
              OutlinedButton(
                onPressed: _page == 0 ? null : _prevPage,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4B5563),
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: const Text('◀ Prev', style: TextStyle(fontSize: 11.5)),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _page >= _totalPages - 1 ? null : _nextPage,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4B5563),
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: const Text('Next ▶', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openDetails(dynamic a) {
    final status = (a['status'] ?? '').toString();
    final patientName = (a['patientName'] ?? 'Patient').toString();
    final idx = _colorIdx(patientName);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.92,
          builder: (ctx, scrollController) {
            return Column(
              children: [
                // Header banner — mirrors Angular's spec-modal-header gradient
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF085041), Color(0xFF0F766E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _avatarBgColors[idx],
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(_initials(patientName),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                                color: _avatarFgColors[idx])),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(patientName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _statusBg(status),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(status,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: _statusFg(status))),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      _detailSpecCard('📅', 'Scheduled Date & Time',
                          '🗓️ ${a['scheduledDate'] ?? ''}   ⏰ ${(a['startTime'] ?? '').toString().length >= 5 ? (a['startTime'] as String).substring(0, 5) : a['startTime'] ?? ''} (${a['durationMinutes'] ?? '-'} min)\n${(a['sessionType'] ?? '') == 'IN_CLINIC' ? '🏢 In-Clinic Visit' : '💻 Video Call Session'}'),
                      _detailSpecCard(
                          '🏥',
                          'Clinical Assignment',
                          '${a['clinicNameEn'] ?? 'Private Clinic'}\n🩺 ${a['department'] ?? 'General Practice'} • 📍 ${a['branchNameEn'] ?? 'Main Branch'}'),
                      _detailSpecCard('📝', 'Reason for Consultation',
                          (a['reason'] ?? 'No specific reasons provided by the patient.').toString()),
                      if (status == 'CANCELLED' || status == 'NO_SHOW')
                        _detailSpecCard(
                          '⚠️',
                          'Cancellation Information',
                          'Cancelled By: ${a['cancelledById'] ?? 'System'}\nReason: ${a['cancelReason'] ?? 'No reason provided'}',
                          danger: true,
                        ),
                      const SizedBox(height: 8),
                      const Text('🚀 Quick Shortcuts',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF374151))),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            // Navigate to EMR for a['patientId']
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('📋 View Patient EMR Chart'),
                        ),
                      ),
                      if ((a['consultationId'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              // Navigate to consultation chat for a['consultationId']
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF085041),
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('💬 Go to Consultation Chat'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _detailSpecCard(String icon, String title, String body,
      {bool danger = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFFFF1F2) : const Color(0xFFF8FAFC),
        border: Border.all(
            color: danger ? const Color(0xFFFECDD3) : const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: danger ? const Color(0xFFFFE4E6) : const Color(0xFFF1F5F9),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Text(title.toUpperCase(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: danger
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF475569))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(body,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: danger
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF334155))),
          ),
        ],
      ),
    );
  }
}
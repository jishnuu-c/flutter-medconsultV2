import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../doctor_dashboard/data/appointment_service.dart';
import '../data/patient_service.dart';
import '../data/review_service.dart';

/// Extra brand tokens from styles.css not yet in AppTheme, mirrored from
/// book_appointment_screen.dart so both screens read as one design system.
class _C {
  static const tealDark = Color(0xFF085041);
  static const tealLight = Color(0xFFE1F5EE);
  static const off = Color(0xFFF8FAF9);
  static const t3 = Color(0xFF6B7280);
  static const feeBg = Color(0xFFECFDF5);
  static const feeText = Color(0xFF065F46);
  static const infoBg = Color(0xFFEFF6FF);
  static const infoText = Color(0xFF1D4ED8);
  static const dangerBg = Color(0xFFFEF2F2);

  static const avatarBg = [
    Color(0xFFE1F5EE),
    Color(0xFFDBEAFE),
    Color(0xFFEDE9FE),
    Color(0xFFFEF3C7),
    Color(0xFFDCFCE7),
  ];
  static const avatarFg = [
    Color(0xFF085041),
    Color(0xFF1E40AF),
    Color(0xFF5B21B6),
    Color(0xFF92400E),
    Color(0xFF166534),
  ];
}

class _NextDay {
  final String date;
  final String label;
  final String dayName;
  bool hasSlots;
  _NextDay(
      {required this.date,
      required this.label,
      required this.dayName,
      this.hasSlots = false});
}

/// Mirrors Angular's patient-dashboard/appointments ("My Appointments") 1:1:
/// filters, status/mode badges, pagination, and the details / cancel /
/// reschedule / review dialogs — surfaced here as bottom sheets since this
/// is a phone screen instead of a desktop modal stack.
class PatientAppointmentsScreen extends ConsumerStatefulWidget {
  const PatientAppointmentsScreen({super.key});

  @override
  ConsumerState<PatientAppointmentsScreen> createState() =>
      _PatientAppointmentsScreenState();
}

class _PatientAppointmentsScreenState
    extends ConsumerState<PatientAppointmentsScreen> {
  bool _isLoading = false;
  bool _needProfileInit = false;
  String? _patientId;

  List<Map<String, dynamic>> _appointments = [];
  List<Map<String, dynamic>> _filteredAppointments = [];
  final Map<String, List<dynamic>> _doctorClinicsCache = {};

  // Filters (mirrors selectedStatus / selectedSessionType / fromDate / toDate / searchQuery)
  String _selectedStatus = '';
  String _selectedSessionType = '';
  String _fromDate = '';
  String _toDate = '';
  String _searchQuery = '';
  final _searchController = TextEditingController();

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

  @override
  void initState() {
    super.initState();
    _loadPatientProfile();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Data loading (mirrors ngOnInit → loadPatientProfile → loadAppointments) ─

  Future<void> _loadPatientProfile() async {
    setState(() => _isLoading = true);
    try {
      final profile = await ref.read(patientServiceProvider).getMyProfile();
      final id = profile is Map ? profile['patientId']?.toString() : null;
      if (id == null || id.isEmpty) {
        setState(() => _needProfileInit = true);
        return;
      }
      _patientId = id;
      _needProfileInit = false;
      await _loadAppointments();
    } catch (e) {
      final status = e is DioException ? e.response?.statusCode : null;
      if (status == 404) {
        setState(() => _needProfileInit = true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAppointments() async {
    if (_patientId == null) return;
    setState(() => _isLoading = true);
    try {
      final res = await ref
          .read(appointmentServiceProvider)
          .getMyAppointments(page: 0, size: 100);
      final rawList =
          ((res is Map ? res['content'] : null) as List? ?? []).cast<dynamic>();

      if (rawList.isEmpty) {
        _appointments = [];
        _filterAppointments();
        return;
      }

      final uniqueDocIds =
          rawList.map((a) => a['doctorId']?.toString() ?? '').toSet().toList();
      final uncached =
          uniqueDocIds.where((id) => !_doctorClinicsCache.containsKey(id));

      if (uncached.isNotEmpty) {
        final results = await Future.wait(uncached.map((docId) async {
          try {
            final clinics =
                await ref.read(doctorServiceProvider).getDoctorClinics(docId);
            return MapEntry(docId, clinics);
          } catch (_) {
            return MapEntry(docId, const <dynamic>[]);
          }
        }));
        for (final entry in results) {
          _doctorClinicsCache[entry.key] = entry.value;
        }
      }

      _appointments = rawList.map<Map<String, dynamic>>((app) {
        final a = Map<String, dynamic>.from(app as Map);
        final clinics = _doctorClinicsCache[a['doctorId']?.toString()] ?? [];
        final link =
            clinics.cast<dynamic>().where((c) => c.dcId == a['dcId']).toList();
        final dc = link.isNotEmpty ? link.first : null;
        a['clinicId'] = dc?.clinicId;
        a['clinicNameEn'] = dc?.clinicNameEn ?? 'Private Clinic';
        a['branchNameEn'] = dc?.branchNameEn ?? 'Main Branch';
        a['department'] = dc?.department ?? 'General Medicine';
        a['consultationFeeSar'] = dc?.consultationFeeSar ?? 100;
        return a;
      }).toList();

      // Sort by scheduledDate desc, startTime desc
      _appointments.sort((a, b) {
        final dc = (b['scheduledDate'] ?? '')
            .toString()
            .compareTo((a['scheduledDate'] ?? '').toString());
        if (dc != 0) return dc;
        return (b['startTime'] ?? '')
            .toString()
            .compareTo((a['startTime'] ?? '').toString());
      });

      _filterAppointments();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load appointments.')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Filtering & pagination (mirrors filterAppointments) ──────────────────

  void _filterAppointments() {
    var list = [..._appointments];

    if (_selectedStatus.isNotEmpty) {
      list = list.where((a) => a['status'] == _selectedStatus).toList();
    }
    if (_selectedSessionType.isNotEmpty) {
      list =
          list.where((a) => a['sessionType'] == _selectedSessionType).toList();
    }
    if (_fromDate.isNotEmpty) {
      list = list
          .where((a) =>
              (a['scheduledDate'] ?? '').toString().compareTo(_fromDate) >= 0)
          .toList();
    }
    if (_toDate.isNotEmpty) {
      list = list
          .where((a) =>
              (a['scheduledDate'] ?? '').toString().compareTo(_toDate) <= 0)
          .toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      list = list
          .where((a) =>
              (a['doctorName'] ?? '').toString().toLowerCase().contains(q) ||
              (a['department'] ?? '').toString().toLowerCase().contains(q))
          .toList();
    }

    _totalElements = list.length;
    _totalPages = (list.length / _size).ceil();
    if (_totalPages < 1) _totalPages = 1;

    final startIdx = _page * _size;
    setState(() {
      _filteredAppointments = list.skip(startIdx).take(_size).toList();
    });
  }

  void _applyFilters() {
    _page = 0;
    _filterAppointments();
  }

  void _clearFilters() {
    setState(() {
      _selectedStatus = '';
      _selectedSessionType = '';
      _fromDate = '';
      _toDate = '';
      _searchQuery = '';
      _searchController.clear();
      _page = 0;
    });
    _filterAppointments();
  }

  void _nextPage() {
    if (_page < _totalPages - 1) {
      _page++;
      _filterAppointments();
    }
  }

  void _prevPage() {
    if (_page > 0) {
      _page--;
      _filterAppointments();
    }
  }

  bool _hasActions(Map<String, dynamic> app) {
    final s = app['status'];
    return s == 'COMPLETED' || s == 'SCHEDULED' || s == 'CONFIRMED';
  }

  // ── Display helpers (mirror getInitials/getAvatarBg/getDoctorDisplayName) ─

  String _getInitials(String? name) {
    if (name == null || name.trim().isEmpty) return 'DR';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return name
        .trim()
        .substring(0, name.trim().length.clamp(0, 2))
        .toUpperCase();
  }

  int _colorIndex(String? name) {
    if (name == null || name.isEmpty) return 0;
    return name.codeUnitAt(0) % _C.avatarBg.length;
  }

  String _doctorDisplayName(String? name) {
    if (name == null || name.trim().isEmpty) return '';
    final trimmed = name.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('dr') ||
        lower.startsWith('doctor') ||
        lower.startsWith('prof') ||
        lower.startsWith('consultant') ||
        lower.startsWith('specialist') ||
        trimmed.startsWith('د.')) {
      return trimmed;
    }
    return 'Dr. $trimmed';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'SCHEDULED':
        return 'Scheduled';
      case 'CONFIRMED':
        return 'Confirmed';
      case 'COMPLETED':
        return 'Completed';
      case 'CANCELLED':
        return 'Cancelled';
      case 'NO_SHOW':
        return 'No Show';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return AppTheme.successGreen;
      case 'CONFIRMED':
        return _C.infoText;
      case 'SCHEDULED':
        return AppTheme.warningAmber;
      case 'CANCELLED':
      case 'NO_SHOW':
        return AppTheme.dangerRed;
      default:
        return AppTheme.textMuted;
    }
  }

  String _fmtFee(dynamic fee) {
    final f = (fee is num) ? fee.toDouble() : double.tryParse('$fee') ?? 150;
    return f == f.roundToDouble() ? f.toInt().toString() : f.toStringAsFixed(2);
  }

  String _fmtDateMedium(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
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
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _fmtDateFull(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_needProfileInit) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: AppTheme.warningAmber, size: 30),
              ),
              const SizedBox(height: 16),
              const Text('Patient Profile Registration Required',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 8),
              const Text(
                'Welcome! Please complete your Patient Details registration to unlock booking appointments, viewing appointment history, and managing scheduled visits.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.go('/patient/profile'),
                child: const Text('Complete Patient Details Now'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAppointments,
      child: (_isLoading && _appointments.isEmpty)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _buildFiltersCard(),
                const SizedBox(height: 16),
                if (_filteredAppointments.isEmpty) _emptyState(),
                for (final app in _filteredAppointments) _appointmentCard(app),
                const SizedBox(height: 12),
                _buildPaginationFooter(),
              ],
            ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _C.tealLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.event_note_rounded, size: 13, color: _C.tealDark),
              SizedBox(width: 4),
              Text('Appointment Center',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _C.tealDark)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text('My Appointments',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textMain)),
        const SizedBox(height: 4),
        const Text(
          'Manage your upcoming consultations, view clinical session history, and modify scheduled visits.',
          style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => context.push('/patient/book-appointment'),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Book New Appointment'),
          ),
        ),
      ],
    );
  }

  // ── Filters card (mirrors filters-card) ───────────────────────────────

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
          const Text('Status',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _C.t3)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _selectedStatus,
            isExpanded: true,
            decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            items: _statusOptions
                .map((o) => DropdownMenuItem(
                    value: o['value'], child: Text(o['label']!)))
                .toList(),
            onChanged: (v) {
              setState(() => _selectedStatus = v ?? '');
              _applyFilters();
            },
          ),
          const SizedBox(height: 12),
          const Text('Consultation Mode',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _C.t3)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _selectedSessionType,
            isExpanded: true,
            decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            items: _sessionTypeOptions
                .map((o) => DropdownMenuItem(
                    value: o['value'], child: Text(o['label']!)))
                .toList(),
            onChanged: (v) {
              setState(() => _selectedSessionType = v ?? '');
              _applyFilters();
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('From Date',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _C.t3)),
                    const SizedBox(height: 6),
                    _dateField(_fromDate, (v) {
                      setState(() => _fromDate = v);
                      _applyFilters();
                    }),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('To Date',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _C.t3)),
                    const SizedBox(height: 6),
                    _dateField(_toDate, (v) {
                      setState(() => _toDate = v);
                      _applyFilters();
                    }),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Search Doctor',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _C.t3)),
          const SizedBox(height: 6),
          TextField(
            controller: _searchController,
            onChanged: (v) {
              _searchQuery = v;
              _applyFilters();
            },
            decoration: const InputDecoration(
              hintText: 'Search by doctor/department...',
              isDense: true,
              suffixIcon: Icon(Icons.search, size: 18),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 15),
                label: const Text('Clear Filters'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _loadAppointments,
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateField(String value, ValueChanged<String> onChanged) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.tryParse(value) ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          final s =
              '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
          onChanged(s);
        }
      },
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.borderGray),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.centerLeft,
        child: Text(value.isEmpty ? 'Select date' : value,
            style: TextStyle(
                fontSize: 12.5,
                color: value.isEmpty ? _C.t3 : AppTheme.textMain)),
      ),
    );
  }

  // ── Empty state / pagination ─────────────────────────────────────────

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: const Text('No appointments history matches the current filters.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted)),
    );
  }

  Widget _buildPaginationFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
                'Showing page ${_page + 1} of $_totalPages ($_totalElements total records)',
                style: const TextStyle(fontSize: 11.5, color: _C.t3)),
          ),
          Row(
            children: [
              IconButton(
                onPressed: _page == 0 ? null : _prevPage,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                onPressed: _page >= _totalPages - 1 ? null : _nextPage,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Appointment card (mirrors mobile-app-card) ───────────────────────

  Widget _appointmentCard(Map<String, dynamic> app) {
    final status = (app['status'] ?? '').toString();
    final sessionType = (app['sessionType'] ?? '').toString();
    final doctorName = (app['doctorName'] ?? '').toString();
    final scheduledDate = (app['scheduledDate'] ?? '').toString();
    final startTime = (app['startTime'] ?? '').toString();
    final timeLabel =
        startTime.length >= 5 ? startTime.substring(0, 5) : startTime;
    final clinicName = (app['clinicNameEn'] ?? '').toString();
    final colorIdx = _colorIndex(doctorName);
    final isClinic = sessionType == 'IN_CLINIC';

    return GestureDetector(
      onTap: () => _openDetails(app),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
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
                CircleAvatar(
                  radius: 16,
                  backgroundColor: _C.avatarBg[colorIdx],
                  child: Text(_getInitials(doctorName),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _C.avatarFg[colorIdx])),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_doctorDisplayName(doctorName),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(_statusLabel(status),
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _statusColor(status))),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_month_outlined,
                    size: 13, color: _C.t3),
                const SizedBox(width: 4),
                Text('${_fmtDateMedium(scheduledDate)} @ $timeLabel',
                    style: const TextStyle(fontSize: 12, color: _C.t3)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                    isClinic
                        ? Icons.local_hospital_outlined
                        : Icons.videocam_outlined,
                    size: 13,
                    color: _C.t3),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                      '$clinicName (${isClinic ? 'In-Clinic' : 'Video Call'})',
                      style: const TextStyle(fontSize: 12, color: _C.t3),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openDetails(app),
                icon: const Icon(Icons.remove_red_eye_outlined, size: 14),
                label: const Text('View Details'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── DETAILS bottom sheet (mirrors DETAILS DIALOG MODAL) ──────────────

  void _openDetails(Map<String, dynamic> app) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (ctx, scrollController) =>
            _detailsSheetContent(app, scrollController),
      ),
    );
  }

  Widget _detailsSheetContent(
      Map<String, dynamic> app, ScrollController scrollController) {
    final status = (app['status'] ?? '').toString();
    final doctorName = (app['doctorName'] ?? '').toString();
    final colorIdx = _colorIndex(doctorName);
    final scheduledDate = (app['scheduledDate'] ?? '').toString();
    final startTime = (app['startTime'] ?? '').toString();
    final timeLabel =
        startTime.length >= 5 ? startTime.substring(0, 5) : startTime;
    final sessionType = (app['sessionType'] ?? '').toString();
    final isClinic = sessionType == 'IN_CLINIC';
    final appointmentId = (app['appointmentId'] ?? '').toString();
    final apptType =
        (app['appointmentType'] ?? '').toString().replaceAll('_', ' ');
    final isCancelled = status == 'CANCELLED' || status == 'NO_SHOW';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: AppTheme.primaryTeal,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_note_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Appointment Specification Details',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      Text(
                          'ID: #${appointmentId.isNotEmpty ? appointmentId.substring(0, appointmentId.length.clamp(0, 8)) : 'APT-REF'}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _C.off,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: _C.avatarBg[colorIdx],
                        child: Text(_getInitials(doctorName),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _C.avatarFg[colorIdx])),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_doctorDisplayName(doctorName),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                            Text(
                                (app['department'] ?? 'General Specialist')
                                    .toString(),
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.primaryTeal)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Consultation Fee',
                              style: TextStyle(fontSize: 9.5, color: _C.t3)),
                          Text('${_fmtFee(app['consultationFeeSar'])} SAR',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _C.tealDark)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _detailInfoCard(
                  Icons.calendar_month_outlined,
                  'Scheduled Date & Time',
                  _fmtDateFull(scheduledDate),
                  sub: '$timeLabel · ${app['durationMinutes'] ?? 30} min',
                ),
                const SizedBox(height: 10),
                _detailInfoCard(
                  Icons.local_hospital_outlined,
                  'Clinical Assignment',
                  (app['clinicNameEn'] ?? '').toString(),
                  sub: (app['branchNameEn'] ?? '').toString(),
                ),
                const SizedBox(height: 10),
                _detailInfoCard(
                  Icons.person_search_rounded,
                  'Consultation Details',
                  isClinic ? 'In-Clinic Visit' : 'Video Call Session',
                  sub: apptType,
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _C.off,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Reason for Consultation',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: _C.t3)),
                      const SizedBox(height: 6),
                      Text(
                          '"${(app['reason'] ?? '').toString().isNotEmpty ? app['reason'] : 'No specific reasons provided by the patient.'}"',
                          style: const TextStyle(
                              fontSize: 12.5, color: AppTheme.textMain)),
                    ],
                  ),
                ),
                if (isCancelled) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _C.dangerBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 15, color: AppTheme.dangerRed),
                            const SizedBox(width: 6),
                            const Text('Cancellation Information',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.dangerRed,
                                    fontSize: 12.5)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('Status: ${_statusLabel(status)}',
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.dangerRed)),
                        const SizedBox(height: 2),
                        Text(
                            'Reason: ${(app['cancelReason'] ?? '').toString().isNotEmpty ? app['cancelReason'] : 'No reason provided'}',
                            style: const TextStyle(fontSize: 12, color: _C.t3)),
                      ],
                    ),
                  ),
                ],
                if (_hasActions(app)) ...[
                  const SizedBox(height: 16),
                  const Text('Quick Shortcuts',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 8),
                  if (status == 'COMPLETED')
                    _shortcutButton(
                      icon: Icons.star_rounded,
                      label: 'Write Review',
                      color: AppTheme.primaryTeal,
                      onTap: () {
                        Navigator.pop(context);
                        _openReviewModal(app);
                      },
                    ),
                  if (status == 'SCHEDULED' || status == 'CONFIRMED') ...[
                    _shortcutButton(
                      icon: Icons.event_repeat,
                      label: 'Reschedule Visit',
                      color: AppTheme.primaryTeal,
                      onTap: () {
                        Navigator.pop(context);
                        _openReschedule(app);
                      },
                    ),
                    const SizedBox(height: 8),
                    _shortcutButton(
                      icon: Icons.cancel_outlined,
                      label: 'Cancel Appointment',
                      color: AppTheme.dangerRed,
                      outline: true,
                      onTap: () {
                        Navigator.pop(context);
                        _openCancel(app);
                      },
                    ),
                  ],
                  if (app['consultationId'] != null &&
                      (status == 'CONFIRMED' || status == 'COMPLETED')) ...[
                    const SizedBox(height: 8),
                    _shortcutButton(
                      icon: Icons.chat_bubble_outline,
                      label: 'Go to Chat Session',
                      color: AppTheme.primaryTeal,
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/patient/consultations',
                            extra: {'id': app['consultationId']});
                      },
                    ),
                  ],
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailInfoCard(IconData icon, String label, String value,
      {String? sub}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _C.tealLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: AppTheme.primaryTeal),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _C.t3)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                if (sub != null && sub.isNotEmpty)
                  Text(sub,
                      style: const TextStyle(fontSize: 11.5, color: _C.t3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _shortcutButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool outline = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: outline
          ? OutlinedButton.icon(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                  foregroundColor: color, side: BorderSide(color: color)),
              icon: Icon(icon, size: 16),
              label: Text(label),
            )
          : ElevatedButton.icon(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                  backgroundColor: color, foregroundColor: Colors.white),
              icon: Icon(icon, size: 16),
              label: Text(label),
            ),
    );
  }

  // ── CANCEL bottom sheet (mirrors CANCELLATION MODAL DIALOG) ──────────

  void _openCancel(Map<String, dynamic> app) {
    final reasonController = TextEditingController();
    bool touched = false;
    bool submitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16,
              right: 16,
              top: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cancel_outlined,
                        color: AppTheme.dangerRed),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Cancel Appointment',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.dangerRed,
                              fontSize: 16)),
                    ),
                    IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                    'Are you sure you want to cancel your consultation with ${_doctorDisplayName((app['doctorName'] ?? '').toString())}? This action cannot be undone once confirmed.',
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textMain)),
                const SizedBox(height: 14),
                const Text('Reason for Cancellation *',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  maxLength: 255,
                  onChanged: (_) => setModalState(() => touched = true),
                  decoration: const InputDecoration(
                      hintText:
                          'Please tell us why you need to cancel this appointment'),
                ),
                if (touched &&
                    (reasonController.text.trim().isEmpty ||
                        reasonController.text.length > 255))
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Reason is required (max 255 chars).',
                        style: TextStyle(
                            color: AppTheme.dangerRed, fontSize: 11.5)),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Go Back'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.dangerRed,
                            foregroundColor: Colors.white),
                        onPressed: (reasonController.text.trim().isEmpty ||
                                submitting)
                            ? null
                            : () async {
                                setModalState(() => submitting = true);
                                try {
                                  await ref
                                      .read(appointmentServiceProvider)
                                      .cancelAppointment(
                                          app['appointmentId'].toString(), {
                                    'cancelReason': reasonController.text.trim()
                                  });
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Appointment cancelled successfully!')));
                                  }
                                  await _loadAppointments();
                                } catch (_) {
                                  setModalState(() => submitting = false);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Failed to cancel appointment.')));
                                  }
                                }
                              },
                        child: Text(submitting
                            ? 'Cancelling…'
                            : 'Confirm Cancellation'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── RESCHEDULE bottom sheet (mirrors RESCHEDULE MODAL DIALOG) ────────

  void _openReschedule(Map<String, dynamic> app) {
    String bookingDate = DateTime.now().toIso8601String().split('T')[0];
    List<_NextDay> nextDays = [];
    List<dynamic> availableSlots = [];
    dynamic selectedSlot;
    bool isSubmitting = false;
    bool loadingDays = true;
    bool loadingSlots = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> fetchSlots(String date) async {
            setModalState(() => loadingSlots = true);
            try {
              final slots = await ref
                  .read(doctorServiceProvider)
                  .getAvailableSlots(app['dcId'].toString(), date: date);
              availableSlots = slots;
              final firstAvail = availableSlots
                  .cast<dynamic>()
                  .where((s) => s['status'] == 'AVAILABLE')
                  .toList();
              selectedSlot = firstAvail.isNotEmpty ? firstAvail.first : null;
            } catch (_) {
              availableSlots = [];
              selectedSlot = null;
            }
            setModalState(() => loadingSlots = false);
          }

          Future<void> checkAvailability() async {
            setModalState(() => loadingDays = true);
            final today = DateTime.now();
            final dates = <String>[];
            for (var i = 0; i < 7; i++) {
              final d = today.add(Duration(days: i));
              dates.add(
                  '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
            }
            final results = await Future.wait(dates.map((d) async {
              try {
                return await ref
                    .read(doctorServiceProvider)
                    .getAvailableSlots(app['dcId'].toString(), date: d);
              } catch (_) {
                return <dynamic>[];
              }
            }));
            const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
            const monthNames = [
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
            nextDays = List.generate(dates.length, (i) {
              final d = DateTime.parse(dates[i]);
              final avail = results[i]
                  .cast<dynamic>()
                  .where((s) => s['status'] == 'AVAILABLE')
                  .isNotEmpty;
              return _NextDay(
                date: dates[i],
                label: '${d.day} ${monthNames[d.month - 1]}',
                dayName: dayNames[d.weekday % 7],
                hasSlots: avail,
              );
            });
            final firstAvailable = nextDays.where((d) => d.hasSlots).toList();
            bookingDate = firstAvailable.isNotEmpty
                ? firstAvailable.first.date
                : bookingDate;
            setModalState(() => loadingDays = false);
            await fetchSlots(bookingDate);
          }

          if (loadingDays && nextDays.isEmpty) {
            checkAvailability();
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            expand: false,
            builder: (ctx, scrollController) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.event_repeat,
                            color: AppTheme.primaryTeal),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Reschedule Consultation',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close)),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _C.off,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.person_search_rounded,
                                  color: AppTheme.primaryTeal),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        _doctorDisplayName(
                                            (app['doctorName'] ?? '')
                                                .toString()),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13)),
                                    Text((app['clinicNameEn'] ?? '').toString(),
                                        style: const TextStyle(
                                            fontSize: 11.5, color: _C.t3)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Select New Appointment Date *',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 8),
                        if (loadingDays)
                          const Center(
                              child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator()))
                        else
                          SizedBox(
                            height: 66,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: nextDays.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, i) {
                                final day = nextDays[i];
                                final selected = bookingDate == day.date;
                                return GestureDetector(
                                  onTap: () async {
                                    setModalState(() => bookingDate = day.date);
                                    await fetchSlots(bookingDate);
                                  },
                                  child: Container(
                                    width: 64,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? AppTheme.primaryTeal
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: selected
                                              ? AppTheme.primaryTeal
                                              : AppTheme.borderGray),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(day.dayName,
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: selected
                                                    ? Colors.white70
                                                    : _C.t3)),
                                        const SizedBox(height: 2),
                                        Text(day.label,
                                            style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: selected
                                                    ? Colors.white
                                                    : AppTheme.textMain)),
                                        const SizedBox(height: 3),
                                        Container(
                                          width: 5,
                                          height: 5,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: day.hasSlots
                                                ? (selected
                                                    ? Colors.white
                                                    : AppTheme.successGreen)
                                                : Colors.transparent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text('Or choose another date:',
                                style: TextStyle(fontSize: 12, color: _C.t3)),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.tryParse(bookingDate) ??
                                      DateTime.now(),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 180)),
                                );
                                if (picked != null) {
                                  final s =
                                      '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                  setModalState(() => bookingDate = s);
                                  await fetchSlots(s);
                                }
                              },
                              child: Text(bookingDate),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('Available Slots for $bookingDate',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 8),
                        if (loadingSlots)
                          const Center(
                              child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator()))
                        else if (availableSlots.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                                'No open consultation slots available for this date.',
                                style: TextStyle(
                                    fontSize: 12, color: Color(0xFFB45309))),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: availableSlots.map((slot) {
                              final selected = selectedSlot != null &&
                                  selectedSlot['slotId'] == slot['slotId'];
                              final isAvailable = slot['status'] == 'AVAILABLE';
                              final t = (slot['startTime'] ?? '').toString();
                              final label =
                                  t.length >= 5 ? t.substring(0, 5) : t;
                              return GestureDetector(
                                onTap: isAvailable
                                    ? () =>
                                        setModalState(() => selectedSlot = slot)
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 9),
                                  decoration: BoxDecoration(
                                    color: !isAvailable
                                        ? const Color(0xFFF3F4F6)
                                        : (selected
                                            ? AppTheme.primaryTeal
                                            : Colors.white),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: selected
                                            ? AppTheme.primaryTeal
                                            : AppTheme.borderGray),
                                  ),
                                  child: Text(label,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: !isAvailable
                                              ? AppTheme.textMuted
                                              : (selected
                                                  ? Colors.white
                                                  : AppTheme.textMain))),
                                ),
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.successGreen,
                                    foregroundColor: Colors.white),
                                onPressed: (isSubmitting ||
                                        selectedSlot == null)
                                    ? null
                                    : () async {
                                        setModalState(
                                            () => isSubmitting = true);
                                        try {
                                          final bookingDto = {
                                            'dcId': app['dcId'],
                                            'patientId': _patientId,
                                            'slotId': selectedSlot['slotId'],
                                            'appointmentType':
                                                app['appointmentType'],
                                            'sessionType': app['sessionType'],
                                            'reason': (app['reason'] ?? '')
                                                    .toString()
                                                    .isNotEmpty
                                                ? app['reason']
                                                : 'Rescheduled consultation',
                                          };
                                          await ref
                                              .read(appointmentServiceProvider)
                                              .bookAppointment(bookingDto);
                                          try {
                                            await ref
                                                .read(
                                                    appointmentServiceProvider)
                                                .cancelAppointment(
                                                    app['appointmentId']
                                                        .toString(),
                                                    {
                                                  'cancelReason':
                                                      'Rescheduled to new slot on $bookingDate'
                                                });
                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(const SnackBar(
                                                      content: Text(
                                                          'Appointment rescheduled successfully!')));
                                            }
                                          } catch (_) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(const SnackBar(
                                                      content: Text(
                                                          'New slot booked, but failed to cancel the old appointment. Please contact support.')));
                                            }
                                          }
                                          if (ctx.mounted) Navigator.pop(ctx);
                                          await _loadAppointments();
                                        } catch (_) {
                                          setModalState(
                                              () => isSubmitting = false);
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(const SnackBar(
                                                    content: Text(
                                                        'Failed to book the new slot. Reschedule cancelled.')));
                                          }
                                        }
                                      },
                                icon: isSubmitting
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Icon(Icons.check, size: 16),
                                label: Text(isSubmitting
                                    ? 'Processing...'
                                    : 'Confirm Reschedule'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── REVIEW bottom sheet (mirrors REVIEW SUBMISSION MODAL DIALOG) ─────

  void _openReviewModal(Map<String, dynamic> app) {
    int doctorRating = 5;
    int ratingBedside = 5;
    int ratingKnowledge = 5;
    int ratingWait = 5;
    int clinicRating = 5;
    int ratingCleanliness = 5;
    int ratingStaff = 5;
    int clinicRatingWait = 5;
    bool isAnonymous = false;
    bool submitting = false;
    final reviewTextController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Widget ratingDropdown(
              String label, int value, ValueChanged<int?> onChanged,
              {bool small = false}) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: small ? 10.5 : 12,
                        fontWeight: FontWeight.w600,
                        color: _C.t3)),
                const SizedBox(height: 4),
                DropdownButtonFormField<int>(
                  initialValue: value,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                  items: [5, 4, 3, 2, 1]
                      .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(small ? '$v ★' : '${'⭐' * v} ($v/5)')))
                      .toList(),
                  onChanged: onChanged,
                ),
              ],
            );
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            expand: false,
            builder: (ctx, scrollController) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryTeal,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Colors.white),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Rate Your Consultation',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                        ),
                        IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close, color: Colors.white)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                            'Doctor Review: ${_doctorDisplayName((app['doctorName'] ?? '').toString())}',
                            style: const TextStyle(
                                color: AppTheme.primaryTeal,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 10),
                        ratingDropdown(
                            'Overall Doctor Rating (1-5) *',
                            doctorRating,
                            (v) => setModalState(() => doctorRating = v ?? 5)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                                child: ratingDropdown(
                                    'Bedside *',
                                    ratingBedside,
                                    (v) => setModalState(
                                        () => ratingBedside = v ?? 5),
                                    small: true)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: ratingDropdown(
                                    'Knowledge *',
                                    ratingKnowledge,
                                    (v) => setModalState(
                                        () => ratingKnowledge = v ?? 5),
                                    small: true)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: ratingDropdown(
                                    'Wait Time *',
                                    ratingWait,
                                    (v) => setModalState(
                                        () => ratingWait = v ?? 5),
                                    small: true)),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Divider(),
                        const SizedBox(height: 6),
                        Text(
                            'Clinic Review: ${(app['clinicNameEn'] ?? '').toString()}',
                            style: const TextStyle(
                                color: AppTheme.primaryTeal,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 10),
                        ratingDropdown(
                            'Overall Clinic Rating (1-5) *',
                            clinicRating,
                            (v) => setModalState(() => clinicRating = v ?? 5)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                                child: ratingDropdown(
                                    'Cleanliness *',
                                    ratingCleanliness,
                                    (v) => setModalState(
                                        () => ratingCleanliness = v ?? 5),
                                    small: true)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: ratingDropdown(
                                    'Staff *',
                                    ratingStaff,
                                    (v) => setModalState(
                                        () => ratingStaff = v ?? 5),
                                    small: true)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: ratingDropdown(
                                    'Wait Time *',
                                    clinicRatingWait,
                                    (v) => setModalState(
                                        () => clinicRatingWait = v ?? 5),
                                    small: true)),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Text('Written Feedback (Optional)',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: reviewTextController,
                          maxLines: 3,
                          maxLength: 2000,
                          decoration: const InputDecoration(
                              hintText: 'Share details of your experience...'),
                        ),
                        Row(
                          children: [
                            Checkbox(
                              value: isAnonymous,
                              onChanged: (v) =>
                                  setModalState(() => isAnonymous = v ?? false),
                            ),
                            const Expanded(
                                child: Text('Submit this review anonymously',
                                    style: TextStyle(fontSize: 13))),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: submitting
                                    ? null
                                    : () async {
                                        setModalState(() => submitting = true);
                                        try {
                                          final doctorReviewReq = {
                                            'doctorId': app['doctorId'],
                                            'appointmentId':
                                                app['appointmentId'],
                                            'rating': doctorRating,
                                            'ratingBedside': ratingBedside,
                                            'ratingKnowledge': ratingKnowledge,
                                            'ratingWait': ratingWait,
                                            'reviewText':
                                                reviewTextController.text,
                                            'isAnonymous': isAnonymous,
                                          };
                                          await ref
                                              .read(reviewServiceProvider)
                                              .submitDoctorReview(
                                                  doctorReviewReq);
                                          if (app['clinicId'] != null) {
                                            final clinicReviewReq = {
                                              'clinicId': app['clinicId'],
                                              'appointmentId':
                                                  app['appointmentId'],
                                              'rating': clinicRating,
                                              'ratingCleanliness':
                                                  ratingCleanliness,
                                              'ratingStaff': ratingStaff,
                                              'ratingWait': clinicRatingWait,
                                              'reviewText':
                                                  reviewTextController.text,
                                              'isAnonymous': isAnonymous,
                                            };
                                            await ref
                                                .read(reviewServiceProvider)
                                                .submitClinicReview(
                                                    clinicReviewReq);
                                          }
                                          if (ctx.mounted) Navigator.pop(ctx);
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(const SnackBar(
                                                    content: Text(
                                                        'Thank you! Your reviews have been submitted successfully.')));
                                          }
                                          await _loadAppointments();
                                        } catch (_) {
                                          setModalState(
                                              () => submitting = false);
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(const SnackBar(
                                                    content: Text(
                                                        'Failed to submit reviews. Please try again.')));
                                          }
                                        }
                                      },
                                icon: const Icon(Icons.star, size: 16),
                                label: Text(submitting
                                    ? 'Submitting…'
                                    : 'Submit Feedback'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

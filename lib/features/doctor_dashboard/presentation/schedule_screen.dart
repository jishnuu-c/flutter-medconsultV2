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

  @override
  void initState() {
    super.initState();
    _loadSchedule();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load schedule: ${_errorMessage(e)}')),
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

  Future<void> _changeStatus(String appointmentId, String newStatus) async {
    setState(() => _isLoading = true);
    try {
      await ref
          .read(appointmentServiceProvider)
          .updateStatus(appointmentId, {'status': newStatus});
      await _loadSchedule();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to update status: ${_errorMessage(e)}')),
        );
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static const List<String> _months = [
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

  // Mirrors Angular's `date:'mediumDate'` pipe (e.g. "Jul 28, 2026").
  String _mediumDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final d = DateTime.parse(raw);
      return '${_months[d.month - 1]} ${d.day}, ${d.year}';
    } catch (_) {
      return raw;
    }
  }

  Color _statusBadgeColor(String status) {
    switch (status) {
      case 'CONFIRMED':
      case 'COMPLETED':
        return AppTheme.successGreen;
      case 'SCHEDULED':
        return AppTheme.warningAmber;
      case 'CANCELLED':
      case 'NO_SHOW':
        return AppTheme.dangerRed;
      default:
        return AppTheme.textMuted;
    }
  }

  bool _isMobile(BuildContext c) => MediaQuery.of(c).size.width < 600;

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile(context);
    return Scaffold(
      body: Container(
        padding: EdgeInsets.all(mobile ? 12 : 24),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header card ──────────────────────────────────
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(mobile ? 16 : 24),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.start,
                          runSpacing: 10,
                          children: [
                            SizedBox(
                              width: mobile
                                  ? MediaQuery.of(context).size.width -
                                      12 * 2 -
                                      16 * 2
                                  : 400,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '🗓️ Doctor Consultation Schedule',
                                    style: TextStyle(
                                        fontSize: mobile ? 17 : 20,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primaryTeal),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Clinical timeline of patient appointments for today',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            ),
                            Chip(
                              label: Text(
                                  'Total Scheduled: ${_appointments.length}'),
                              backgroundColor: AppTheme.primaryLightTeal,
                              labelStyle: const TextStyle(
                                  color: AppTheme.primaryDarkTeal,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Timeline list ─────────────────────────────────
                    if (_appointments.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(32),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceWhite,
                          border: Border.all(color: AppTheme.borderGray),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'No patient consultations scheduled for today.',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      )
                    else
                      Column(
                        children: List.generate(_appointments.length, (i) {
                          final apt = _appointments[i];
                          final status = apt['status'] ?? 'SCHEDULED';
                          final startTime = (apt['startTime'] as String?) ?? '';
                          final timeLabel = startTime.length >= 5
                              ? startTime.substring(0, 5)
                              : startTime;
                          final sessionType =
                              (apt['sessionType'] as String? ?? '')
                                  .replaceAll('_', ' ');
                          final isCurrentActive =
                              status == 'CONFIRMED' || i == 0;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                                horizontal: mobile ? 14 : 24,
                                vertical: mobile ? 14 : 18),
                            decoration: BoxDecoration(
                              color: isCurrentActive
                                  ? AppTheme.primaryLightTeal
                                  : AppTheme.surfaceWhite,
                              border: Border(
                                left: BorderSide(
                                  color: isCurrentActive
                                      ? AppTheme.primaryTeal
                                      : AppTheme.borderGray,
                                  width: isCurrentActive ? 5 : 1,
                                ),
                                top: BorderSide(color: AppTheme.borderGray),
                                right: BorderSide(color: AppTheme.borderGray),
                                bottom: BorderSide(color: AppTheme.borderGray),
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 16,
                              runSpacing: 12,
                              children: [
                                // Time slot badge
                                Text(
                                  '⏰ $timeLabel',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppTheme.primaryTeal),
                                ),

                                // Patient info
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      alignment: Alignment.center,
                                      decoration: const BoxDecoration(
                                        color: AppTheme.primaryLightTeal,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Text('👤',
                                          style: TextStyle(fontSize: 18)),
                                    ),
                                    const SizedBox(width: 14),
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: mobile
                                            ? MediaQuery.of(context)
                                                    .size
                                                    .width -
                                                12 * 2 -
                                                14 * 2 -
                                                44 -
                                                14
                                            : 260,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            apt['patientName'] ?? 'Patient',
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                color: AppTheme.textMain),
                                          ),
                                          Text(
                                            'Date: ${_mediumDate(apt['scheduledDate'] as String?)} | Mode: $sessionType',
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 2,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: AppTheme.textMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                // Status + actions
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _statusBadgeColor(status)
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: _statusBadgeColor(status)),
                                      ),
                                    ),
                                    if (status == 'SCHEDULED')
                                      ElevatedButton(
                                        onPressed: () => _changeStatus(
                                            apt['appointmentId'], 'CONFIRMED'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryTeal,
                                          foregroundColor: Colors.white,
                                        ),
                                        child:
                                            const Text('▶ Start Consultation'),
                                      ),
                                    if (status == 'CONFIRMED')
                                      ElevatedButton(
                                        onPressed: () => _changeStatus(
                                            apt['appointmentId'], 'COMPLETED'),
                                        child: const Text('✓ Mark Complete'),
                                      ),
                                    if (status == 'CONFIRMED' ||
                                        status == 'SCHEDULED')
                                      OutlinedButton(
                                        onPressed: () => _changeStatus(
                                            apt['appointmentId'], 'NO_SHOW'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppTheme.dangerRed,
                                          side: const BorderSide(
                                              color: AppTheme.dangerRed),
                                        ),
                                        child: const Text('No Show'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

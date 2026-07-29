import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/clinic_service.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../clinic_admin/data/doctor_models.dart';
import '../../doctor_dashboard/data/appointment_service.dart';
import '../data/patient_service.dart';

class BookAppointmentScreen extends ConsumerStatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  ConsumerState<BookAppointmentScreen> createState() =>
      _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends ConsumerState<BookAppointmentScreen> {
  final _reasonController = TextEditingController();
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _needProfileInit = false;

  String? _patientId;
  List<dynamic> _doctors = [];
  List<DoctorClinicModel> _doctorClinics = [];
  List<dynamic> _slots = [];

  String? _selectedDoctorId;
  String? _selectedDcId;
  DateTime? _selectedDate;
  String? _selectedSlotId;
  String _selectedApptType = 'NEW_PATIENT';
  String _selectedSessionType = 'IN_CLINIC';

  static const _appointmentTypes = [
    'FOLLOW_UP',
    'NEW_PATIENT',
    'REFERRAL',
    'EMERGENCY'
  ];
  static const _sessionTypes = ['IN_CLINIC', 'VIRTUAL', 'BOTH'];

  @override
  void initState() {
    super.initState();
    _checkProfileAndLoad();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _checkProfileAndLoad() async {
    setState(() => _isLoading = true);
    try {
      final profile = await ref.read(patientServiceProvider).getMyProfile();
      _patientId = profile['patientId'];
      await _loadDoctors();
    } catch (e) {
      final status = e is DioException ? e.response?.statusCode : null;
      if (status == 404) {
        setState(() => _needProfileInit = true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDoctors() async {
    final res = await ref.read(doctorServiceProvider).getAllDoctors();
    if (mounted) setState(() => _doctors = res);
  }

  // Mirrors book-appointment.component.ts's onDoctorChange: fetch the
  // doctor's active clinic placements, then enrich each with clinic +
  // branch display names (the doctor-clinics endpoint only returns ids).
  Future<void> _onDoctorChange(String? docId) async {
    setState(() {
      _selectedDoctorId = docId;
      _doctorClinics = [];
      _slots = [];
      _selectedDcId = null;
      _selectedDate = null;
      _selectedSlotId = null;
    });
    if (docId == null) return;
    setState(() => _isLoading = true);
    try {
      final clinics =
          await ref.read(doctorServiceProvider).getDoctorClinics(docId);
      final activeClinics = clinics.where((c) => c.isActive).toList();
      if (activeClinics.isEmpty) {
        if (mounted) setState(() => _doctorClinics = []);
        return;
      }
      final clinicService = ref.read(clinicServiceProvider);
      final enriched = <DoctorClinicModel>[];
      for (final dc in activeClinics) {
        try {
          final detail = await clinicService.getClinicDetail(dc.clinicId);
          final branch =
              detail.branches.where((b) => b.branchId == dc.branchId).toList();
          enriched.add(DoctorClinicModel(
            dcId: dc.dcId,
            doctorId: dc.doctorId,
            clinicId: dc.clinicId,
            branchId: dc.branchId,
            department: dc.department,
            consultationFeeSar: dc.consultationFeeSar,
            isPrimary: dc.isPrimary,
            startDate: dc.startDate,
            endDate: dc.endDate,
            isActive: dc.isActive,
            clinicNameEn: detail.nameEn,
            branchNameEn: branch.isNotEmpty
                ? branch.first.branchNameEn
                : 'Unknown Branch',
          ));
        } catch (_) {
          enriched.add(dc);
        }
      }
      if (mounted) setState(() => _doctorClinics = enriched);
    } catch (_) {
      if (mounted) setState(() => _doctorClinics = []);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onClinicOrDateChange() async {
    setState(() {
      _slots = [];
      _selectedSlotId = null;
    });
    if (_selectedDcId == null || _selectedDate == null) return;
    setState(() => _isLoading = true);
    try {
      final dateStr =
          '${_selectedDate!.year.toString().padLeft(4, '0')}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
      final slots = await ref
          .read(doctorServiceProvider)
          .getAvailableSlots(_selectedDcId!, date: dateStr);
      if (mounted) {
        setState(() =>
            _slots = slots.where((s) => s['status'] == 'AVAILABLE').toList());
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _onClinicOrDateChange();
    }
  }

  bool get _canSubmit =>
      _patientId != null &&
      _selectedDcId != null &&
      _selectedSlotId != null &&
      _selectedDate != null;

  Future<void> _confirmBooking() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);

    final dateStr =
        '${_selectedDate!.year.toString().padLeft(4, '0')}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';

    try {
      await ref.read(appointmentServiceProvider).bookAppointment({
        'patientId': _patientId,
        'dcId': _selectedDcId,
        'slotId': _selectedSlotId,
        'appointmentType': _selectedApptType,
        'scheduledDate': dateStr,
        'sessionType': _selectedSessionType,
        'reason': _reasonController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Appointment booked successfully!')),
        );
        context.go('/patient/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_extractErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // Mirrors book-appointment.component.ts's onSubmit error branch: the
  // backend error body can be a plain string, a {message} object, or a
  // Spring validation {errors:[...]} array — unwrap whichever shape shows up.
  String _extractErrorMessage(Object e) {
    if (e is! DioException) return 'Failed to book appointment.';
    final data = e.response?.data;
    if (data == null) return 'Failed to book appointment.';
    if (data is String) return data;
    if (data is Map) {
      if (data['message'] != null) return data['message'].toString();
      if (data['errors'] is List) {
        final errors = data['errors'] as List;
        return errors
            .map((er) =>
                er is Map ? (er['defaultMessage'] ?? er['message'] ?? er) : er)
            .join(', ');
      }
    }
    return 'Failed to book appointment.';
  }

  String _titleLabel(DoctorTitle t) {
    switch (t) {
      case DoctorTitle.DR:
        return 'Dr';
      case DoctorTitle.PROF:
        return 'Prof';
      case DoctorTitle.ASSOC_PROF:
        return 'Assoc Prof';
    }
  }

  String _fmtFee(double fee) => fee == fee.roundToDouble()
      ? fee.toInt().toString()
      : fee.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    if (_needProfileInit) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'Please initialize your patient profile before booking an appointment.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.go('/patient/profile'),
                  child: const Text('Setup Profile'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('📅 Schedule Your Consultation',
                        style: TextStyle(
                            fontSize: isMobile ? 20 : 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textMain)),
                    const SizedBox(height: 4),
                    const Text(
                        'Follow the steps below to choose your doctor, date, and time slot',
                        style:
                            TextStyle(fontSize: 14, color: AppTheme.textMuted)),
                  ],
                ),
                Chip(
                    label: const Text('🇸🇦 MOH Verified Network'),
                    backgroundColor: AppTheme.primaryLightTeal),
              ],
            ),
            const SizedBox(height: 16),
            _buildStepFlowBar(isMobile),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 16 : 24),
                child: (_isLoading && _doctors.isEmpty)
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Step 1: Choose Specialist Doctor *',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            key: const Key('book_doctor_dropdown'),
                            initialValue: _selectedDoctorId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: '-- Select Specialist Doctor --'),
                            items: _doctors.map((doc) {
                              final title = _titleLabel(doc.title);
                              final fee = _fmtFee(doc.consultationFeeSar);
                              return DropdownMenuItem<String>(
                                value: doc.doctorId,
                                child: Text(
                                  '👨‍⚕️ $title. ${doc.fullName} (${doc.experienceYears} yrs exp - Standard Fee: SAR $fee)',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: _onDoctorChange,
                          ),
                          if (_selectedDoctorId != null) ...[
                            const SizedBox(height: 24),
                            const Text('Step 2: Select Clinic Location *',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              key: const Key('book_clinic_dropdown'),
                              initialValue: _selectedDcId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: '-- Choose Clinic Location --'),
                              items: _doctorClinics.map((c) {
                                final fee = _fmtFee(c.consultationFeeSar);
                                return DropdownMenuItem<String>(
                                  value: c.dcId,
                                  child: Text(
                                    '🏥 ${c.clinicNameEn ?? c.department} - ${c.branchNameEn ?? ''} (SAR $fee)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedDcId = val;
                                  _selectedDate = null;
                                  _slots = [];
                                  _selectedSlotId = null;
                                });
                              },
                            ),
                            if (_doctorClinics.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text(
                                    'No active clinic branch locations assigned to this doctor.',
                                    style: TextStyle(
                                        color: AppTheme.warningAmber,
                                        fontSize: 12)),
                              ),
                          ],
                          if (_selectedDcId != null) ...[
                            const SizedBox(height: 24),
                            const Text('Step 3: Choose Appointment Date *',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(_selectedDate == null
                                  ? 'Choose a date'
                                  : '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'),
                              onPressed: _pickDate,
                            ),
                          ],
                          if (_selectedDate != null &&
                              _selectedDcId != null) ...[
                            const SizedBox(height: 24),
                            const Text('Step 4: Select Available Time Slot *',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 12),
                            if (_slots.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: AppTheme.borderGray,
                                      style: BorderStyle.solid),
                                  borderRadius: BorderRadius.circular(8),
                                  color: AppTheme.backgroundApp,
                                ),
                                child: const Text(
                                  'No available time slots found for the selected date. Please pick another date.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppTheme.textMuted),
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _slots.map((slot) {
                                  final id = slot['slotId'];
                                  final isSelected = _selectedSlotId == id;
                                  final startTime =
                                      (slot['startTime'] ?? '').toString();
                                  final label = startTime.length >= 5
                                      ? startTime.substring(0, 5)
                                      : startTime;
                                  return ChoiceChip(
                                    label:
                                        Text(isSelected ? '$label ✓' : label),
                                    selected: isSelected,
                                    selectedColor: AppTheme.primaryTeal,
                                    labelStyle: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : AppTheme.textMain),
                                    onSelected: (val) {
                                      if (val)
                                        setState(() => _selectedSlotId = id);
                                    },
                                  );
                                }).toList(),
                              ),
                          ],
                          if (_selectedSlotId != null) ...[
                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 12),
                            const Text('Step 5: Confirm & Finalize Details',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: AppTheme.primaryTeal)),
                            const SizedBox(height: 16),
                            LayoutBuilder(builder: (context, constraints) {
                              final stacked = constraints.maxWidth < 480;
                              final typeField = DropdownButtonFormField<String>(
                                initialValue: _selectedApptType,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Appointment Type *'),
                                items: _appointmentTypes
                                    .map((t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(t.replaceAll('_', ' '))))
                                    .toList(),
                                onChanged: (v) => setState(() =>
                                    _selectedApptType = v ?? _selectedApptType),
                              );
                              final sessionField =
                                  DropdownButtonFormField<String>(
                                initialValue: _selectedSessionType,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Session Mode *'),
                                items: _sessionTypes
                                    .map((t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(t.replaceAll('_', ' '))))
                                    .toList(),
                                onChanged: (v) => setState(() =>
                                    _selectedSessionType =
                                        v ?? _selectedSessionType),
                              );
                              if (stacked) {
                                return Column(children: [
                                  typeField,
                                  const SizedBox(height: 16),
                                  sessionField
                                ]);
                              }
                              return Row(children: [
                                Expanded(child: typeField),
                                const SizedBox(width: 16),
                                Expanded(child: sessionField),
                              ]);
                            }),
                            const SizedBox(height: 16),
                            const Text('Reason for Visit / Symptoms (Optional)',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _reasonController,
                              maxLines: 3,
                              maxLength: 255,
                              decoration: const InputDecoration(
                                  hintText:
                                      'Briefly describe your symptoms or visit reason...'),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                key: const Key('confirm_booking_btn'),
                                onPressed: (_isSubmitting || !_canSubmit)
                                    ? null
                                    : _confirmBooking,
                                child: _isSubmitting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Text(
                                        'Confirm & Book Appointment →'),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mirrors book-appointment.component.html's step-flow-bar. Wraps to two
  // rows on narrow screens instead of squeezing 5 steps into one line.
  Widget _buildStepFlowBar(bool isMobile) {
    final steps = <Map<String, dynamic>>[
      {'label': 'Doctor', 'completed': _selectedDoctorId != null},
      {'label': 'Clinic', 'completed': _selectedDcId != null},
      {'label': 'Date', 'completed': _selectedDate != null},
      {'label': 'Slot', 'completed': _selectedSlotId != null},
      {'label': 'Confirm', 'completed': false},
    ];
    return Wrap(
      spacing: isMobile ? 6 : 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: steps[i]['completed'] == true
                    ? AppTheme.primaryTeal
                    : AppTheme.borderGray,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      color: steps[i]['completed'] == true
                          ? Colors.white
                          : AppTheme.textMuted),
                ),
              ),
              const SizedBox(width: 6),
              Text(steps[i]['label'] as String,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
          if (i != steps.length - 1)
            const Text('›', style: TextStyle(color: AppTheme.textMuted)),
        ],
      ],
    );
  }
}

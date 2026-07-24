import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../doctor_dashboard/data/appointment_service.dart';
import '../data/patient_service.dart';

class BookAppointmentScreen extends ConsumerStatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  ConsumerState<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends ConsumerState<BookAppointmentScreen> {
  final _reasonController = TextEditingController();
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _needProfileInit = false;

  String? _patientId;
  List<dynamic> _doctors = [];
  List<dynamic> _doctorClinics = [];
  List<dynamic> _slots = [];

  String? _selectedDoctorId;
  String? _selectedDcId;
  DateTime? _selectedDate;
  String? _selectedSlotId;
  String _selectedApptType = 'NEW_PATIENT';
  String _selectedSessionType = 'IN_CLINIC';

  static const _appointmentTypes = ['FOLLOW_UP', 'NEW_PATIENT', 'REFERRAL', 'EMERGENCY'];
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

  Future<void> _onDoctorChange(String? docId) async {
    setState(() {
      _selectedDoctorId = docId;
      _doctorClinics = [];
      _slots = [];
      _selectedDcId = null;
      _selectedSlotId = null;
    });
    if (docId == null) return;
    setState(() => _isLoading = true);
    try {
      final clinics = await ref.read(doctorServiceProvider).getDoctorClinics(docId);
      if (mounted) {
        setState(() => _doctorClinics = clinics.where((c) => c.isActive).toList());
      }
    } catch (_) {
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
      final slots = await ref.read(doctorServiceProvider).getAvailableSlots(_selectedDcId!, date: dateStr);
      if (mounted) {
        setState(() => _slots = slots.where((s) => s['status'] == 'AVAILABLE').toList());
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
      _patientId != null && _selectedDcId != null && _selectedSlotId != null && _selectedDate != null;

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
      final msg = e is DioException ? (e.response?.data?['message'] ?? 'Failed to book appointment.') : 'Failed to book appointment.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.toString())));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

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
                const Text('Please initialize your patient profile before booking an appointment.',
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

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Book an Appointment',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textMain),
            ),
            const SizedBox(height: 4),
            const Text(
              'Select a doctor, choose your preferred session type, and reserve a consultation slot.',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 24),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: (_isLoading && _doctors.isEmpty)
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('1. Select Doctor / Specialist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            key: const Key('book_doctor_dropdown'),
                            initialValue: _selectedDoctorId,
                            decoration: const InputDecoration(labelText: 'Choose Doctor'),
                            items: _doctors.map((doc) {
                              return DropdownMenuItem<String>(
                                value: doc.doctorId,
                                child: Text('${doc.fullName} • ${doc.experienceYears} yrs exp'),
                              );
                            }).toList(),
                            onChanged: _onDoctorChange,
                          ),
                          const SizedBox(height: 24),

                          const Text('2. Select Clinic', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            key: const Key('book_clinic_dropdown'),
                            initialValue: _selectedDcId,
                            decoration: const InputDecoration(labelText: 'Choose Clinic'),
                            items: _doctorClinics.map((c) {
                              return DropdownMenuItem<String>(
                                value: c.dcId,
                                child: Text(c.clinicNameEn ?? c.department),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() => _selectedDcId = val);
                              _onClinicOrDateChange();
                            },
                          ),
                          const SizedBox(height: 24),

                          const Text('3. Session Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            children: _sessionTypes.map((t) {
                              return ChoiceChip(
                                label: Text(t.replaceAll('_', ' ')),
                                selected: _selectedSessionType == t,
                                selectedColor: AppTheme.primaryTeal,
                                labelStyle: TextStyle(color: _selectedSessionType == t ? Colors.white : AppTheme.textMain),
                                onSelected: (_) => setState(() => _selectedSessionType = t),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),

                          const Text('4. Appointment Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: _appointmentTypes.map((t) {
                              return ChoiceChip(
                                label: Text(t.replaceAll('_', ' ')),
                                selected: _selectedApptType == t,
                                selectedColor: AppTheme.primaryTeal,
                                labelStyle: TextStyle(color: _selectedApptType == t ? Colors.white : AppTheme.textMain),
                                onSelected: (_) => setState(() => _selectedApptType = t),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),

                          const Text('5. Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text(_selectedDate == null
                                ? 'Choose a date'
                                : '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}'),
                            onPressed: _pickDate,
                          ),
                          const SizedBox(height: 24),

                          const Text('6. Available Consultation Slot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          if (_slots.isEmpty)
                            const Text('No slots loaded yet. Select clinic and date above.', style: TextStyle(color: AppTheme.textMuted))
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _slots.map((slot) {
                                final id = slot['slotId'];
                                final isSelected = _selectedSlotId == id;
                                final label = '${(slot['startTime'] ?? '').toString().substring(0, (slot['startTime'] ?? '').toString().length >= 5 ? 5 : (slot['startTime'] ?? '').toString().length)}';
                                return ChoiceChip(
                                  label: Text(label),
                                  selected: isSelected,
                                  selectedColor: AppTheme.primaryTeal,
                                  labelStyle: TextStyle(color: isSelected ? Colors.white : AppTheme.textMain),
                                  onSelected: (val) {
                                    if (val) setState(() => _selectedSlotId = id);
                                  },
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 24),

                          const Text('7. Reason for Visit (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _reasonController,
                            maxLines: 3,
                            maxLength: 255,
                            decoration: const InputDecoration(hintText: 'Describe symptoms or consultation purpose...'),
                          ),
                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              key: const Key('confirm_booking_btn'),
                              onPressed: (_isSubmitting || !_canSubmit) ? null : _confirmBooking,
                              child: _isSubmitting
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('Confirm & Book Appointment'),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

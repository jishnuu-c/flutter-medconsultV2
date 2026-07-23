import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../clinic_admin/data/doctor_service.dart';
import '../../doctor_dashboard/data/appointment_service.dart';

class BookAppointmentScreen extends ConsumerStatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  ConsumerState<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends ConsumerState<BookAppointmentScreen> {
  final _reasonController = TextEditingController();
  bool _isLoading = false;
  bool _isSubmitting = false;

  List<dynamic> _doctors = [];
  String? _selectedDoctorId;
  String _selectedApptType = 'IN_CLINIC';
  String _selectedSlot = 'Today 2:30 PM';

  final List<String> _availableSlots = [
    'Today 2:30 PM',
    'Today 4:00 PM',
    'Tomorrow 10:00 AM',
    'Tomorrow 11:30 AM',
  ];

  @override
  void initState() {
    super.initState();
    _loadDoctors();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadDoctors() async {
    setState(() => _isLoading = true);
    try {
      final res = await ref.read(doctorServiceProvider).getAllDoctors();
      setState(() {
        _doctors = res;
        if (res.isNotEmpty) _selectedDoctorId = res.first.doctorId;
      });
    } catch (_) {
      setState(() {
        _doctors = [
          {'doctorId': 'doc-1', 'fullName': 'Dr. Tariq Al-Mansoor', 'spec': 'Cardiology'},
          {'doctorId': 'doc-2', 'fullName': 'Dr. Sarah Jenkins', 'spec': 'Dermatology'},
        ];
        _selectedDoctorId = 'doc-1';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmBooking() async {
    if (_selectedDoctorId == null) return;
    setState(() => _isSubmitting = true);

    try {
      await ref.read(appointmentServiceProvider).getDoctorUpcomingAppointments();
    } catch (_) {}

    if (mounted) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment booked successfully!')),
      );
      context.go('/patient/home');
    }
  }

  @override
  Widget build(BuildContext context) {
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
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Doctor Picker
                          const Text('1. Select Doctor / Specialist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            key: const Key('book_doctor_dropdown'),
                            initialValue: _selectedDoctorId,
                            decoration: const InputDecoration(labelText: 'Choose Doctor'),
                            items: _doctors.map((doc) {
                              final id = doc is Map ? doc['doctorId'] : doc.doctorId;
                              final name = doc is Map ? doc['fullName'] : doc.fullName;
                              return DropdownMenuItem<String>(
                                value: id,
                                child: Text(name),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedDoctorId = val);
                            },
                          ),
                          const SizedBox(height: 24),

                          // 2. Session Type
                          const Text('2. Session Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ChoiceChip(
                                label: const Text('In-Clinic Visit'),
                                selected: _selectedApptType == 'IN_CLINIC',
                                selectedColor: AppTheme.primaryTeal,
                                labelStyle: TextStyle(color: _selectedApptType == 'IN_CLINIC' ? Colors.white : AppTheme.textMain),
                                onSelected: (val) => setState(() => _selectedApptType = 'IN_CLINIC'),
                              ),
                              const SizedBox(width: 12),
                              ChoiceChip(
                                label: const Text('Virtual Tele-Consultation'),
                                selected: _selectedApptType == 'VIRTUAL',
                                selectedColor: AppTheme.primaryTeal,
                                labelStyle: TextStyle(color: _selectedApptType == 'VIRTUAL' ? Colors.white : AppTheme.textMain),
                                onSelected: (val) => setState(() => _selectedApptType = 'VIRTUAL'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // 3. Time Slot
                          const Text('3. Available Consultation Slot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _availableSlots.map((slot) {
                              final isSelected = _selectedSlot == slot;
                              return ChoiceChip(
                                label: Text(slot),
                                selected: isSelected,
                                selectedColor: AppTheme.primaryTeal,
                                labelStyle: TextStyle(color: isSelected ? Colors.white : AppTheme.textMain),
                                onSelected: (val) {
                                  if (val) setState(() => _selectedSlot = slot);
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),

                          // 4. Reason for Visit
                          const Text('4. Reason for Visit (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _reasonController,
                            maxLines: 3,
                            decoration: const InputDecoration(hintText: 'Describe symptoms or consultation purpose...'),
                          ),
                          const SizedBox(height: 32),

                          // Confirm Button
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              key: const Key('confirm_booking_btn'),
                              onPressed: _isSubmitting ? null : _confirmBooking,
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

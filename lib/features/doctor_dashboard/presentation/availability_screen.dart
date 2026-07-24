import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';

class DoctorAvailabilityScreen extends ConsumerStatefulWidget {
  const DoctorAvailabilityScreen({super.key});

  @override
  ConsumerState<DoctorAvailabilityScreen> createState() => _DoctorAvailabilityScreenState();
}

class _DoctorAvailabilityScreenState extends ConsumerState<DoctorAvailabilityScreen> {
  final days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  final Map<int, bool> _activeDays = {0: true, 1: true, 2: true, 3: true, 4: true, 5: false, 6: false};
  final Map<int, String> _startTimes = {0: '09:00 AM', 1: '09:00 AM', 2: '09:00 AM', 3: '09:00 AM', 4: '09:00 AM'};
  final Map<int, String> _endTimes = {0: '05:00 PM', 1: '05:00 PM', 2: '05:00 PM', 3: '05:00 PM', 4: '05:00 PM'};

  bool _isSaving = false;

  void _saveAvailability() {
    setState(() => _isSaving = true);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Availability schedule saved successfully.')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Availability & Time Slots',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Configure your weekly recurring consultation hours and slot durations.',
                  style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Save Schedule'),
                    onPressed: _isSaving ? null : _saveAvailability,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Expanded(
              child: Card(
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: 7,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final dayName = days[index];
                    final isActive = _activeDays[index] ?? false;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Switch(
                                value: isActive,
                                onChanged: (val) => setState(() => _activeDays[index] = val),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                dayName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isActive ? AppTheme.textMain : AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                          if (isActive) ...[
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.only(left: 56),
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  Text(
                                    'Hours: ${_startTimes[index] ?? "09:00 AM"} - ${_endTimes[index] ?? "05:00 PM"}',
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                  OutlinedButton(
                                    onPressed: () {},
                                    child: const Text('Edit Hours'),
                                  ),
                                ],
                              ),
                            ),
                          ] else
                            const Padding(
                              padding: EdgeInsets.only(left: 56),
                              child: Text('Unavailable / Off', style: TextStyle(color: AppTheme.textMuted)),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

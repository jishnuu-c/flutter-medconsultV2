import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/patient_service.dart';

class PatientHealthProfileScreen extends ConsumerStatefulWidget {
  const PatientHealthProfileScreen({super.key});

  @override
  ConsumerState<PatientHealthProfileScreen> createState() => _PatientHealthProfileScreenState();
}

class _PatientHealthProfileScreenState extends ConsumerState<PatientHealthProfileScreen> {
  final _heightController = TextEditingController(text: '175');
  final _weightController = TextEditingController(text: '72');
  final _bpController = TextEditingController(text: '120/80');

  List<dynamic> _allergies = [];
  List<dynamic> _chronicConditions = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _bpController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final pService = ref.read(patientServiceProvider);
      final allergiesRes = await pService.getMyAllergies();
      final conditionsRes = await pService.getMyChronicConditions();
      setState(() {
        _allergies = allergiesRes;
        _chronicConditions = conditionsRes;
      });
    } catch (_) {
      _populateMockHealthData();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateMockHealthData() {
    _allergies = [
      {'id': 'alg-1', 'allergen': 'Penicillin', 'severity': 'HIGH', 'reaction': 'Skin rash and hives'},
    ];
    _chronicConditions = [
      {'id': 'cc-1', 'conditionName': 'Hypertension', 'diagnosedYear': 2021, 'status': 'MANAGED'},
    ];
  }

  void _openAddAllergyDialog() {
    final allergenController = TextEditingController();
    final reactionController = TextEditingController();
    String severity = 'HIGH';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Known Allergy'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: allergenController, decoration: const InputDecoration(labelText: 'Allergen (e.g. Penicillin)')),
                const SizedBox(height: 12),
                TextField(controller: reactionController, decoration: const InputDecoration(labelText: 'Reaction')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: severity,
                  decoration: const InputDecoration(labelText: 'Severity'),
                  items: const [
                    DropdownMenuItem(value: 'MILD', child: Text('MILD')),
                    DropdownMenuItem(value: 'MODERATE', child: Text('MODERATE')),
                    DropdownMenuItem(value: 'HIGH', child: Text('HIGH')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => severity = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await ref.read(patientServiceProvider).addAllergy({
                    'allergen': allergenController.text.trim(),
                    'reaction': reactionController.text.trim(),
                    'severity': severity,
                  });
                } catch (_) {}
                if (mounted) Navigator.pop(ctx);
                _loadData();
              },
              child: const Text('Add Allergy'),
            ),
          ],
        ),
      ),
    );
  }

  void _openAddConditionDialog() {
    final conditionController = TextEditingController();
    final yearController = TextEditingController(text: '2023');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Chronic Condition'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: conditionController, decoration: const InputDecoration(labelText: 'Condition Name')),
              const SizedBox(height: 12),
              TextField(controller: yearController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Diagnosed Year')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(patientServiceProvider).addChronicCondition({
                  'conditionName': conditionController.text.trim(),
                  'diagnosedYear': int.tryParse(yearController.text) ?? 2023,
                  'status': 'MANAGED',
                });
              } catch (_) {}
              if (mounted) Navigator.pop(ctx);
              _loadData();
            },
            child: const Text('Add Condition'),
          ),
        ],
      ),
    );
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
              'Personal Health Metrics & History',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textMain),
            ),
            const SizedBox(height: 4),
            const Text(
              'Keep your allergies, chronic conditions, and body metrics updated for your care team.',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 24),

            // Metrics Row
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Height (cm)', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          TextField(controller: _heightController, keyboardType: TextInputType.number),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Weight (kg)', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          TextField(controller: _weightController, keyboardType: TextInputType.number),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Blood Pressure', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          TextField(controller: _bpController),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Allergies Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Known Allergies', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Allergy'),
                  onPressed: _openAddAllergyDialog,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: _isLoading
                  ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _allergies.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final alg = _allergies[idx];
                        return ListTile(
                          leading: const Icon(Icons.warning_amber_outlined, color: AppTheme.dangerRed),
                          title: Text(alg['allergen'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Reaction: ${alg['reaction'] ?? "None"}'),
                          trailing: Chip(label: Text(alg['severity'] ?? 'HIGH'), backgroundColor: Colors.red[100]),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 24),

            // Chronic Conditions Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Chronic Conditions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Condition'),
                  onPressed: _openAddConditionDialog,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: _isLoading
                  ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _chronicConditions.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final cc = _chronicConditions[idx];
                        return ListTile(
                          leading: const Icon(Icons.medical_information_outlined, color: AppTheme.primaryTeal),
                          title: Text(cc['conditionName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Diagnosed: ${cc['diagnosedYear']}'),
                          trailing: Chip(label: Text(cc['status'] ?? 'MANAGED'), backgroundColor: AppTheme.primaryLightTeal),
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

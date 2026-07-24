import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/patient_service.dart';

class PatientHealthProfileScreen extends ConsumerStatefulWidget {
  const PatientHealthProfileScreen({super.key});

  @override
  ConsumerState<PatientHealthProfileScreen> createState() =>
      _PatientHealthProfileScreenState();
}

class _PatientHealthProfileScreenState
    extends ConsumerState<PatientHealthProfileScreen> {
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _surgicalHistoryController = TextEditingController();
  final _familyHistoryController = TextEditingController();
  final _notesController = TextEditingController();
  String _smokingStatus = 'NEVER';
  String _alcoholStatus = 'NONE';

  static const _smokingStatuses = ['NEVER', 'FORMER', 'CURRENT'];
  static const _alcoholStatuses = ['NONE', 'OCCASIONAL', 'REGULAR'];

  bool _healthProfileExists = false;
  double? _bmi;

  List<dynamic> _allergies = [];
  List<dynamic> _chronicConditions = [];
  bool _isLoading = false;
  bool _isSavingMetrics = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _surgicalHistoryController.dispose();
    _familyHistoryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final pService = ref.read(patientServiceProvider);
    try {
      final healthProfile = await pService.getMyHealthProfile();
      if (mounted) {
        setState(() {
          _healthProfileExists = true;
          _heightController.text = '${healthProfile['heightCm'] ?? ''}';
          _weightController.text = '${healthProfile['weightKg'] ?? ''}';
          _surgicalHistoryController.text =
              healthProfile['surgicalHistory'] ?? '';
          _familyHistoryController.text = healthProfile['familyHistory'] ?? '';
          _notesController.text = healthProfile['additionalNotes'] ?? '';
          _smokingStatus = healthProfile['smokingStatus'] ?? 'NEVER';
          _alcoholStatus = healthProfile['alcoholStatus'] ?? 'NONE';
          _bmi = (healthProfile['bmi'] as num?)?.toDouble();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _healthProfileExists = false);
    }

    try {
      final allergiesRes = await pService.getMyAllergies();
      final conditionsRes = await pService.getMyChronicConditions();
      if (mounted) {
        setState(() {
          _allergies = allergiesRes;
          _chronicConditions = conditionsRes;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load allergies/conditions.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveMetrics() async {
    setState(() => _isSavingMetrics = true);
    final dto = {
      'heightCm': double.tryParse(_heightController.text) ?? 0,
      'weightKg': double.tryParse(_weightController.text) ?? 0,
      'smokingStatus': _smokingStatus,
      'alcoholStatus': _alcoholStatus,
      'surgicalHistory': _surgicalHistoryController.text.trim(),
      'familyHistory': _familyHistoryController.text.trim(),
      'additionalNotes': _notesController.text.trim(),
    };
    try {
      final pService = ref.read(patientServiceProvider);
      if (_healthProfileExists) {
        await pService.updateHealthProfile(dto);
      } else {
        await pService.addHealthProfile(dto);
        _healthProfileExists = true;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Health metrics saved successfully.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save health metrics.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingMetrics = false);
    }
  }

  void _openAddAllergyDialog() {
    final allergenController = TextEditingController();
    final reactionController = TextEditingController();
    String severity = 'MODERATE';
    String allergyType = 'DRUG';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Known Allergy'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: allergenController,
                    decoration: const InputDecoration(
                        labelText: 'Allergen (e.g. Penicillin)')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: allergyType,
                  decoration: const InputDecoration(labelText: 'Allergy Type'),
                  items: const [
                    DropdownMenuItem(value: 'DRUG', child: Text('DRUG')),
                    DropdownMenuItem(value: 'FOOD', child: Text('FOOD')),
                    DropdownMenuItem(
                        value: 'ENVIRONMENTAL', child: Text('ENVIRONMENTAL')),
                    DropdownMenuItem(value: 'OTHER', child: Text('OTHER')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => allergyType = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: reactionController,
                    decoration: const InputDecoration(labelText: 'Reaction')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: severity,
                  decoration: const InputDecoration(labelText: 'Severity'),
                  items: const [
                    DropdownMenuItem(value: 'MILD', child: Text('MILD')),
                    DropdownMenuItem(
                        value: 'MODERATE', child: Text('MODERATE')),
                    DropdownMenuItem(value: 'SEVERE', child: Text('SEVERE')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => severity = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await ref.read(patientServiceProvider).addAllergy({
                    'allergen': allergenController.text.trim(),
                    'allergyType': allergyType,
                    'reaction': reactionController.text.trim(),
                    'severity': severity,
                    'confirmed': true,
                  });
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to add allergy.')),
                    );
                  }
                }
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

  Future<void> _deleteAllergy(String allergyId) async {
    try {
      await ref.read(patientServiceProvider).deleteAllergy(allergyId);
      _loadData();
    } catch (_) {}
  }

  void _openAddConditionDialog() {
    final conditionController = TextEditingController();
    final icdController = TextEditingController();
    String status = 'ACTIVE';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Chronic Condition'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: conditionController,
                    decoration:
                        const InputDecoration(labelText: 'Condition Name')),
                const SizedBox(height: 12),
                TextField(
                    controller: icdController,
                    decoration: const InputDecoration(
                        labelText: 'ICD-10 Code (optional)')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'ACTIVE', child: Text('ACTIVE')),
                    DropdownMenuItem(
                        value: 'IN_REMISSION', child: Text('IN_REMISSION')),
                    DropdownMenuItem(
                        value: 'RESOLVED', child: Text('RESOLVED')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => status = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await ref.read(patientServiceProvider).addChronicCondition({
                    'conditionName': conditionController.text.trim(),
                    'icd10Code': icdController.text.trim(),
                    'status': status,
                  });
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to add condition.')),
                    );
                  }
                }
                if (mounted) Navigator.pop(ctx);
                _loadData();
              },
              child: const Text('Add Condition'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCondition(String conditionId) async {
    try {
      await ref
          .read(patientServiceProvider)
          .deleteChronicCondition(conditionId);
      _loadData();
    } catch (_) {}
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
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMain),
            ),
            const SizedBox(height: 4),
            const Text(
              'Keep your allergies, chronic conditions, and body metrics updated for your care team.',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 24),

            // Metrics Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Height (cm)',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              TextField(
                                  controller: _heightController,
                                  keyboardType: TextInputType.number),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Weight (kg)',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              TextField(
                                  controller: _weightController,
                                  keyboardType: TextInputType.number),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_bmi != null) ...[
                      const SizedBox(height: 12),
                      Text('BMI: ${_bmi!.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppTheme.textMuted)),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _smokingStatus,
                            decoration: const InputDecoration(
                                labelText: 'Smoking Status'),
                            items: _smokingStatuses
                                .map((s) =>
                                    DropdownMenuItem(value: s, child: Text(s)))
                                .toList(),
                            onChanged: (val) => setState(
                                () => _smokingStatus = val ?? _smokingStatus),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _alcoholStatus,
                            decoration: const InputDecoration(
                                labelText: 'Alcohol Status'),
                            items: _alcoholStatuses
                                .map((s) =>
                                    DropdownMenuItem(value: s, child: Text(s)))
                                .toList(),
                            onChanged: (val) => setState(
                                () => _alcoholStatus = val ?? _alcoholStatus),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Surgical History',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                        controller: _surgicalHistoryController, maxLines: 2),
                    const SizedBox(height: 16),
                    const Text('Family History',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                        controller: _familyHistoryController, maxLines: 2),
                    const SizedBox(height: 16),
                    const Text('Additional Notes',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(controller: _notesController, maxLines: 2),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 200,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _isSavingMetrics ? null : _saveMetrics,
                        child: _isSavingMetrics
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Save Metrics'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Allergies Section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Known Allergies',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Allergy'),
                    onPressed: _openAddAllergyDialog,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()))
                  : _allergies.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('No allergies recorded.')))
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _allergies.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final alg = _allergies[idx];
                            return ListTile(
                              leading: const Icon(Icons.warning_amber_outlined,
                                  color: AppTheme.dangerRed),
                              title: Text(alg['allergen'] ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  'Reaction: ${alg['reaction'] ?? "None"}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Chip(
                                      label: Text(alg['severity'] ?? ''),
                                      backgroundColor: Colors.red[100]),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18),
                                    onPressed: () =>
                                        _deleteAllergy(alg['allergyId']),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 24),

            // Chronic Conditions Section
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chronic Conditions',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Condition'),
                    onPressed: _openAddConditionDialog,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()))
                  : _chronicConditions.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                              child: Text('No chronic conditions recorded.')))
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _chronicConditions.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final cc = _chronicConditions[idx];
                            return ListTile(
                              leading: const Icon(
                                  Icons.medical_information_outlined,
                                  color: AppTheme.primaryTeal),
                              title: Text(cc['conditionName'] ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle:
                                  Text('ICD-10: ${cc['icd10Code'] ?? 'N/A'}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Chip(
                                      label: Text(cc['status'] ?? ''),
                                      backgroundColor:
                                          AppTheme.primaryLightTeal),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18),
                                    onPressed: () =>
                                        _deleteCondition(cc['conditionId']),
                                  ),
                                ],
                              ),
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

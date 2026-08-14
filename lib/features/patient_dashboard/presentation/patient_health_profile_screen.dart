import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  static const _conditionStatuses = ['ACTIVE', 'IN_REMISSION', 'RESOLVED'];
  static final _icd10Pattern =
      RegExp(r'^[A-Za-z][0-9][0-9AB](?:\.[0-9A-Za-z]{1,4})?$');

  // Gate: patient must have a General Profile before health metrics unlock.
  bool _needProfileInit = false;

  bool _healthProfileExists = false;
  bool _isEditMode = false;
  double? _bmi;

  List<dynamic> _allergies = [];
  List<dynamic> _chronicConditions = [];
  int _activeSectionIndex = 0; // 0 = Known Allergies, 1 = Chronic Conditions
  bool _isLoading = true;
  bool _isSavingMetrics = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
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

  // ── Load ──────────────────────────────────────────────────────────
  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final pService = ref.read(patientServiceProvider);

    try {
      await pService.getMyProfile();
      _needProfileInit = false;
    } catch (e) {
      final status = e is DioException ? e.response?.statusCode : null;
      if (status == 404) {
        if (mounted) setState(() => _needProfileInit = true);
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    }

    await Future.wait([
      _loadHealthProfile(),
      _loadAllergies(),
      _loadChronicConditions(),
    ]);

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadHealthProfile() async {
    final pService = ref.read(patientServiceProvider);
    try {
      final profile = await pService.getMyHealthProfile();
      if (!mounted) return;
      setState(() {
        _healthProfileExists = true;
        _isEditMode = false;
        _heightController.text = '${profile['heightCm'] ?? ''}';
        _weightController.text = '${profile['weightKg'] ?? ''}';
        _surgicalHistoryController.text = profile['surgicalHistory'] ?? '';
        _familyHistoryController.text = profile['familyHistory'] ?? '';
        _notesController.text = profile['additionalNotes'] ?? '';
        _smokingStatus = profile['smokingStatus'] ?? 'NEVER';
        _alcoholStatus = profile['alcoholStatus'] ?? 'NONE';
        _bmi = (profile['bmi'] as num?)?.toDouble();
      });
    } catch (e) {
      final status = e is DioException ? e.response?.statusCode : null;
      if (status == 404 && mounted) {
        setState(() {
          _healthProfileExists = false;
          _isEditMode = true; // auto-open for first-time creation
        });
      }
    }
  }

  Future<void> _loadAllergies() async {
    try {
      final data = await ref.read(patientServiceProvider).getMyAllergies();
      if (mounted) setState(() => _allergies = data);
    } catch (_) {}
  }

  Future<void> _loadChronicConditions() async {
    try {
      final data =
          await ref.read(patientServiceProvider).getMyChronicConditions();
      if (mounted) setState(() => _chronicConditions = data);
    } catch (_) {}
  }

  // ── Metrics form: edit lock ────────────────────────────────────────
  void _enableEdit() => setState(() => _isEditMode = true);

  void _cancelEdit() {
    if (!_healthProfileExists) return; // nothing to cancel back to
    setState(() => _isEditMode = false);
    _loadHealthProfile();
  }

  Future<void> _saveMetrics() async {
    final height = double.tryParse(_heightController.text);
    final weight = double.tryParse(_weightController.text);
    if (height == null || height <= 0 || weight == null || weight <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid height and weight.')),
      );
      return;
    }

    setState(() => _isSavingMetrics = true);
    final dto = {
      'heightCm': height,
      'weightKg': weight,
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
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Health metrics saved successfully.')),
        );
      }
      await _loadHealthProfile();
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

  // ── Allergy modal ───────────────────────────────────────────────────
  void _openAddAllergyDialog() {
    final allergenController = TextEditingController();
    final reactionController = TextEditingController();
    String severity = 'MILD';
    String allergyType = 'DRUG';
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Known Allergy'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: allergenController,
                    maxLength: 100,
                    decoration: const InputDecoration(
                        labelText: 'Allergen (e.g. Penicillin)'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: allergyType,
                    decoration:
                        const InputDecoration(labelText: 'Allergy Type'),
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
                  TextFormField(
                    controller: reactionController,
                    maxLength: 255,
                    decoration: const InputDecoration(
                        labelText: 'Reaction (e.g. Skin rash, Anaphylaxis)'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
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
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                try {
                  await ref.read(patientServiceProvider).addAllergy({
                    'allergen': allergenController.text.trim(),
                    'allergyType': allergyType,
                    'reaction': reactionController.text.trim(),
                    'severity': severity,
                    'confirmed': true,
                  });
                  if (mounted) {
                    Navigator.pop(ctx);
                    setState(() => _activeSectionIndex = 0);
                  }
                  _loadAllergies();
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to add allergy.')),
                    );
                  }
                }
              },
              child: const Text('Add Allergy'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAllergy(String allergyId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove allergy?'),
        content: const Text('Are you sure you want to remove this allergy?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(patientServiceProvider).deleteAllergy(allergyId);
      _loadAllergies();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete allergy.')),
        );
      }
    }
  }

  // ── Chronic condition modal ──────────────────────────────────────────
  void _openAddConditionDialog() {
    final conditionController = TextEditingController();
    final icdController = TextEditingController();
    final notesController = TextEditingController();
    String status = 'ACTIVE';
    DateTime? diagnosisDate;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Register Chronic Condition'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: conditionController,
                    maxLength: 150,
                    decoration: const InputDecoration(
                        labelText:
                            'Condition Name (e.g. Diabetes Mellitus Type II)'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: icdController,
                    decoration: const InputDecoration(
                        labelText: 'ICD-10 Code (e.g. E11.9)'),
                    validator: (v) {
                      final val = v?.trim() ?? '';
                      if (val.isEmpty) return 'Required';
                      if (!_icd10Pattern.hasMatch(val)) {
                        return 'Must be a valid ICD-10 format.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: diagnosisDate ?? DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setDialogState(() => diagnosisDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration:
                          const InputDecoration(labelText: 'Diagnosis Date'),
                      child: Text(
                        diagnosisDate == null
                            ? 'Select date'
                            : '${diagnosisDate!.year}-${diagnosisDate!.month.toString().padLeft(2, '0')}-${diagnosisDate!.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: _conditionStatuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => status = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesController,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(labelText: 'Notes (optional)'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                if (diagnosisDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Select a diagnosis date.')),
                  );
                  return;
                }
                try {
                  await ref.read(patientServiceProvider).addChronicCondition({
                    'conditionName': conditionController.text.trim(),
                    'icd10Code': icdController.text.trim(),
                    'diagnosisDate':
                        diagnosisDate!.toIso8601String().split('T').first,
                    'status': status,
                    'notes': notesController.text.trim(),
                  });
                  if (mounted) {
                    Navigator.pop(ctx);
                    setState(() => _activeSectionIndex = 1);
                  }
                  _loadChronicConditions();
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Failed to register condition.')),
                    );
                  }
                }
              },
              child: const Text('Add Condition'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCondition(String conditionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove condition?'),
        content: const Text('Are you sure you want to remove this condition?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(patientServiceProvider)
          .deleteChronicCondition(conditionId);
      _loadChronicConditions();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to remove condition.')),
        );
      }
    }
  }

  // ── Shared styling helpers (mirrors Angular .badge / .item-list-card / .group-card) ──
  static const _offWhite = Color(0xFFF9FAFB);
  static const _borderColor = Color(0xFFE5E7EB);

  Widget _badge(String text, {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style:
              TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  // Card header with title + optional action button that WRAPS instead of
  // overflowing when space is tight (fixes the overflow on narrow phones).
  Widget _groupCardHeader(String title, {Widget? action}) {
    return Container(
      padding: const EdgeInsets.only(bottom: 14),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryTeal)),
          if (action != null) action,
        ],
      ),
    );
  }

  // Two fields side-by-side on normal width, stacked on very narrow screens —
  // this is what actually removes the RenderFlex overflow risk on small devices.
  Widget _responsiveFieldPair(Widget a, Widget b) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [a, const SizedBox(height: 16), b],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 16),
            Expanded(child: b),
          ],
        );
      },
    );
  }

  // ── Build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_needProfileInit) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: const Border(
                      left: BorderSide(color: AppTheme.warningAmber, width: 5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Registration Required',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB45309))),
                    const SizedBox(height: 8),
                    const Text(
                      'Please initialize your General Patient Profile before entering your medical metrics.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF78350F)),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.go('/patient/profile'),
                      child: const Text('Setup Profile'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _offWhite,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAll,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMetricsCard(),
                const SizedBox(height: 20),
                _buildSecondarySection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsCard() {
    final locked = _healthProfileExists && !_isEditMode;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _groupCardHeader(
            '🩺 Health Metrics & Medical History',
            action: locked
                ? OutlinedButton(
                    onPressed: _enableEdit, child: const Text('Edit Metrics'))
                : null,
          ),
          _responsiveFieldPair(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Height (cm)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                    controller: _heightController,
                    enabled: !locked,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Weight (kg)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                    controller: _weightController,
                    enabled: !locked,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true)),
              ],
            ),
          ),
          if (_bmi != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  color: _offWhite, borderRadius: BorderRadius.circular(8)),
              child: Text('Calculated BMI: ${_bmi!.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: AppTheme.textMain, fontWeight: FontWeight.bold)),
            ),
          ],
          const SizedBox(height: 16),
          _responsiveFieldPair(
            DropdownButtonFormField<String>(
              initialValue: _smokingStatus,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Smoking Status'),
              items: _smokingStatuses
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: locked
                  ? null
                  : (val) =>
                      setState(() => _smokingStatus = val ?? _smokingStatus),
            ),
            DropdownButtonFormField<String>(
              initialValue: _alcoholStatus,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Alcohol Status'),
              items: _alcoholStatuses
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: locked
                  ? null
                  : (val) =>
                      setState(() => _alcoholStatus = val ?? _alcoholStatus),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Surgical History',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
              controller: _surgicalHistoryController,
              enabled: !locked,
              minLines: 2,
              maxLines: 4),
          const SizedBox(height: 16),
          const Text('Family Medical History',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
              controller: _familyHistoryController,
              enabled: !locked,
              minLines: 2,
              maxLines: 4),
          const SizedBox(height: 16),
          const Text('Additional Notes',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
              controller: _notesController,
              enabled: !locked,
              minLines: 2,
              maxLines: 4),
          if (!locked) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.only(top: 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _borderColor)),
              ),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (_healthProfileExists)
                    OutlinedButton(
                        onPressed: _isSavingMetrics ? null : _cancelEdit,
                        child: const Text('Cancel')),
                  ElevatedButton(
                    onPressed: _isSavingMetrics ? null : _saveMetrics,
                    child: _isSavingMetrics
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Save Changes'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSecondarySection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Segmented Tab Switcher Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _offWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _segmentTab(
                      label: 'Known Allergies',
                      count: _allergies.length,
                      icon: Icons.warning_amber_rounded,
                      iconColor: const Color(0xFFD97706),
                      isActive: _activeSectionIndex == 0,
                      onTap: () => setState(() => _activeSectionIndex = 0),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _segmentTab(
                      label: 'Chronic Conditions',
                      count: _chronicConditions.length,
                      icon: Icons.assignment_outlined,
                      iconColor: const Color(0xFF0284C7),
                      isActive: _activeSectionIndex == 1,
                      onTap: () => setState(() => _activeSectionIndex = 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: _borderColor),
          // Active Section Content
          Padding(
            padding: const EdgeInsets.all(18),
            child: _activeSectionIndex == 0
                ? _buildAllergiesContent()
                : _buildConditionsContent(),
          ),
        ],
      ),
    );
  }

  Widget _segmentTab({
    required String label,
    required int count,
    required IconData icon,
    required Color iconColor,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? iconColor : AppTheme.textMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    color: isActive
                        ? AppTheme.primaryDarkTeal
                        : AppTheme.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppTheme.primaryLightTeal
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isActive
                        ? AppTheme.primaryDarkTeal
                        : AppTheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback onAdd,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 420;
        final textBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textMain,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        );
        final button = ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: Text(buttonLabel),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          onPressed: onAdd,
        );

        if (isSmall) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              textBlock,
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: button),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: textBlock),
            const SizedBox(width: 12),
            button,
          ],
        );
      },
    );
  }

  Widget _buildAllergiesContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Known Allergies',
          subtitle: 'List any medication, food, or environmental allergies',
          buttonLabel: 'Add Allergy',
          onAdd: _openAddAllergyDialog,
        ),
        const SizedBox(height: 16),
        if (_allergies.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            decoration: BoxDecoration(
              color: _offWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFDCFCE7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 32,
                    color: Color(0xFF15803D),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No Known Allergies Recorded',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Click "Add Allergy" above if you have any drug or food allergies.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              for (int i = 0; i < _allergies.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _allergyCard(_allergies[i]),
              ],
            ],
          ),
      ],
    );
  }

  Widget _allergyCard(dynamic al) {
    final severity = al['severity'] ?? '';
    Color bg, fg;
    switch (severity) {
      case 'SEVERE':
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFB91C1C);
        break;
      case 'MODERATE':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        break;
      default:
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF15803D);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _offWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(al['allergen'] ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: AppTheme.textMain)),
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: AppTheme.dangerRed),
                  onPressed: () => _deleteAllergy(al['allergyId']),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _badge(severity, bg: bg, fg: fg),
              _badge(al['allergyType'] ?? '',
                  bg: const Color(0xFFE1F5EE), fg: AppTheme.primaryTeal),
            ],
          ),
          const SizedBox(height: 6),
          Text('Reaction: ${al['reaction'] ?? "None"}',
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _buildConditionsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Chronic Conditions',
          subtitle: 'Track long-term diagnosed health conditions',
          buttonLabel: 'Add Condition',
          onAdd: _openAddConditionDialog,
        ),
        const SizedBox(height: 16),
        if (_chronicConditions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            decoration: BoxDecoration(
              color: _offWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE0F2FE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.assignment_turned_in_outlined,
                    size: 32,
                    color: Color(0xFF0369A1),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'No Chronic Conditions Recorded',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Click "Add Condition" above to register diagnosed health conditions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              for (int i = 0; i < _chronicConditions.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _conditionCard(_chronicConditions[i]),
              ],
            ],
          ),
      ],
    );
  }

  Widget _conditionCard(dynamic cc) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _offWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(cc['conditionName'] ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: AppTheme.textMain)),
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: AppTheme.dangerRed),
                  onPressed: () => _deleteCondition(cc['conditionId']),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'ICD-10: ${cc['icd10Code'] ?? 'N/A'} · Diagnosed: ${cc['diagnosisDate'] ?? 'N/A'}',
            style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 6),
          _badge(cc['status'] ?? '',
              bg: const Color(0xFFE1F5EE), fg: AppTheme.primaryTeal),
        ],
      ),
    );
  }
}

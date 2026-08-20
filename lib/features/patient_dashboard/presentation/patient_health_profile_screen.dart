import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_notification.dart';
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
  static const _allergyTypes = ['DRUG', 'FOOD', 'ENVIRONMENTAL', 'OTHER'];
  static const _severities = ['MILD', 'MODERATE', 'SEVERE'];
  static final _icd10Pattern =
      RegExp(r'^[A-Za-z][0-9][0-9AB](?:\.[0-9A-Za-z]{1,4})?$');

  bool _needProfileInit = false;
  bool _healthProfileExists = false;
  bool _isEditMode = false;
  double? _bmi;

  List<dynamic> _allergies = [];
  List<dynamic> _chronicConditions = [];
  int _activeTabIndex = 0; // 0 = Allergies, 1 = Chronic Conditions
  bool _isLoading = true;
  bool _isSavingMetrics = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _heightController.addListener(_calculateLiveBmi);
    _weightController.addListener(_calculateLiveBmi);
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

  void _calculateLiveBmi() {
    final h = double.tryParse(_heightController.text);
    final w = double.tryParse(_weightController.text);
    if (h != null && h > 0 && w != null && w > 0) {
      final hm = h / 100.0;
      final bmiVal = w / (hm * hm);
      if (mounted) setState(() => _bmi = bmiVal);
    }
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final pService = ref.read(patientServiceProvider);

    try {
      final profile = await pService.getMyProfile();
      if (profile == null || (profile is Map && profile['patientId'] == null)) {
        if (mounted) {
          setState(() {
            _needProfileInit = true;
            _isLoading = false;
          });
        }
        return;
      }
      _needProfileInit = false;
    } catch (_) {
      if (mounted) {
        setState(() {
          _needProfileInit = true;
          _isLoading = false;
        });
      }
      return;
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
          _isEditMode = true; // Auto-open edit for first time
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

  void _enableEdit() => setState(() => _isEditMode = true);

  void _cancelEdit() {
    if (!_healthProfileExists) return;
    setState(() => _isEditMode = false);
    _loadHealthProfile();
  }

  Future<void> _saveMetrics() async {
    final height = double.tryParse(_heightController.text);
    final weight = double.tryParse(_weightController.text);
    if (height == null || height <= 0 || weight == null || weight <= 0) {
      AppNotification.showWarning(
        context,
        'Please enter a valid height and weight.',
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
        AppNotification.showSuccess(
          context,
          _healthProfileExists
              ? 'Health metrics updated successfully.'
              : 'Health metrics saved successfully.',
        );
      }
      await _loadHealthProfile();
    } catch (_) {
      if (mounted) {
        AppNotification.showError(
          context,
          'Failed to save health metrics.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingMetrics = false);
    }
  }

  // ── Modals & Actions ───────────────────────────────────────────────────
  void _openAddAllergyDialog() {
    final allergenController = TextEditingController();
    final reactionController = TextEditingController();
    String allergyType = 'DRUG';
    String severity = 'MODERATE';
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
              SizedBox(width: 8),
              Text('Add Known Allergy', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: allergenController,
                    decoration: const InputDecoration(
                      labelText: 'Allergen Name *',
                      hintText: 'E.g. Penicillin, Peanuts, Latex',
                      isDense: true,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Allergen name is required' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: allergyType,
                    decoration: const InputDecoration(labelText: 'Allergy Type', isDense: true),
                    items: _allergyTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => allergyType = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: severity,
                    decoration: const InputDecoration(labelText: 'Severity Level', isDense: true),
                    items: _severities
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => severity = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: reactionController,
                    decoration: const InputDecoration(
                      labelText: 'Reaction Details',
                      hintText: 'E.g. Skin rash, shortness of breath',
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
            ),
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
                    setState(() => _activeTabIndex = 0);
                    AppNotification.showSuccess(
                      context,
                      'Allergy added successfully.',
                    );
                  }
                  _loadAllergies();
                } catch (_) {
                  if (mounted) {
                    AppNotification.showError(
                      context,
                      'Failed to add allergy.',
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Allergy?'),
        content: const Text('Are you sure you want to remove this allergy record?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(patientServiceProvider).deleteAllergy(allergyId);
      _loadAllergies();
    } catch (_) {}
  }

  void _openAddConditionDialog() {
    final conditionController = TextEditingController();
    final icdController = TextEditingController();
    final notesController = TextEditingController();
    String status = 'ACTIVE';
    DateTime? diagnosisDate = DateTime.now();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.assignment_outlined, color: Color(0xFF0284C7), size: 22),
              SizedBox(width: 8),
              Text('Register Condition', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: conditionController,
                    decoration: const InputDecoration(
                      labelText: 'Condition Name *',
                      hintText: 'E.g. Diabetes Mellitus Type II',
                      isDense: true,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Condition name is required' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: icdController,
                    decoration: const InputDecoration(
                      labelText: 'ICD-10 Code *',
                      hintText: 'E.g. E11.9, I10',
                      isDense: true,
                    ),
                    validator: (v) {
                      final val = v?.trim() ?? '';
                      if (val.isEmpty) return 'ICD-10 Code is required';
                      if (!_icd10Pattern.hasMatch(val)) return 'Invalid format (e.g. E11.9)';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: diagnosisDate ?? DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setDialogState(() => diagnosisDate = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Diagnosis Date', isDense: true),
                      child: Text(
                        diagnosisDate == null
                            ? 'Select Date'
                            : '${diagnosisDate!.year}-${diagnosisDate!.month.toString().padLeft(2, '0')}-${diagnosisDate!.day.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status', isDense: true),
                    items: _conditionStatuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(s.replaceAll('_', ' '))))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => status = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Clinical Notes',
                      hintText: 'Treatment details, medications...',
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                try {
                  await ref.read(patientServiceProvider).addChronicCondition({
                    'conditionName': conditionController.text.trim(),
                    'icd10Code': icdController.text.trim(),
                    'diagnosisDate': diagnosisDate!.toIso8601String().split('T').first,
                    'status': status,
                    'notes': notesController.text.trim(),
                  });
                  if (mounted) {
                    Navigator.pop(ctx);
                    setState(() => _activeTabIndex = 1);
                    AppNotification.showSuccess(
                      context,
                      'Condition registered successfully.',
                    );
                  }
                  _loadChronicConditions();
                } catch (_) {
                  if (mounted) {
                    AppNotification.showError(
                      context,
                      'Failed to add condition.',
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Condition?'),
        content: const Text('Are you sure you want to remove this condition record?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(patientServiceProvider).deleteChronicCondition(conditionId);
      _loadChronicConditions();
    } catch (_) {}
  }

  // ── Main UI Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundApp,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal)),
      );
    }

    if (_needProfileInit) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundApp,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(color: Color(0xFFFEF3C7), shape: BoxShape.circle),
                      child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 32),
                    ),
                    const SizedBox(height: 12),
                    const Text('Registration Required',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
                    const SizedBox(height: 8),
                    const Text(
                      'Please complete your General Patient Profile before entering your medical metrics and health history.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF78350F), fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: () => context.go('/patient/profile'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: const Text('Setup Patient Profile Now', style: TextStyle(fontWeight: FontWeight.bold)),
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
      backgroundColor: AppTheme.backgroundApp,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryTeal,
          onRefresh: _loadAll,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: isMobile ? 16 : 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Header Banner
                _buildHeaderBanner(isMobile),
                const SizedBox(height: 18),

                // 2. 4-Card KPI Stat Grid (Height, Weight, BMI, Lifestyle)
                _buildHealthKpiGrid(isMobile),
                const SizedBox(height: 20),

                // 3. Body Metrics & Medical History Form Card
                _buildMetricsFormCard(isMobile),
                const SizedBox(height: 24),

                // 4. Allergies & Chronic Conditions Segmented Group
                _buildAllergiesAndConditionsSection(isMobile),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 1. HEADER BANNER
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHeaderBanner(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 18 : 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF115E59)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withOpacity(0.2),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.favorite_border_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Health Metrics & History',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Personal vital indicators, lifestyle habits, and clinical allergy records',
                  style: TextStyle(
                    fontSize: isMobile ? 11.5 : 12.5,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. HEALTH KPI SUMMARY GRID (4 Cards)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHealthKpiGrid(bool isMobile) {
    final heightText = _heightController.text.isNotEmpty ? '${_heightController.text} cm' : '--';
    final weightText = _weightController.text.isNotEmpty ? '${_weightController.text} kg' : '--';

    String bmiText = '--';
    String bmiCategory = 'No Data';
    Color bmiColor = AppTheme.textMuted;

    if (_bmi != null && _bmi! > 0) {
      bmiText = _bmi!.toStringAsFixed(1);
      if (_bmi! < 18.5) {
        bmiCategory = 'Underweight';
        bmiColor = const Color(0xFFD97706);
      } else if (_bmi! < 25.0) {
        bmiCategory = 'Normal';
        bmiColor = const Color(0xFF059669);
      } else if (_bmi! < 30.0) {
        bmiCategory = 'Overweight';
        bmiColor = const Color(0xFFEA580C);
      } else {
        bmiCategory = 'Obese';
        bmiColor = const Color(0xFFDC2626);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildKpiCard(
              width: cardWidth,
              label: 'Height',
              value: heightText,
              icon: Icons.height_rounded,
              color: const Color(0xFF0D9488),
              bgColor: const Color(0xFFF0FDFA),
            ),
            _buildKpiCard(
              width: cardWidth,
              label: 'Weight',
              value: weightText,
              icon: Icons.scale_rounded,
              color: const Color(0xFF2563EB),
              bgColor: const Color(0xFFEFF6FF),
            ),
            _buildKpiCard(
              width: cardWidth,
              label: 'BMI Index',
              value: bmiText,
              tag: bmiCategory,
              tagColor: bmiColor,
              icon: Icons.speed_rounded,
              color: const Color(0xFF7C3AED),
              bgColor: const Color(0xFFF5F3FF),
            ),
            _buildKpiCard(
              width: cardWidth,
              label: 'Lifestyle',
              value: _smokingStatus == 'NEVER' ? 'Smoke-Free' : _smokingStatus,
              tag: _alcoholStatus == 'NONE' ? 'Alcohol-Free' : _alcoholStatus,
              tagColor: const Color(0xFF059669),
              icon: Icons.health_and_safety_outlined,
              color: const Color(0xFF059669),
              bgColor: const Color(0xFFECFDF5),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required double width,
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
    String? tag,
    Color? tagColor,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted),
              ),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 15),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textMain),
          ),
          if (tag != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (tagColor ?? color).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                tag,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: tagColor ?? color,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. BODY METRICS & MEDICAL HISTORY FORM CARD
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMetricsFormCard(bool isMobile) {
    final locked = _healthProfileExists && !_isEditMode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: AppTheme.primaryTeal, size: 20),
              SizedBox(width: 8),
              Text(
                'Clinical Measurements',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textMain),
              ),
            ],
          ),
          if (locked) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _enableEdit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: const Size(40, 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('Edit Metrics', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Height & Weight fields
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Height (cm) *', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _heightController,
                      enabled: !locked,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '175',
                        filled: locked,
                        fillColor: locked ? AppTheme.backgroundApp : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Weight (kg) *', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _weightController,
                      enabled: !locked,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '70',
                        filled: locked,
                        fillColor: locked ? AppTheme.backgroundApp : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Smoking & Alcohol Dropdowns
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Smoking Status', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _smokingStatus,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: locked,
                        fillColor: locked ? AppTheme.backgroundApp : Colors.white,
                      ),
                      items: _smokingStatuses
                          .map((s) => DropdownMenuItem(value: s, child: Text(s.replaceAll('_', ' '))))
                          .toList(),
                      onChanged: locked ? null : (v) => setState(() => _smokingStatus = v ?? _smokingStatus),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Alcohol Status', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _alcoholStatus,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: locked,
                        fillColor: locked ? AppTheme.backgroundApp : Colors.white,
                      ),
                      items: _alcoholStatuses
                          .map((s) => DropdownMenuItem(value: s, child: Text(s.replaceAll('_', ' '))))
                          .toList(),
                      onChanged: locked ? null : (v) => setState(() => _alcoholStatus = v ?? _alcoholStatus),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Surgical History
          const Text('Surgical History', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _surgicalHistoryController,
            enabled: !locked,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'List any past surgical procedures and dates...',
              filled: locked,
              fillColor: locked ? AppTheme.backgroundApp : Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          // Family Medical History
          const Text('Family Medical History', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _familyHistoryController,
            enabled: !locked,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'List hereditary conditions in family (e.g. Hypertension, Diabetes)...',
              filled: locked,
              fillColor: locked ? AppTheme.backgroundApp : Colors.white,
            ),
          ),
          const SizedBox(height: 14),

          // Clinical Notes
          const Text('Additional Notes', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextFormField(
            controller: _notesController,
            enabled: !locked,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Any additional notes or physical activity details...',
              filled: locked,
              fillColor: locked ? AppTheme.backgroundApp : Colors.white,
            ),
          ),

          if (!locked) ...[
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_healthProfileExists) ...[
                  OutlinedButton(
                    onPressed: _isSavingMetrics ? null : _cancelEdit,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                ],
                ElevatedButton(
                  onPressed: _isSavingMetrics ? null : _saveMetrics,
                  child: _isSavingMetrics
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save Changes'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 4. ALLERGIES & CHRONIC CONDITIONS (Segmented Tab Section)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildAllergiesAndConditionsSection(bool isMobile) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGray.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Segmented Switcher Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.backgroundApp,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSegmentButton(
                      index: 0,
                      title: 'Known Allergies',
                      count: _allergies.length,
                      icon: Icons.warning_amber_rounded,
                      activeColor: const Color(0xFFD97706),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildSegmentButton(
                      index: 1,
                      title: 'Chronic Conditions',
                      count: _chronicConditions.length,
                      icon: Icons.assignment_outlined,
                      activeColor: const Color(0xFF0284C7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.all(16),
            child: _activeTabIndex == 0 ? _buildAllergiesList(isMobile) : _buildConditionsList(isMobile),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton({
    required int index,
    required String title,
    required int count,
    required IconData icon,
    required Color activeColor,
  }) {
    final isActive = _activeTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _activeTabIndex = index),
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isActive
              ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 1))]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isActive ? activeColor : AppTheme.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive ? AppTheme.textMain : AppTheme.textMuted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isActive ? activeColor.withOpacity(0.12) : Colors.black.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: isActive ? activeColor : AppTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Allergies Tab View ───────────────────────────────────────────────────
  Widget _buildAllergiesList(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Allergy Directory', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: _openAddAllergyDialog,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: const Size(50, 32),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add Allergy', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_allergies.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.backgroundApp,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
                  child: const Icon(Icons.shield_outlined, color: Color(0xFF059669), size: 24),
                ),
                const SizedBox(height: 8),
                const Text('No Known Allergies Recorded', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 3),
                const Text('Keep your medical record updated to alert treating physicians.',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _allergies.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final al = _allergies[index];
              final severity = (al['severity'] ?? 'MODERATE').toString();
              Color sevColor = const Color(0xFF059669);
              if (severity == 'SEVERE') sevColor = const Color(0xFFDC2626);
              if (severity == 'MODERATE') sevColor = const Color(0xFFD97706);

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundApp,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderGray.withOpacity(0.6)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: sevColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.warning_amber_rounded, color: sevColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                al['allergen'] ?? 'Unknown Allergen',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: sevColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  severity,
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: sevColor),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Type: ${al['allergyType'] ?? 'General'} ${al['reaction'] != null && al['reaction'].toString().isNotEmpty ? '• Reaction: ${al['reaction']}' : ''}',
                            style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppTheme.dangerRed, size: 18),
                      onPressed: () => _deleteAllergy(al['allergyId']),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  // ── Chronic Conditions Tab View ──────────────────────────────────────────
  Widget _buildConditionsList(bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Conditions Directory', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: _openAddConditionDialog,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: const Size(50, 32),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add Condition', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_chronicConditions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.backgroundApp,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: Color(0xFFE0F2FE), shape: BoxShape.circle),
                  child: const Icon(Icons.check_circle_outline, color: Color(0xFF0284C7), size: 24),
                ),
                const SizedBox(height: 8),
                const Text('No Chronic Conditions Listed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 3),
                const Text('Any chronic ailments will appear here with ICD-10 codes.',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _chronicConditions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final cc = _chronicConditions[index];
              final status = (cc['status'] ?? 'ACTIVE').toString();
              Color stColor = const Color(0xFF059669);
              if (status == 'IN_REMISSION') stColor = const Color(0xFF2563EB);
              if (status == 'RESOLVED') stColor = AppTheme.textMuted;

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundApp,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderGray.withOpacity(0.6)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.assignment_outlined, color: Color(0xFF0284C7), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  cc['conditionName'] ?? 'Condition',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: stColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  status.replaceAll('_', ' '),
                                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: stColor),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'ICD-10: ${cc['icd10Code'] ?? '--'} • Diagnosed: ${cc['diagnosisDate'] ?? '--'}',
                            style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                          ),
                          if (cc['notes'] != null && cc['notes'].toString().isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              'Notes: ${cc['notes']}',
                              style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textMuted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppTheme.dangerRed, size: 18),
                      onPressed: () => _deleteCondition(cc['conditionId']),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

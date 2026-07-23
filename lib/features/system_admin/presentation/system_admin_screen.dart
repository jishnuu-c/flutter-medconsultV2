import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../data/reference_models.dart';
import '../data/reference_service.dart';

class SystemAdminScreen extends ConsumerStatefulWidget {
  const SystemAdminScreen({super.key});

  @override
  ConsumerState<SystemAdminScreen> createState() => _SystemAdminScreenState();
}

class _SystemAdminScreenState extends ConsumerState<SystemAdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = false;

  // Data Lists
  List<CityModel> _cities = [];
  List<SpecialtyModel> _specialties = [];
  List<LanguageModel> _languages = [];
  List<InsuranceProviderModel> _insurances = [];

  // Drill-down State
  CityModel? _selectedCityForLocalities;
  List<LocalityModel> _localities = [];

  SpecialtyModel? _selectedSpecialtyForSub;
  List<SubSpecialtyModel> _subSpecialties = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {
      _selectedCityForLocalities = null;
      _selectedSpecialtyForSub = null;
    });
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final refService = ref.read(referenceServiceProvider);

    try {
      switch (_tabController.index) {
        case 0:
          _selectedCityForLocalities = null;
          final res = await refService.getAllCities();
          setState(() => _cities = res);
          break;
        case 1:
          _selectedSpecialtyForSub = null;
          final res = await refService.getAllSpecialties();
          setState(() => _specialties = res);
          break;
        case 2:
          final res = await refService.getAllLanguages();
          setState(() => _languages = res);
          break;
        case 3:
          final res = await refService.getAllInsuranceProviders();
          setState(() => _insurances = res);
          break;
      }
    } catch (_) {
      // Mock data fallback if API backend not running
      _populateMockData();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateMockData() {
    if (_tabController.index == 0) {
      _cities = [
        CityModel(cityId: 'c1', countryCode: 'SA', nameEn: 'Riyadh', nameAr: 'الرياض', isActive: true, sortOrder: 1),
        CityModel(cityId: 'c2', countryCode: 'SA', nameEn: 'Jeddah', nameAr: 'جدة', isActive: true, sortOrder: 2),
        CityModel(cityId: 'c3', countryCode: 'SA', nameEn: 'Dammam', nameAr: 'الدمام', isActive: true, sortOrder: 3),
      ];
    } else if (_tabController.index == 1) {
      _specialties = [
        SpecialtyModel(specialtyId: 's1', code: 'GEN', nameEn: 'General Practice', nameAr: 'طب عام', category: 'GENERAL', isActive: true, sortOrder: 1),
        SpecialtyModel(specialtyId: 's2', code: 'CARD', nameEn: 'Cardiology', nameAr: 'أمراض القلب', category: 'MEDICAL', isActive: true, sortOrder: 2),
        SpecialtyModel(specialtyId: 's3', code: 'DERM', nameEn: 'Dermatology', nameAr: 'الجلدية', category: 'MEDICAL', isActive: true, sortOrder: 3),
      ];
    } else if (_tabController.index == 2) {
      _languages = [
        LanguageModel(languageId: 'l1', code: 'en', nameEn: 'English', nameAr: 'الإنجليزية', isActive: true),
        LanguageModel(languageId: 'l2', code: 'ar', nameEn: 'Arabic', nameAr: 'العربية', isActive: true),
      ];
    } else if (_tabController.index == 3) {
      _insurances = [
        InsuranceProviderModel(providerId: 'i1', nameEn: 'Tawuniya', nameAr: 'التعاونية', isActive: true),
        InsuranceProviderModel(providerId: 'i2', nameEn: 'Bupa Arabia', nameAr: 'بوبا العربية', isActive: true),
      ];
    }
  }

  Future<void> _loadLocalities(CityModel city) async {
    setState(() {
      _selectedCityForLocalities = city;
      _isLoading = true;
    });

    try {
      final res = await ref.read(referenceServiceProvider).getLocalities(city.cityId);
      setState(() => _localities = res);
    } catch (_) {
      setState(() {
        _localities = [
          LocalityModel(localityId: 'loc1', cityId: city.cityId, nameEn: 'Olaya District', nameAr: 'حي العليا', postalCode: '12211', isActive: true),
          LocalityModel(localityId: 'loc2', cityId: city.cityId, nameEn: 'Al Malqa', nameAr: 'حي الملقا', postalCode: '13521', isActive: true),
        ];
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSubSpecialties(SpecialtyModel spec) async {
    setState(() {
      _selectedSpecialtyForSub = spec;
      _isLoading = true;
    });

    try {
      final res = await ref.read(referenceServiceProvider).getSubSpecialties(spec.specialtyId);
      setState(() => _subSpecialties = res);
    } catch (_) {
      setState(() {
        _subSpecialties = [
          SubSpecialtyModel(subSpecialtyId: 'sub1', specialtyId: spec.specialtyId, nameEn: 'Interventional Cardiology', nameAr: 'أمراض القلب التداخلية', isActive: true),
        ];
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleAddClick() {
    switch (_tabController.index) {
      case 0:
        if (_selectedCityForLocalities != null) {
          _openLocalityDialog(null);
        } else {
          _openCityDialog(null);
        }
        break;
      case 1:
        if (_selectedSpecialtyForSub != null) {
          _openSubSpecialtyDialog(null);
        } else {
          _openSpecialtyDialog(null);
        }
        break;
      case 2:
        _openLanguageDialog(null);
        break;
      case 3:
        _openInsuranceDialog(null);
        break;
    }
  }

  // ── Dialogs ────────────────────────────────────────────────────────
  void _openCityDialog(CityModel? city) {
    final isEdit = city != null;
    final nameEnController = TextEditingController(text: city?.nameEn ?? '');
    final nameArController = TextEditingController(text: city?.nameAr ?? '');
    final countryCodeController = TextEditingController(text: city?.countryCode ?? 'SA');
    final sortOrderController = TextEditingController(text: (city?.sortOrder ?? (_cities.length + 1)).toString());
    bool isActive = city?.isActive ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Edit City' : 'Add New City'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameEnController, decoration: const InputDecoration(labelText: 'Name (EN)')),
                const SizedBox(height: 12),
                TextField(controller: nameArController, decoration: const InputDecoration(labelText: 'Name (AR)')),
                const SizedBox(height: 12),
                TextField(controller: countryCodeController, decoration: const InputDecoration(labelText: 'Country Code')),
                const SizedBox(height: 12),
                TextField(controller: sortOrderController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sort Order')),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Active Status'),
                  value: isActive,
                  onChanged: (val) => setDialogState(() => isActive = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final payload = {
                  'nameEn': nameEnController.text.trim(),
                  'nameAr': nameArController.text.trim(),
                  'countryCode': countryCodeController.text.trim(),
                  'sortOrder': int.tryParse(sortOrderController.text) ?? 1,
                  'isActive': isActive,
                };
                try {
                  if (isEdit) {
                    await ref.read(referenceServiceProvider).updateCity(city.cityId, payload);
                  } else {
                    await ref.read(referenceServiceProvider).addCity(payload);
                  }
                } catch (_) {}
                if (mounted) Navigator.pop(ctx);
                _loadData();
              },
              child: Text(isEdit ? 'Save Changes' : 'Add City'),
            ),
          ],
        ),
      ),
    );
  }

  void _openLocalityDialog(LocalityModel? loc) {
    final isEdit = loc != null;
    final nameEnController = TextEditingController(text: loc?.nameEn ?? '');
    final nameArController = TextEditingController(text: loc?.nameAr ?? '');
    final postalController = TextEditingController(text: loc?.postalCode ?? '');
    bool isActive = loc?.isActive ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Edit Locality' : 'Add Locality to ${_selectedCityForLocalities?.nameEn}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameEnController, decoration: const InputDecoration(labelText: 'Locality Name (EN)')),
                const SizedBox(height: 12),
                TextField(controller: nameArController, decoration: const InputDecoration(labelText: 'Locality Name (AR)')),
                const SizedBox(height: 12),
                TextField(controller: postalController, decoration: const InputDecoration(labelText: 'Postal Code')),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Active Status'),
                  value: isActive,
                  onChanged: (val) => setDialogState(() => isActive = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final payload = {
                  'cityId': _selectedCityForLocalities?.cityId ?? '',
                  'nameEn': nameEnController.text.trim(),
                  'nameAr': nameArController.text.trim(),
                  'postalCode': postalController.text.trim(),
                  'isActive': isActive,
                };
                try {
                  if (isEdit) {
                    await ref.read(referenceServiceProvider).updateLocality(loc.localityId, payload);
                  } else {
                    await ref.read(referenceServiceProvider).addLocality(payload);
                  }
                } catch (_) {}
                if (mounted) Navigator.pop(ctx);
                if (_selectedCityForLocalities != null) _loadLocalities(_selectedCityForLocalities!);
              },
              child: Text(isEdit ? 'Save Changes' : 'Add Locality'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSpecialtyDialog(SpecialtyModel? spec) {
    final isEdit = spec != null;
    final codeController = TextEditingController(text: spec?.code ?? '');
    final nameEnController = TextEditingController(text: spec?.nameEn ?? '');
    final nameArController = TextEditingController(text: spec?.nameAr ?? '');
    String category = spec?.category ?? 'GENERAL';
    bool isActive = spec?.isActive ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Edit Specialty' : 'Add Medical Specialty'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: codeController, decoration: const InputDecoration(labelText: 'Specialty Code (e.g. CARD)')),
                const SizedBox(height: 12),
                TextField(controller: nameEnController, decoration: const InputDecoration(labelText: 'Name (EN)')),
                const SizedBox(height: 12),
                TextField(controller: nameArController, decoration: const InputDecoration(labelText: 'Name (AR)')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: const [
                    DropdownMenuItem(value: 'GENERAL', child: Text('GENERAL')),
                    DropdownMenuItem(value: 'MEDICAL', child: Text('MEDICAL')),
                    DropdownMenuItem(value: 'SURGICAL', child: Text('SURGICAL')),
                    DropdownMenuItem(value: 'DENTAL', child: Text('DENTAL')),
                    DropdownMenuItem(value: 'PEDIATRICS', child: Text('PEDIATRICS')),
                    DropdownMenuItem(value: 'OBGYN', child: Text('OBGYN')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => category = val);
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Active Status'),
                  value: isActive,
                  onChanged: (val) => setDialogState(() => isActive = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final payload = {
                  'code': codeController.text.trim(),
                  'nameEn': nameEnController.text.trim(),
                  'nameAr': nameArController.text.trim(),
                  'category': category,
                  'isActive': isActive,
                };
                try {
                  if (isEdit) {
                    await ref.read(referenceServiceProvider).updateSpecialty(spec.specialtyId, payload);
                  } else {
                    await ref.read(referenceServiceProvider).addSpecialty(payload);
                  }
                } catch (_) {}
                if (mounted) Navigator.pop(ctx);
                _loadData();
              },
              child: Text(isEdit ? 'Save Changes' : 'Add Specialty'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSubSpecialtyDialog(SubSpecialtyModel? sub) {
    final isEdit = sub != null;
    final nameEnController = TextEditingController(text: sub?.nameEn ?? '');
    final nameArController = TextEditingController(text: sub?.nameAr ?? '');
    bool isActive = sub?.isActive ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Edit Sub-Specialty' : 'Add Sub-Specialty to ${_selectedSpecialtyForSub?.nameEn}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameEnController, decoration: const InputDecoration(labelText: 'Name (EN)')),
                const SizedBox(height: 12),
                TextField(controller: nameArController, decoration: const InputDecoration(labelText: 'Name (AR)')),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Active Status'),
                  value: isActive,
                  onChanged: (val) => setDialogState(() => isActive = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final payload = {
                  'specialtyId': _selectedSpecialtyForSub?.specialtyId ?? '',
                  'nameEn': nameEnController.text.trim(),
                  'nameAr': nameArController.text.trim(),
                  'isActive': isActive,
                };
                try {
                  if (isEdit) {
                    await ref.read(referenceServiceProvider).updateSubSpecialty(sub.subSpecialtyId, payload);
                  } else {
                    await ref.read(referenceServiceProvider).addSubSpecialty(payload);
                  }
                } catch (_) {}
                if (mounted) Navigator.pop(ctx);
                if (_selectedSpecialtyForSub != null) _loadSubSpecialties(_selectedSpecialtyForSub!);
              },
              child: Text(isEdit ? 'Save Changes' : 'Add Sub-Specialty'),
            ),
          ],
        ),
      ),
    );
  }

  void _openLanguageDialog(LanguageModel? lang) {
    final isEdit = lang != null;
    final codeController = TextEditingController(text: lang?.code ?? '');
    final nameEnController = TextEditingController(text: lang?.nameEn ?? '');
    final nameArController = TextEditingController(text: lang?.nameAr ?? '');
    bool isActive = lang?.isActive ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Edit Language' : 'Add Supported Language'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: codeController, decoration: const InputDecoration(labelText: 'Language Code (e.g. en)')),
                const SizedBox(height: 12),
                TextField(controller: nameEnController, decoration: const InputDecoration(labelText: 'Name (EN)')),
                const SizedBox(height: 12),
                TextField(controller: nameArController, decoration: const InputDecoration(labelText: 'Name (AR)')),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Active Status'),
                  value: isActive,
                  onChanged: (val) => setDialogState(() => isActive = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final payload = {
                  'code': codeController.text.trim(),
                  'nameEn': nameEnController.text.trim(),
                  'nameAr': nameArController.text.trim(),
                  'isActive': isActive,
                };
                try {
                  if (isEdit) {
                    await ref.read(referenceServiceProvider).updateLanguage(lang.languageId, payload);
                  } else {
                    await ref.read(referenceServiceProvider).addLanguage(payload);
                  }
                } catch (_) {}
                if (mounted) Navigator.pop(ctx);
                _loadData();
              },
              child: Text(isEdit ? 'Save Changes' : 'Add Language'),
            ),
          ],
        ),
      ),
    );
  }

  void _openInsuranceDialog(InsuranceProviderModel? ins) {
    final isEdit = ins != null;
    final nameEnController = TextEditingController(text: ins?.nameEn ?? '');
    final nameArController = TextEditingController(text: ins?.nameAr ?? '');
    bool isActive = ins?.isActive ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Edit Insurance Provider' : 'Add Insurance Provider'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameEnController, decoration: const InputDecoration(labelText: 'Provider Name (EN)')),
                const SizedBox(height: 12),
                TextField(controller: nameArController, decoration: const InputDecoration(labelText: 'Provider Name (AR)')),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Active Status'),
                  value: isActive,
                  onChanged: (val) => setDialogState(() => isActive = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final payload = {
                  'nameEn': nameEnController.text.trim(),
                  'nameAr': nameArController.text.trim(),
                  'isActive': isActive,
                };
                try {
                  if (isEdit) {
                    await ref.read(referenceServiceProvider).updateInsuranceProvider(ins.providerId, payload);
                  } else {
                    await ref.read(referenceServiceProvider).addInsuranceProvider(payload);
                  }
                } catch (_) {}
                if (mounted) Navigator.pop(ctx);
                _loadData();
              },
              child: Text(isEdit ? 'Save Changes' : 'Add Provider'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteItem(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: const Text('Are you sure you want to delete this reference item?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
            onPressed: () async {
              Navigator.pop(ctx);
              final refService = ref.read(referenceServiceProvider);
              try {
                switch (_tabController.index) {
                  case 0:
                    if (_selectedCityForLocalities != null) {
                      await refService.deleteLocality(id);
                      _loadLocalities(_selectedCityForLocalities!);
                    } else {
                      await refService.deleteCity(id);
                      _loadData();
                    }
                    break;
                  case 1:
                    if (_selectedSpecialtyForSub != null) {
                      await refService.deleteSubSpecialty(id);
                      _loadSubSpecialties(_selectedSpecialtyForSub!);
                    } else {
                      await refService.deleteSpecialty(id);
                      _loadData();
                    }
                    break;
                  case 2:
                    await refService.deleteLanguage(id);
                    _loadData();
                    break;
                  case 3:
                    await refService.deleteInsuranceProvider(id);
                    _loadData();
                    break;
                }
              } catch (_) {}
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Global Reference Configurations',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Manage system-wide reference data, cities, medical specialties, and insurance options.',
                      style: TextStyle(fontSize: 14, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  key: const Key('add_reference_item_btn'),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(_getAddButtonLabel()),
                  onPressed: _handleAddClick,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // TabBar
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: AppTheme.borderGray)),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: AppTheme.primaryTeal,
                unselectedLabelColor: AppTheme.textMuted,
                indicatorColor: AppTheme.primaryTeal,
                tabs: const [
                  Tab(text: 'Cities & Localities'),
                  Tab(text: 'Medical Specialties'),
                  Tab(text: 'Supported Languages'),
                  Tab(text: 'Insurance Providers'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Content Table Area
            Expanded(
              child: Card(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildCurrentTabContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getAddButtonLabel() {
    switch (_tabController.index) {
      case 0:
        return _selectedCityForLocalities != null ? 'Add Locality' : 'Add City';
      case 1:
        return _selectedSpecialtyForSub != null ? 'Add Sub-Specialty' : 'Add Specialty';
      case 2:
        return 'Add Language';
      case 3:
        return 'Add Provider';
      default:
        return 'Add Item';
    }
  }

  Widget _buildCurrentTabContent() {
    switch (_tabController.index) {
      case 0:
        return _buildCitiesTab();
      case 1:
        return _buildSpecialtiesTab();
      case 2:
        return _buildLanguagesTab();
      case 3:
        return _buildInsurancesTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Tab 0: Cities & Localities ──────────────────────────────────────
  Widget _buildCitiesTab() {
    if (_selectedCityForLocalities != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Back to Cities'),
                  onPressed: () => setState(() => _selectedCityForLocalities = null),
                ),
                const SizedBox(width: 16),
                Text(
                  'Localities for ${_selectedCityForLocalities!.nameEn} (${_selectedCityForLocalities!.nameAr})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Locality (EN)')),
                  DataColumn(label: Text('Locality (AR)')),
                  DataColumn(label: Text('Postal Code')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: _localities.map((loc) {
                  return DataRow(cells: [
                    DataCell(Text(loc.nameEn)),
                    DataCell(Text(loc.nameAr)),
                    DataCell(Text(loc.postalCode ?? '-')),
                    DataCell(
                      Chip(
                        label: Text(loc.isActive ? 'Active' : 'Inactive'),
                        backgroundColor: loc.isActive ? AppTheme.primaryLightTeal : Colors.grey[200],
                      ),
                    ),
                    DataCell(Row(
                      children: [
                        IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _openLocalityDialog(loc)),
                        IconButton(icon: const Icon(Icons.delete, size: 18, color: AppTheme.dangerRed), onPressed: () => _deleteItem(loc.localityId)),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('City Name (EN)')),
          DataColumn(label: Text('City Name (AR)')),
          DataColumn(label: Text('Country')),
          DataColumn(label: Text('Sort Order')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: _cities.map((city) {
          return DataRow(cells: [
            DataCell(Text(city.nameEn, style: const TextStyle(fontWeight: FontWeight.bold))),
            DataCell(Text(city.nameAr)),
            DataCell(Text(city.countryCode)),
            DataCell(Text(city.sortOrder.toString())),
            DataCell(
              Chip(
                label: Text(city.isActive ? 'Active' : 'Inactive'),
                backgroundColor: city.isActive ? AppTheme.primaryLightTeal : Colors.grey[200],
              ),
            ),
            DataCell(Row(
              children: [
                TextButton(
                  onPressed: () => _loadLocalities(city),
                  child: const Text('View Localities'),
                ),
                IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _openCityDialog(city)),
                IconButton(icon: const Icon(Icons.delete, size: 18, color: AppTheme.dangerRed), onPressed: () => _deleteItem(city.cityId)),
              ],
            )),
          ]);
        }).toList(),
      ),
    );
  }

  // ── Tab 1: Specialties & SubSpecialties ─────────────────────────────
  Widget _buildSpecialtiesTab() {
    if (_selectedSpecialtyForSub != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Back to Specialties'),
                  onPressed: () => setState(() => _selectedSpecialtyForSub = null),
                ),
                const SizedBox(width: 16),
                Text(
                  'Sub-Specialties for ${_selectedSpecialtyForSub!.nameEn}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Sub-Specialty (EN)')),
                  DataColumn(label: Text('Sub-Specialty (AR)')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: _subSpecialties.map((sub) {
                  return DataRow(cells: [
                    DataCell(Text(sub.nameEn)),
                    DataCell(Text(sub.nameAr)),
                    DataCell(
                      Chip(
                        label: Text(sub.isActive ? 'Active' : 'Inactive'),
                        backgroundColor: sub.isActive ? AppTheme.primaryLightTeal : Colors.grey[200],
                      ),
                    ),
                    DataCell(Row(
                      children: [
                        IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _openSubSpecialtyDialog(sub)),
                        IconButton(icon: const Icon(Icons.delete, size: 18, color: AppTheme.dangerRed), onPressed: () => _deleteItem(sub.subSpecialtyId)),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Code')),
          DataColumn(label: Text('Specialty Name (EN)')),
          DataColumn(label: Text('Specialty Name (AR)')),
          DataColumn(label: Text('Category')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: _specialties.map((spec) {
          return DataRow(cells: [
            DataCell(Text(spec.code, style: const TextStyle(fontWeight: FontWeight.bold))),
            DataCell(Text(spec.nameEn)),
            DataCell(Text(spec.nameAr)),
            DataCell(Chip(label: Text(spec.category))),
            DataCell(
              Chip(
                label: Text(spec.isActive ? 'Active' : 'Inactive'),
                backgroundColor: spec.isActive ? AppTheme.primaryLightTeal : Colors.grey[200],
              ),
            ),
            DataCell(Row(
              children: [
                TextButton(
                  onPressed: () => _loadSubSpecialties(spec),
                  child: const Text('View Sub-Specialties'),
                ),
                IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _openSpecialtyDialog(spec)),
                IconButton(icon: const Icon(Icons.delete, size: 18, color: AppTheme.dangerRed), onPressed: () => _deleteItem(spec.specialtyId)),
              ],
            )),
          ]);
        }).toList(),
      ),
    );
  }

  // ── Tab 2: Languages ────────────────────────────────────────────────
  Widget _buildLanguagesTab() {
    return SingleChildScrollView(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Code')),
          DataColumn(label: Text('Language (EN)')),
          DataColumn(label: Text('Language (AR)')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: _languages.map((lang) {
          return DataRow(cells: [
            DataCell(Text(lang.code, style: const TextStyle(fontWeight: FontWeight.bold))),
            DataCell(Text(lang.nameEn)),
            DataCell(Text(lang.nameAr)),
            DataCell(
              Chip(
                label: Text(lang.isActive ? 'Active' : 'Inactive'),
                backgroundColor: lang.isActive ? AppTheme.primaryLightTeal : Colors.grey[200],
              ),
            ),
            DataCell(Row(
              children: [
                IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _openLanguageDialog(lang)),
                IconButton(icon: const Icon(Icons.delete, size: 18, color: AppTheme.dangerRed), onPressed: () => _deleteItem(lang.languageId)),
              ],
            )),
          ]);
        }).toList(),
      ),
    );
  }

  // ── Tab 3: Insurance Providers ──────────────────────────────────────
  Widget _buildInsurancesTab() {
    return SingleChildScrollView(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Provider Name (EN)')),
          DataColumn(label: Text('Provider Name (AR)')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: _insurances.map((ins) {
          return DataRow(cells: [
            DataCell(Text(ins.nameEn, style: const TextStyle(fontWeight: FontWeight.bold))),
            DataCell(Text(ins.nameAr)),
            DataCell(
              Chip(
                label: Text(ins.isActive ? 'Active' : 'Inactive'),
                backgroundColor: ins.isActive ? AppTheme.primaryLightTeal : Colors.grey[200],
              ),
            ),
            DataCell(Row(
              children: [
                IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _openInsuranceDialog(ins)),
                IconButton(icon: const Icon(Icons.delete, size: 18, color: AppTheme.dangerRed), onPressed: () => _deleteItem(ins.providerId)),
              ],
            )),
          ]);
        }).toList(),
      ),
    );
  }
}

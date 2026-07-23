import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/models/auth_models.dart';
import '../../../core/theme/app_theme.dart';

class DoctorCardData {
  final String id;
  final String name;
  final String title;
  final String spec;
  final double rating;
  final int reviews;
  final int expYears;
  final String nextSlot;
  final double feeSar;

  const DoctorCardData({
    required this.id,
    required this.name,
    required this.title,
    required this.spec,
    required this.rating,
    required this.reviews,
    required this.expYears,
    required this.nextSlot,
    required this.feeSar,
  });
}

class LandingScreen extends ConsumerStatefulWidget {
  const LandingScreen({super.key});

  @override
  ConsumerState<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends ConsumerState<LandingScreen> {
  final _searchController = TextEditingController();
  String _selectedSpecialty = 'All';

  final List<String> _specialties = [
    'All',
    'General Practice',
    'Internal Medicine',
    'Cardiology',
    'Dermatology',
    'Pediatrics',
    'Orthopedics',
  ];

  final List<DoctorCardData> _mockDoctors = const [
    DoctorCardData(
      id: 'doc-1',
      name: 'Dr. Tariq Al-Mansoor',
      title: 'Dr',
      spec: 'Cardiology Specialist',
      rating: 4.9,
      reviews: 48,
      expYears: 12,
      nextSlot: 'Today 3:00 PM',
      feeSar: 250,
    ),
    DoctorCardData(
      id: 'doc-2',
      name: 'Dr. Sarah Jenkins',
      title: 'Dr',
      spec: 'Dermatology Consultant',
      rating: 5.0,
      reviews: 92,
      expYears: 8,
      nextSlot: 'Tomorrow 10:00 AM',
      feeSar: 200,
    ),
    DoctorCardData(
      id: 'doc-3',
      name: 'Dr. Ahmed Al-Zahrani',
      title: 'Dr',
      spec: 'Pediatrics Specialist',
      rating: 4.8,
      reviews: 35,
      expYears: 15,
      nextSlot: 'Today 5:30 PM',
      feeSar: 180,
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showBookingDialog(DoctorCardData doc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Book Appointment with ${doc.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Specialty: ${doc.spec}'),
            const SizedBox(height: 4),
            Text('Consultation Fee: SAR ${doc.feeSar.toStringAsFixed(0)}'),
            const SizedBox(height: 4),
            Text('Available Slot: ${doc.nextSlot}'),
            const SizedBox(height: 16),
            const Text(
              'Please log in as a Patient to confirm appointment booking.',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go('/login');
            },
            child: const Text('Login to Book'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MedConsult V2 Public Portal'),
        actions: [
          if (authState.isLoggedIn && user != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onPressed: () {
                  switch (user.role) {
                    case UserRole.PATIENT:
                      context.go('/patient/home');
                      break;
                    case UserRole.DOCTOR:
                      context.go('/doctor/schedule');
                      break;
                    case UserRole.CLINIC_ADMIN:
                      context.go('/clinic-admin/clinics');
                      break;
                    case UserRole.SYSTEM_ADMIN:
                      context.go('/system-admin');
                      break;
                  }
                },
                child: Text('Dashboard (${user.fullName})'),
              ),
            )
          else ...[
            TextButton(
              key: const Key('landing_login_btn'),
              onPressed: () => context.go('/login'),
              child: const Text('Sign In'),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ElevatedButton(
                key: const Key('landing_register_btn'),
                onPressed: () => context.go('/register'),
                child: const Text('Get Started'),
              ),
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero Section
            Container(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              color: AppTheme.darkSidebar,
              child: Column(
                children: [
                  const Text(
                    'Saudi Arabia\'s Leading Digital Health Platform',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Find verified doctors, explore clinics, and book tele-consultations effortlessly.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  const SizedBox(height: 32),

                  // Search Bar
                  Container(
                    constraints: const BoxConstraints(maxWidth: 600),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        const Icon(Icons.search, color: AppTheme.textMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            key: const Key('landing_search_input'),
                            controller: _searchController,
                            decoration: const InputDecoration(
                              hintText: 'Search doctor, specialty, or clinic...',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              fillColor: Colors.transparent,
                            ),
                          ),
                        ),
                        ElevatedButton(
                          key: const Key('landing_search_btn'),
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          onPressed: () => setState(() {}),
                          child: const Text('Search'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Specialty Filter Chips
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Browse by Specialty',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _specialties.map((spec) {
                      final isSelected = _selectedSpecialty == spec;
                      return ChoiceChip(
                        label: Text(spec),
                        selected: isSelected,
                        selectedColor: AppTheme.primaryTeal,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppTheme.textMain,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedSpecialty = spec);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),

                  // Doctor Cards Header
                  const Text(
                    'Featured Doctors & Specialists',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Doctor Cards Grid / List
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final filteredDocs = _mockDoctors.where((doc) {
                        final query = _searchController.text.trim().toLowerCase();
                        final matchesQuery = query.isEmpty ||
                            doc.name.toLowerCase().contains(query) ||
                            doc.spec.toLowerCase().contains(query);
                        final matchesSpec = _selectedSpecialty == 'All' || doc.spec.contains(_selectedSpecialty);
                        return matchesQuery && matchesSpec;
                      }).toList();

                      if (filteredDocs.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('No doctors match your criteria.'),
                          ),
                        );
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredDocs.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 30,
                                    backgroundColor: AppTheme.primaryLightTeal,
                                    child: Text(
                                      doc.name.split(' ').map((e) => e[0]).take(2).join(),
                                      style: const TextStyle(
                                        color: AppTheme.primaryTeal,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          doc.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textMain,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          doc.spec,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppTheme.primaryTeal,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(Icons.star, color: Colors.amber, size: 16),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${doc.rating} (${doc.reviews} reviews)',
                                              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                            ),
                                            const SizedBox(width: 12),
                                            const Icon(Icons.work_outline, size: 16, color: AppTheme.textMuted),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${doc.expYears} yrs exp',
                                              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'SAR ${doc.feeSar.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textMain,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        doc.nextSlot,
                                        style: const TextStyle(fontSize: 12, color: AppTheme.successGreen),
                                      ),
                                      const SizedBox(height: 10),
                                      ElevatedButton(
                                        onPressed: () => _showBookingDialog(doc),
                                        child: const Text('Book Appointment'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

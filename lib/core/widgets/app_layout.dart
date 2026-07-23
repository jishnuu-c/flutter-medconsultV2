import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../models/auth_models.dart';
import '../theme/app_theme.dart';

class MenuItemData {
  final String label;
  final String route;

  const MenuItemData({required this.label, required this.route});
}

class AppLayout extends ConsumerWidget {
  final Widget child;

  const AppLayout({super.key, required this.child});

  List<MenuItemData> _getMenuItems(UserRole? role) {
    if (role == null) return [];

    switch (role) {
      case UserRole.PATIENT:
        return const [
          MenuItemData(label: 'Home Dashboard', route: '/patient/home'),
          MenuItemData(label: 'My Medical Records (EMR)', route: '/patient/emr'),
          MenuItemData(label: 'Book Appointment', route: '/patient/book-appointment'),
          MenuItemData(label: 'Tele-Consultations', route: '/patient/consultations'),
          MenuItemData(label: 'My General Profile', route: '/patient/profile'),
          MenuItemData(label: 'Personal Health Metrics', route: '/patient/health-profile'),
        ];
      case UserRole.DOCTOR:
        return const [
          MenuItemData(label: 'My Professional Profile', route: '/doctor/profile'),
          MenuItemData(label: 'Consultation Schedule', route: '/doctor/schedule'),
          MenuItemData(label: 'My Consultations', route: '/doctor/consultations'),
          MenuItemData(label: 'Case Rooms', route: '/doctor/caserooms'),
          MenuItemData(label: 'Patient EMR Records', route: '/doctor/patients'),
          MenuItemData(label: 'Availability & Slots', route: '/doctor/availability'),
        ];
      case UserRole.CLINIC_ADMIN:
        return const [
          MenuItemData(label: 'Manage Clinics', route: '/clinic-admin/clinics'),
          MenuItemData(label: 'Manage Doctors', route: '/clinic-admin/doctors'),
        ];
      case UserRole.SYSTEM_ADMIN:
        return const [
          MenuItemData(label: 'Global Configurations', route: '/system-admin'),
        ];
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.currentUser;
    final menuItems = _getMenuItems(user?.role);
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    final sidebarWidget = Container(
      width: 260,
      color: AppTheme.darkSidebar,
      child: Column(
        children: [
          // Brand Section
          InkWell(
            onTap: () => context.go('/'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryTeal,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'MedConsult V2',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 1),

          // Menu items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                ...menuItems.map((item) {
                  final location = GoRouterState.of(context).uri.toString();
                  final isActive = location == item.route;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive ? AppTheme.primaryTeal : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      title: Text(
                        item.label,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white70,
                          fontSize: 14,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      dense: true,
                      onTap: () {
                        context.go(item.route);
                        if (!isDesktop) Navigator.of(context).pop();
                      },
                    ),
                  );
                }),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12, height: 1),
                ListTile(
                  leading: const Icon(Icons.public, color: Colors.white70, size: 20),
                  title: const Text(
                    'Public Portal Home',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  onTap: () {
                    context.go('/');
                    if (!isDesktop) Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),

          // Footer Logout Button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                minimumSize: const Size.fromHeight(44),
              ),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Logout'),
              onPressed: () {
                ref.read(authNotifierProvider.notifier).logout();
                context.go('/login');
              },
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      drawer: isDesktop ? null : Drawer(child: sidebarWidget),
      body: Row(
        children: [
          if (isDesktop) sidebarWidget,
          Expanded(
            child: Column(
              children: [
                // Top Header Bar
                Container(
                  height: 70,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: AppTheme.borderGray)),
                  ),
                  child: Row(
                    children: [
                      if (!isDesktop)
                        Builder(
                          builder: (ctx) => IconButton(
                            icon: const Icon(Icons.menu),
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                          ),
                        ),
                      const Text(
                        'Dashboard',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        icon: const Icon(Icons.public, size: 14),
                        label: const Text('View Public Portal'),
                        onPressed: () => context.go('/'),
                      ),
                      const Spacer(),
                      if (user != null) ...[
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: AppTheme.primaryLightTeal,
                          backgroundImage: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                              ? NetworkImage(user.avatarUrl!)
                              : null,
                          child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                              ? Text(
                                  user.initials,
                                  style: const TextStyle(
                                    color: AppTheme.primaryTeal,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.fullName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppTheme.textMain,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLightTeal,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                user.role.value.replaceAll('_', ' '),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.primaryDarkTeal,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.logout, color: AppTheme.dangerRed, size: 20),
                          tooltip: 'Logout',
                          onPressed: () {
                            ref.read(authNotifierProvider.notifier).logout();
                            context.go('/login');
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                // Main Content Viewport
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

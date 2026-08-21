import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../localization/language_service.dart';
import '../models/auth_models.dart';
import '../network/api_client.dart';
import '../theme/app_theme.dart';

/// Turns a relative avatar path (e.g. "/uploads/Users/avatar/x.jpg") returned
/// by the API into an absolute URL NetworkImage can load. Returns null when
/// there is nothing usable, so callers can fall back to the initials avatar.
String? _resolveAssetUrl(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final value = raw.trim();
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) return value;
  final base = kBaseUrl.endsWith('/')
      ? kBaseUrl.substring(0, kBaseUrl.length - 1)
      : kBaseUrl;
  final path = value.startsWith('/') ? value : '/$value';
  return '$base$path';
}

class MenuItemData {
  final String label;
  final String route;
  final IconData icon;
  final IconData? activeIcon;

  const MenuItemData({
    required this.label,
    required this.route,
    required this.icon,
    this.activeIcon,
  });
}

/// Allows sub-pages (e.g. Clinic Details) to request hiding the top header bar and bottom navigation bar.
final hideAppLayoutBarsProvider = StateProvider<bool>((ref) => false);

class AppLayout extends ConsumerWidget {
  final Widget child;

  const AppLayout({super.key, required this.child});

  List<MenuItemData> _getMenuItems(UserRole? role) {
    if (role == null) return [];

    // Mirrors Angular LayoutComponent.menuItems() — same labels, routes and
    // order per role.
    switch (role) {
      case UserRole.PATIENT:
        return const [
          MenuItemData(
              label: 'Home Dashboard',
              route: '/patient/home',
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded),
          MenuItemData(
              label: 'Browse Doctors',
              route: '/patient/doctors',
              icon: Icons.medical_services_outlined,
              activeIcon: Icons.medical_services_rounded),
          MenuItemData(
              label: 'Clinics & Branches',
              route: '/patient/clinics',
              icon: Icons.local_hospital_outlined,
              activeIcon: Icons.local_hospital_rounded),
          MenuItemData(
              label: 'Book Appointment',
              route: '/patient/book-appointment',
              icon: Icons.calendar_month_outlined,
              activeIcon: Icons.calendar_month_rounded),
          MenuItemData(
              label: 'My Appointments',
              route: '/patient/appointments',
              icon: Icons.event_note_outlined,
              activeIcon: Icons.event_note_rounded),
          MenuItemData(
              label: 'Tele-Consultations',
              route: '/patient/consultations',
              icon: Icons.forum_outlined,
              activeIcon: Icons.forum_rounded),
          MenuItemData(
              label: 'Medical Records (EMR)',
              route: '/patient/emr',
              icon: Icons.folder_shared_outlined,
              activeIcon: Icons.folder_shared_rounded),
          MenuItemData(
              label: 'Personal Health Metrics',
              route: '/patient/health-profile',
              icon: Icons.favorite_border_rounded,
              activeIcon: Icons.favorite_rounded),
          MenuItemData(
              label: 'My General Profile',
              route: '/patient/profile',
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded),
        ];
      case UserRole.DOCTOR:
        return const [
          MenuItemData(
              label: 'Professional Profile',
              route: '/doctor/profile',
              icon: Icons.medical_services_outlined,
              activeIcon: Icons.medical_services_rounded),
          MenuItemData(
              label: 'Consultation Schedule',
              route: '/doctor/schedule',
              icon: Icons.calendar_month_outlined,
              activeIcon: Icons.calendar_month_rounded),
          MenuItemData(
              label: 'Appointments History',
              route: '/doctor/appointments-history',
              icon: Icons.folder_shared_outlined,
              activeIcon: Icons.folder_shared_rounded),
          MenuItemData(
              label: 'My Consultations',
              route: '/doctor/consultations',
              icon: Icons.forum_outlined,
              activeIcon: Icons.forum_rounded),
          MenuItemData(
              label: 'Case Rooms',
              route: '/doctor/caserooms',
              icon: Icons.forum_outlined,
              activeIcon: Icons.forum_rounded),
          MenuItemData(
              label: 'Patient EMR Records',
              route: '/doctor/patients',
              icon: Icons.folder_shared_outlined,
              activeIcon: Icons.folder_shared_rounded),
          MenuItemData(
              label: 'Availability & Slots',
              route: '/doctor/availability',
              icon: Icons.favorite_border_rounded,
              activeIcon: Icons.favorite_rounded),
        ];
      case UserRole.CLINIC_ADMIN:
        return const [
          MenuItemData(
              label: 'Dashboard',
              route: '/clinic-admin/dashboard',
              icon: Icons.dashboard_outlined,
              activeIcon: Icons.dashboard_rounded),
          MenuItemData(
              label: 'My Clinics',
              route: '/clinic-admin/clinics',
              icon: Icons.local_hospital_outlined,
              activeIcon: Icons.local_hospital_rounded),
          MenuItemData(
              label: 'Doctors Roster',
              route: '/clinic-admin/doctors',
              icon: Icons.medical_services_outlined,
              activeIcon: Icons.medical_services_rounded),
        ];
      case UserRole.SYSTEM_ADMIN:
        return const [
          MenuItemData(
              label: 'Global Configurations',
              route: '/system-admin',
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings_rounded),
        ];
    }
  }

  // Subset of _getMenuItems shown as quick-access bottom nav on mobile.
  List<MenuItemData> _getBottomNavItems(List<MenuItemData> menuItems, UserRole? role) {
    if (role == UserRole.PATIENT) {
      return const [
        MenuItemData(
            label: 'Home',
            route: '/patient/home',
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded),
        MenuItemData(
            label: 'Doctors',
            route: '/patient/doctors',
            icon: Icons.medical_services_outlined,
            activeIcon: Icons.medical_services_rounded),
        MenuItemData(
            label: 'Clinics',
            route: '/patient/clinics',
            icon: Icons.local_hospital_outlined,
            activeIcon: Icons.local_hospital_rounded),
        MenuItemData(
            label: 'Consultations',
            route: '/patient/consultations',
            icon: Icons.forum_outlined,
            activeIcon: Icons.forum_rounded),
        MenuItemData(
            label: 'Profile',
            route: '/patient/profile',
            icon: Icons.person_outline_rounded,
            activeIcon: Icons.person_rounded),
      ];
    }
    if (menuItems.length <= 5) return menuItems;
    return menuItems.take(5).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.currentUser;
    final menuItems = _getMenuItems(user?.role);
    final bottomNavItems = _getBottomNavItems(menuItems, user?.role);
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final location = GoRouterState.of(context).uri.toString();
    final bottomNavIndex = bottomNavItems.indexWhere(
      (item) => location == item.route || (item.route != '/patient/home' && location.startsWith(item.route)),
    );

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
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Material(
                      color: isActive
                          ? AppTheme.primaryTeal
                          // Transparent Material can't guarantee the ink
                          // splash is visible, hence Flutter's "ListTile
                          // background color or ink splashes may be
                          // invisible" warning on every inactive tile tap.
                          // Fall through to the sidebar's own opaque
                          // background instead of wrapping in a see-through
                          // Material here.
                          : Colors.transparent,
                      type: isActive
                          ? MaterialType.canvas
                          : MaterialType.transparency,
                      child: ListTile(
                        leading: Icon(
                          item.icon,
                          size: 19,
                          color: isActive ? Colors.white : Colors.white70,
                        ),
                        title: Text(
                          item.label.tr,
                          style: TextStyle(
                            color: isActive ? Colors.white : Colors.white70,
                            fontSize: 14,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        dense: true,
                        onTap: () {
                          context.go(item.route);
                          if (!isDesktop) Navigator.of(context).pop();
                        },
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12, height: 1),
                ListTile(
                  leading:
                      const Icon(Icons.public, color: Colors.white70, size: 20),
                  title: Text(
                    'Public Portal Home'.tr,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  onTap: () {
                    context.go('/');
                    if (!isDesktop) Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),

          // Language Switcher in Sidebar (matching Angular layout.component.html)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.language, size: 16, color: AppTheme.primaryTeal),
              label: Text(
                ref.watch(isArabicProvider) ? 'English' : 'العربية',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: () {
                ref.read(languageNotifierProvider.notifier).toggleLanguage();
              },
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.logout, size: 18),
              label: Text('Logout'.tr),
              onPressed: () {
                ref.read(authNotifierProvider.notifier).logout();
                context.go('/login');
              },
            ),
          ),
        ],
      ),
    );

    final hideBarsExplicit = ref.watch(hideAppLayoutBarsProvider);
    final hideBars = hideBarsExplicit || location.contains('/patient/clinics/');

    return Scaffold(
      drawer: (isDesktop || hideBars) ? null : Drawer(child: sidebarWidget),
      bottomNavigationBar: (!hideBars && !isDesktop && bottomNavItems.length >= 2)
          ? Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
                border: const Border(
                  top: BorderSide(color: AppTheme.borderGray, width: 0.8),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 56,
                  child: BottomNavigationBar(
                    type: BottomNavigationBarType.fixed,
                    backgroundColor: Colors.white,
                    elevation: 0,
                    showSelectedLabels: false,
                    showUnselectedLabels: false,
                    selectedFontSize: 0,
                    unselectedFontSize: 0,
                    selectedItemColor: AppTheme.primaryTeal,
                    unselectedItemColor: const Color(0xFF94A3B8),
                    currentIndex: bottomNavIndex < 0 ? 0 : bottomNavIndex,
                    onTap: (index) => context.go(bottomNavItems[index].route),
                    items: bottomNavItems
                        .map(
                          (item) => BottomNavigationBarItem(
                            icon: Icon(item.icon, size: 24),
                            activeIcon:
                                Icon(item.activeIcon ?? item.icon, size: 26),
                            label: '',
                            tooltip: item.label,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Row(
          children: [
            if (isDesktop && !hideBarsExplicit) sidebarWidget,
            Expanded(
              child: Column(
                children: [
                  // Top Header Bar
                  if (!hideBars)
                    Container(
                      height: 64,
                      padding: EdgeInsets.symmetric(
                          horizontal: isDesktop ? 24 : 12),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                            bottom: BorderSide(color: AppTheme.borderGray)),
                      ),
                      child: Row(
                        children: [
                          if (!isDesktop) ...[
                            Builder(
                              builder: (ctx) => IconButton(
                                icon: const Icon(Icons.menu),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 36, minHeight: 36),
                                onPressed: () => Scaffold.of(ctx).openDrawer(),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            'Dashboard'.tr,
                            style: TextStyle(
                              fontSize: isDesktop ? 18 : 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textMain,
                            ),
                          ),
                          if (isDesktop) ...[
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                              icon: const Icon(Icons.public, size: 14),
                              label: Text('View Public Portal'.tr),
                              onPressed: () => context.go('/'),
                            ),
                          ],
                          const Spacer(),
                          // Quick Language Toggle Pill
                          InkWell(
                            onTap: () {
                              ref
                                  .read(languageNotifierProvider.notifier)
                                  .toggleLanguage();
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.language,
                                      size: 14, color: Color(0xFF0F766E)),
                                  const SizedBox(width: 4),
                                  Text(
                                    ref.watch(isArabicProvider)
                                        ? 'English'
                                        : 'العربية',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F766E),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (user != null) ...[
                            CircleAvatar(
                              radius: isDesktop ? 18 : 15,
                              backgroundColor: AppTheme.primaryLightTeal,
                              backgroundImage:
                                  _resolveAssetUrl(user.avatarUrl) != null
                                      ? NetworkImage(
                                          _resolveAssetUrl(user.avatarUrl)!)
                                      : null,
                              child: _resolveAssetUrl(user.avatarUrl) == null
                                  ? Text(
                                      user.initials,
                                      style: TextStyle(
                                        color: AppTheme.primaryTeal,
                                        fontWeight: FontWeight.bold,
                                        fontSize: isDesktop ? 12 : 10,
                                      ),
                                    )
                                  : null,
                            ),
                            if (isDesktop) ...[
                              const SizedBox(width: 12),
                              Flexible(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      user.fullName,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: AppTheme.textMain,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
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
                              ),
                            ],
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.logout,
                                  color: AppTheme.dangerRed, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 32, minHeight: 32),
                              tooltip: 'Logout'.tr,
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
      ),
    );
  }
}
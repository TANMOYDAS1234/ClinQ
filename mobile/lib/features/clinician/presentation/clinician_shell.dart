import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom-navigation scaffold for the clinician (doctor + staff) app:
/// Home · Patients · Nutrition · Profile.
///
/// Home is the dashboard — the clinic's pulse at a glance. Patients lists the
/// care conversations (doctor↔patient), each row leading into that thread.
/// Nutrition lists the dietician↔patient conversations so the doctor can watch
/// and step in to guide. Clinical tools live in the Profile hub.
class ClinicianShell extends StatelessWidget {
  const ClinicianShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      // Labels kept to single short words so none wrap on a narrow phone.
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded),
            // 'Care' rather than 'Patients': it pairs with the Nutrition tab as
            // the clinic's two conversation streams (care vs nutrition), which is
            // also how the threads are modelled server-side.
            label: 'Care',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu_rounded),
            label: 'Nutrition',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

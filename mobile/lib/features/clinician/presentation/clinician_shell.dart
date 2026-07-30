import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom-navigation scaffold for the clinician (doctor + staff) app:
/// Messages · Profile.
///
/// The first tab is named for what the doctor comes here to do. It lists
/// patients, but every row leads into that patient's conversation, and reaching
/// someone is the daily job — reviewing a chart is the occasional one, and it
/// is one tap further in. Appointments, clinics and clinical tools live in the
/// Profile hub.
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
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum_rounded),
            label: 'Messages',
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

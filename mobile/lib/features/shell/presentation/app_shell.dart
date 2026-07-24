import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/gen/app_localizations.dart';

/// Bottom navigation scaffold for the five main tabs (Home / Chat / Track /
/// Care / Profile). Wraps a [StatefulNavigationShell] so each branch keeps
/// its own navigation stack and scroll position when switching tabs.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: l10n.navHome),
          NavigationDestination(icon: const Icon(Icons.chat_bubble_outline_rounded), selectedIcon: const Icon(Icons.chat_bubble_rounded), label: l10n.navChat),
          NavigationDestination(icon: const Icon(Icons.show_chart_rounded), selectedIcon: const Icon(Icons.show_chart_rounded), label: l10n.navTrack),
          NavigationDestination(icon: const Icon(Icons.favorite_outline_rounded), selectedIcon: const Icon(Icons.favorite_rounded), label: l10n.navCare),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: l10n.navProfile),
        ],
      ),
    );
  }
}

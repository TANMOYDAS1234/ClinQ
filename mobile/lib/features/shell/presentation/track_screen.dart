import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../glucose/presentation/glucose_screen.dart';
import '../../medications/presentation/medications_screen.dart';

/// Bottom-nav "Track" tab: glucose logging/trends and today's medication
/// schedule, as two sub-tabs under one shell entry.
class TrackScreen extends StatelessWidget {
  const TrackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(l10n.navTrack),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.glucoseTitle),
              Tab(text: l10n.medsTitle),
            ],
          ),
        ),
        body: const TabBarView(children: [GlucoseScreen(), MedicationsScreen()]),
      ),
    );
  }
}

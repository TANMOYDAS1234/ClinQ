import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/diet_models.dart';
import 'dietician_providers.dart';

Color dietRiskColor(String band) => switch (band) {
      'critical' => AppColors.danger,
      'high' => const Color(0xFFEA580C),
      'moderate' => AppColors.warning,
      _ => AppColors.success,
    };

/// The dietician's home: the patients a doctor has assigned to them, with the
/// ones whose food log is due for review surfaced first.
class DieticianPatientsScreen extends ConsumerStatefulWidget {
  const DieticianPatientsScreen({super.key});

  @override
  ConsumerState<DieticianPatientsScreen> createState() => _DieticianPatientsScreenState();
}

class _DieticianPatientsScreenState extends ConsumerState<DieticianPatientsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Name or phone. A dietician covering every patient in the clinic scrolls a
  /// list of hundreds otherwise, and the one they want is the one who just
  /// messaged them.
  List<DietPatient> _filter(List<DietPatient> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((p) => p.name.toLowerCase().contains(q) || p.phone.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(dietPatientsProvider);
    final user = ref.watch(authControllerProvider).user;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.md,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My patients', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.accentOn(context))),
            Text('Dietician · ${user?.name ?? ''}', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          // `go`, not `push`: Profile is one of this shell's own tabs, so
          // pushing it would stack a second copy over the Patients tab with a
          // back arrow instead of simply switching to it.
          GestureDetector(
            onTap: () => context.go('/dietician/profile'),
            child: UserAvatar(
              name: user?.name ?? '',
              avatarUrl: user?.avatarUrl,
              accent: AppColors.accentOn(context),
              size: 38,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 15.5),
              decoration: InputDecoration(
                hintText: 'Search patients by name or number…',
                prefixIcon: Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
                filled: true,
                fillColor: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(dietPatientsProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            const Center(child: Text('Could not load patients')),
            const SizedBox(height: AppSpacing.sm),
            Center(child: OutlinedButton(onPressed: () => ref.invalidate(dietPatientsProvider), child: const Text('Retry'))),
          ]),
          data: (patients) {
            if (patients.isEmpty) {
              return ListView(children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.22),
                Icon(Icons.restaurant_menu_rounded, size: 54, color: scheme.outlineVariant),
                const SizedBox(height: AppSpacing.md),
                const Center(child: Text('No patients assigned yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                const SizedBox(height: 6),
                Center(child: Text('A doctor will assign patients to you.', style: TextStyle(color: scheme.onSurfaceVariant))),
              ]);
            }
            final matched = _filter(patients);
            if (matched.isEmpty) {
              return ListView(children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.22),
                Icon(Icons.search_off_rounded, size: 54, color: scheme.outlineVariant),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: Text(
                    'No patient matches “${_query.trim()}”',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ]);
            }
            final sorted = [...matched]..sort((a, b) => (b.reviewDue ? 1 : 0).compareTo(a.reviewDue ? 1 : 0));
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: sorted.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) => _PatientCard(patient: sorted[i]),
            );
          },
        ),
      ),
    );
  }

}

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.patient});

  final DietPatient patient;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = patient;
    final risk = AppColors.toneOn(context, dietRiskColor(p.riskBand));

    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/dietician/patients/${p.id}', extra: p.name),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              UserAvatar(name: p.name, avatarUrl: p.avatarUrl, accent: AppColors.accentOn(context), size: 46),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _pill(p.riskBand.isEmpty ? 'low' : '${p.riskBand[0].toUpperCase()}${p.riskBand.substring(1)} risk', risk),
                        if (p.diabetesType != null && p.diabetesType!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(p.diabetesType!, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (p.reviewDue)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.warningOn(context).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: const Text('Review due', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFFB45309))),
                ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      );
}

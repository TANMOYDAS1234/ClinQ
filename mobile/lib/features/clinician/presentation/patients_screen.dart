import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_spacing.dart';
import '../domain/clinician_models.dart';
import 'clinician_providers.dart';
import 'widgets/clinician_visuals.dart';

/// The doctor's patient directory: searchable, sortable, risk-segmented.
class PatientsScreen extends ConsumerStatefulWidget {
  const PatientsScreen({super.key});

  @override
  ConsumerState<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends ConsumerState<PatientsScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  String _sort = 'risk';
  String? _riskBand;
  Timer? _debounce;

  static const _bands = [
    (null, 'All'),
    ('critical', 'Critical'),
    ('high', 'High'),
    ('moderate', 'Moderate'),
    ('low', 'Low'),
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _search = v.trim());
    });
  }

  PatientsQuery get _query => (riskBand: _riskBand, search: _search.isEmpty ? null : _search, sort: _sort);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(patientsProvider(_query));

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Patients'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'risk', child: Text('Sort by risk')),
              PopupMenuItem(value: 'name', child: Text('Sort by name')),
              PopupMenuItem(value: 'recent', child: Text('Sort by recent activity')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search name or phone',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  itemCount: _bands.length,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    final (value, label) = _bands[i];
                    return ChoiceChip(
                      label: Text(label),
                      selected: _riskBand == value,
                      onSelected: (_) => setState(() => _riskBand = value),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(patientsProvider(_query)),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load patients'),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(onPressed: () => ref.invalidate(patientsProvider(_query)), child: const Text('Retry')),
              ],
            ),
          ),
          data: (paged) {
            if (paged.items.isEmpty) {
              return ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                  Icon(Icons.person_search_outlined, size: 56, color: scheme.outlineVariant),
                  const SizedBox(height: AppSpacing.md),
                  const Center(child: Text('No patients found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: paged.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) => _PatientRow(
                patient: paged.items[i],
                onTap: () => context.push('/clinician/patients/${paged.items[i].id}'),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PatientRow extends StatelessWidget {
  const _PatientRow({required this.patient, required this.onTap});

  final PatientListItem patient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = patient;
    final band = riskBandColor(p.riskBand);
    final initial = (p.name.isNotEmpty ? p.name[0] : '?').toUpperCase();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: band.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Center(child: Text(initial, style: TextStyle(fontWeight: FontWeight.w800, color: band, fontSize: 18))),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    p.lastReadingValue != null
                        ? 'Last: ${p.lastReadingValue} mg/dL · ${p.lastReadingAt != null ? DateFormat('d MMM').format(p.lastReadingAt!) : ''}'
                        : p.phone,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MiniPill(label: riskBandLabel(p.riskBand), color: band),
                if (p.openAlertCount > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFDC2626)),
                      const SizedBox(width: 2),
                      Text('${p.openAlertCount}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

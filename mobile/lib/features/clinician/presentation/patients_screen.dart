import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/authed_image.dart';
import '../../../shared/widgets/markdown_text.dart';
import '../../../core/utils/auth_validators.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/clinician_repository.dart';
import '../domain/clinician_models.dart';
import 'clinician_providers.dart';

/// The clinician's inbox.
///
/// Deliberately a conversation list rather than a clinical directory: reaching a
/// waiting patient is the daily job, and the question the doctor opens the app
/// to answer is "who is waiting on me", not "who has the worst HbA1c". Risk and
/// alerts still appear, but as marks on a row, not as the organising principle.
///
/// Rows sort unread-first, then by most recent message, so the list orders
/// itself around that question without the doctor having to filter.
class PatientsScreen extends ConsumerStatefulWidget {
  const PatientsScreen({super.key});

  @override
  ConsumerState<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends ConsumerState<PatientsScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _search = '';
  Timer? _debounce;
  Timer? _poll;

  /// Only unread conversations, when the doctor wants the queue and nothing else.
  bool _unreadOnly = false;

  /// The inbox is only useful if it is current. There is no socket, so it
  /// re-reads on a timer while on screen and immediately on resume.
  ///
  /// Matched to the conversation screens rather than the twenty seconds a list
  /// view would normally justify: this is the screen a doctor sits on while
  /// waiting for a patient to reply, and a message that takes twenty seconds to
  /// appear reads as the app being broken.
  static const _pollInterval = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the background is the likeliest moment for a new message
    // to have arrived, so check at once rather than waiting out the timer.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(patientsProvider(_query));
    ref.invalidate(worklistProvider);
  }

  /// Registers a walk-in at the desk. Some patients are enrolled on a clinic
  /// phone rather than downloading the app first, and without this the doctor
  /// has no way to start a record for them.
  Future<void> _addPatient() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewPatientSheet(),
    );
    if (created == true) _refresh();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _search = v.trim());
    });
  }

  PatientsQuery get _query =>
      (riskBand: null, search: _search.isEmpty ? null : _search, sort: 'name');

  /// Unread first, then newest message. A patient who has never written sinks
  /// to the bottom — there is nothing waiting there.
  List<PatientListItem> _ordered(List<PatientListItem> items) {
    final list = [...items];
    list.sort((a, b) {
      if ((a.unreadCount > 0) != (b.unreadCount > 0)) return a.unreadCount > 0 ? -1 : 1;
      final at = a.lastMessage?.at;
      final bt = b.lastMessage?.at;
      if (at == null && bt == null) return a.name.compareTo(b.name);
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(patientsProvider(_query));
    final scheme = Theme.of(context).colorScheme;

    final worklist = ref.watch(worklistProvider).valueOrNull;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _InboxHeader(onSearch: () => _searchFocus.requestFocus()),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.xl,
                  ),
                  children: [
                    const _Greeting(),
                    const SizedBox(height: AppSpacing.md),
                    _NewPatientButton(onTap: _addPatient),
                    const SizedBox(height: AppSpacing.lg),
                    if (worklist != null) ...[
                      _StatTrio(worklist: worklist),
                      const SizedBox(height: AppSpacing.md),
                      if (worklist.queue.isNotEmpty) ...[
                        _ActionQueue(worklist: worklist),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      if (worklist.recentMeals.isNotEmpty) ...[
                        _LatestMeals(meals: worklist.recentMeals),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ],

                    // The inbox stays on this tab. The overview above says what
                    // is outstanding; this is still how the doctor reaches a
                    // patient who is waiting on a reply.
                    _SectionBar(
                      unreadOnly: _unreadOnly,
                      onToggleFilter: () => setState(() => _unreadOnly = !_unreadOnly),
                    ),
                    _SearchField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      onChanged: _onSearchChanged,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    async.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (_, _) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            const Text('Could not load messages'),
                            const SizedBox(height: AppSpacing.sm),
                            OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
                          ],
                        ),
                      ),
                      data: (paged) {
                        var items = _ordered(paged.items);
                        if (_unreadOnly) items = items.where((p) => p.unreadCount > 0).toList();

                        if (items.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              children: [
                                Icon(
                                  _unreadOnly ? Icons.mark_email_read_outlined : Icons.forum_outlined,
                                  size: 52,
                                  color: scheme.outlineVariant,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  _unreadOnly ? 'Nothing unread' : 'No conversations yet',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          );
                        }

                        // One grouped card with hairline dividers, rather than a
                        // separate floating card per patient — a long inbox of
                        // detached cards reads as clutter.
                        return Container(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.22)),
                            // Matches the settings groups, so the two panels
                            // read as one product rather than two apps.
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 14,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (var i = 0; i < items.length; i++) ...[
                                if (i > 0)
                                  // Indented past the avatar, so the list reads
                                  // as one column of people rather than a stack
                                  // of separate strips.
                                  Padding(
                                    padding: const EdgeInsets.only(left: 76),
                                    child: Divider(
                                      height: 1,
                                      color: scheme.outlineVariant.withValues(alpha: 0.22),
                                    ),
                                  ),
                                _ConversationRow(
                                  patient: items[i],
                                  onTap: () => context.push(
                                    '/clinician/patients/${items[i].id}/thread',
                                    extra: items[i].name,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Greeting -------------------------------------------------------------

class _Greeting extends ConsumerWidget {
  const _Greeting();

  static String _partOfDay() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authControllerProvider).user;
    final name = user?.name ?? '';
    // Their own record already says "Dr."; prefixing again gives "Dr. Dr. Dey".
    final display = name.toLowerCase().startsWith('dr') ? name : 'Dr. $name';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_partOfDay()}, $display',
          style: const TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            height: 1.2,
            letterSpacing: -0.5,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Here is your daily clinical overview.',
          style: TextStyle(fontSize: 15.5, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _NewPatientButton extends StatelessWidget {
  const _NewPatientButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text('New Patient', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ---- Counts ---------------------------------------------------------------

class _StatTrio extends StatelessWidget {
  const _StatTrio({required this.worklist});

  final DoctorWorklist worklist;

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight, not a bare stretch: inside a ListView the cross-axis is
    // unbounded, so stretching makes the boxes infinitely tall and pushes the
    // action queue and the inbox below them out of reach.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _StatBox(label: 'Patients', value: worklist.patients)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _StatBox(
              label: 'Reviews',
              value: worklist.reviews,
              // Tinted only when there is something to do. A permanently red
              // box stops meaning anything.
              accent: worklist.reviews > 0 ? AppColors.danger : null,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _StatBox(
              label: 'Plans',
              value: worklist.plans,
              accent: worklist.plans > 0 ? AppColors.primary : null,
              tint: AppColors.infoBg,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value, this.accent, this.tint});

  final String label;
  final int value;
  final Color? accent;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = accent ?? scheme.outlineVariant;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: accent == null
            ? scheme.surfaceContainerLowest
            : (tint ?? accent!.withValues(alpha: 0.06)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border.withValues(alpha: accent == null ? 0.7 : 0.45)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: accent ?? scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Action queue ---------------------------------------------------------

class _ActionQueue extends StatelessWidget {
  const _ActionQueue({required this.worklist});

  final DoctorWorklist worklist;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outstanding = worklist.reviews + worklist.plans;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(Icons.assignment_outlined, size: 21, color: scheme.onSurface),
                const SizedBox(width: AppSpacing.sm),
                const Text('Action Queue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(
                  '$outstanding Pending',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          for (final item in worklist.queue) ...[
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
            _QueueRow(item: item),
          ],
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.item});

  final WorklistItem item;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final needsPlan = item.needsPlan;

    return InkWell(
      onTap: () => context.push('/clinician/patients/${item.patientId}/thread', extra: item.name),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: needsPlan ? AppColors.infoBg : AppColors.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Text(
                _initials(item.name),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${needsPlan ? 'Create Plan' : 'Review Due'} · ${item.days}d',
                    style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (needsPlan)
              Material(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => context.push(
                    '/clinician/patients/${item.patientId}/prescribe',
                    extra: item.name,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: Text(
                      'Create',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              )
            else
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ---- Latest meals ---------------------------------------------------------

class _LatestMeals extends StatelessWidget {
  const _LatestMeals({required this.meals});

  final List<RecentMeal> meals;

  static String _ago(DateTime? at) {
    if (at == null) return '';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.restaurant_rounded, size: 21, color: scheme.onSurface),
            const SizedBox(width: AppSpacing.sm),
            const Text('Latest Meals', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: meals.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) {
              final meal = meals[i];
              return SizedBox(
                width: 190,
                child: Material(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push('/clinician/patients/${meal.patientId}'),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              SizedBox(
                                height: 118,
                                width: double.infinity,
                                child: meal.photoUrl != null
                                    ? AuthedImage(path: meal.photoUrl!, fit: BoxFit.cover)
                                    : Container(
                                        color: scheme.surfaceContainerHighest,
                                        child: Icon(
                                          Icons.restaurant_menu_rounded,
                                          size: 30,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                              ),
                              if (meal.mealType.isNotEmpty)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _label(meal.mealType),
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  meal.patientName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _ago(meal.createdAt),
                                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String _label(String mealType) =>
      mealType.isEmpty ? '' : mealType[0].toUpperCase() + mealType.substring(1);
}

// ---- New patient ----------------------------------------------------------

/// Enrols a patient from the clinic side. Validated to the same rules as
/// self-registration, so a desk-created account is not a second-class one.
class _NewPatientSheet extends ConsumerStatefulWidget {
  const _NewPatientSheet();

  @override
  ConsumerState<_NewPatientSheet> createState() => _NewPatientSheetState();
}

class _NewPatientSheetState extends ConsumerState<_NewPatientSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  String? _nameError;
  String? _phoneError;
  String? _passwordError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    final password = _password.text;

    setState(() {
      _nameError = name.length < 2 ? 'Enter the patient\'s full name.' : null;
      _phoneError = (digits.length != 10 || !RegExp(r'^[6-9]\d{9}$').hasMatch(digits))
          ? 'Enter a valid 10-digit mobile number.'
          : null;
      _passwordError = password.length < 8 ? 'At least 8 characters.' : null;
    });
    if (_nameError != null || _phoneError != null || _passwordError != null) return;

    setState(() => _saving = true);
    try {
      await ref.read(clinicianRepositoryProvider).createPatient(
        name: name,
        phone: '${AuthValidators.countryCode}$digits',
        password: password,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _phoneError = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New patient', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'They can sign in with this number and password.',
            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Full name', errorText: _nameError),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            decoration: InputDecoration(
              labelText: 'Mobile number',
              prefixText: '${AuthValidators.countryCode} ',
              counterText: '',
              errorText: _phoneError,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Temporary password', errorText: _passwordError),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Text('Create'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Brand row. Uses the app's own mark, not a generic medical cross.
class _InboxHeader extends ConsumerWidget {
  const _InboxHeader({required this.onSearch});

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authControllerProvider).user;

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          // The app's own emblem, not a generic medical cross.
          Image.asset(
            'assets/brand/logo_emblem.png',
            height: 30,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.forum_rounded, size: 26, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          const Text(
            'ClinQ',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Search patients',
            onPressed: onSearch,
            icon: Icon(Icons.search_rounded, size: 25, color: scheme.onSurface),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: () => context.push('/clinician/more'),
            child: UserAvatar(
              name: user?.name ?? '',
              avatarUrl: user?.avatarUrl,
              accent: AppColors.primary,
              size: 38,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged, this.focusNode});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.zero,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 15.5),
        decoration: InputDecoration(
          hintText: 'Search patients or messages…',
          prefixIcon: Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
          filled: true,
          fillColor: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
          ),
        ),
      ),
    );
  }
}

class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.unreadOnly, required this.onToggleFilter});

  final bool unreadOnly;
  final VoidCallback onToggleFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Patient Messages',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.2),
            ),
          ),
          TextButton(
            onPressed: onToggleFilter,
            child: Text(
              unreadOnly ? 'Show all' : 'Unread',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// One conversation. Reads top-to-bottom as: who, when, what was last said,
/// and whether it needs the doctor.
class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.patient, required this.onTap});

  final PatientListItem patient;
  final VoidCallback onTap;

  /// `10:42 AM` today, `Yesterday`, a weekday within the week, else `12 Oct`.
  String _stamp(DateTime at) {
    final now = DateTime.now();
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) {
      final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
      return '$h:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}';
    }
    if (diff == 1) return 'Yesterday';
    if (diff < 7) {
      return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][at.weekday - 1];
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${at.day} ${months[at.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final msg = patient.lastMessage;
    final unread = patient.unreadCount > 0;
    final emergency = msg?.urgency == 'emergency' || msg?.urgency == 'urgent';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(
              name: patient.name,
              avatarUrl: patient.avatarUrl,
              accent: emergency ? AppColors.danger : AppColors.primary,
              size: 48,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          patient.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16.5,
                            // Unread rows carry the weight, so the queue is
                            // visible without reading a single word.
                            fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (msg != null)
                        Text(
                          _stamp(msg.at),
                          style: TextStyle(
                            fontSize: 13,
                            color: unread ? AppColors.primary : scheme.onSurfaceVariant,
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (msg == null)
                                const TextSpan(text: 'No messages yet')
                              else ...[
                                // Say who spoke, so "answered" and "waiting" are
                                // distinguishable at a glance.
                                if (!msg.fromPatient) const TextSpan(text: 'You: '),
                                // A subtle monochrome icon for a media turn —
                                // premium, not a cheap emoji.
                                if (msg.mediaType != null)
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Icon(
                                        _mediaIcon(msg.mediaType!),
                                        size: 15,
                                        color: unread ? scheme.onSurface : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                TextSpan(text: MarkdownText.toPreview(msg.preview)),
                              ],
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            height: 1.35,
                            color: msg == null
                                ? scheme.outline
                                : unread
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      // WhatsApp-style unread count: a green disc with just the
                      // number, on the right of the preview line. Expands to a
                      // pill for two digits, "99+" beyond.
                      if (unread) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.all(Radius.circular(11)),
                          ),
                          child: Text(
                            patient.unreadCount > 99 ? '99+' : '${patient.unreadCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (emergency) ...[
                    const SizedBox(height: 8),
                    const _Chip(
                      label: 'Needs attention',
                      fg: AppColors.danger,
                      bg: AppColors.dangerBg,
                      icon: Icons.priority_high_rounded,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Subtle inbox-preview icon for a media turn — a monochrome Material glyph, not
/// an emoji, so the row reads as premium.
IconData _mediaIcon(String type) {
  switch (type) {
    case 'voice':
      return Icons.mic_none_rounded;
    case 'photo':
      return Icons.photo_camera_rounded;
    case 'pdf':
      return Icons.picture_as_pdf_rounded;
    case 'document':
      return Icons.description_rounded;
    default:
      return Icons.attach_file_rounded;
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.fg, required this.bg, required this.icon});

  final String label;
  final Color fg;
  final Color bg;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

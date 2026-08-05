import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/auth_validators.dart';
import '../../../shared/providers/core_providers.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../data/clinician_repository.dart';

final _dieticiansProvider = FutureProvider.autoDispose<List<_Dietician>>((ref) async {
  final data = await ref.read(apiClientProvider).getJson('/doctor/dieticians');
  final items = (data['items'] as List?) ?? const [];
  return items.whereType<Map<String, dynamic>>().map(_Dietician.fromJson).toList();
});

/// How often a patient's food log should be reviewed, clinic-wide.
final _reviewIntervalProvider = FutureProvider.autoDispose<int>((ref) async {
  final data = await ref.read(apiClientProvider).getJson('/doctor/settings');
  return (data['dietReviewIntervalDays'] as num?)?.toInt() ?? 14;
});

/// The clinic's dieticians.
///
/// A dietician added here covers every patient straight away — a clinic has one
/// or two of them and hundreds of patients, so requiring the doctor to assign
/// each patient by hand made "nobody is watching this patient's diet" the
/// default and left it to memory to fix.
class DieticiansScreen extends ConsumerStatefulWidget {
  const DieticiansScreen({super.key});

  @override
  ConsumerState<DieticiansScreen> createState() => _DieticiansScreenState();
}

class _DieticiansScreenState extends ConsumerState<DieticiansScreen> {
  Future<void> _add() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddDieticianSheet(),
    );
    if (created == true) ref.invalidate(_dieticiansProvider);
  }

  Future<void> _editInterval(int current) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _IntervalSheet(current: current),
    );
    if (picked == null) return;

    try {
      await ref.read(apiClientProvider).patchJson(
        '/doctor/settings',
        body: {'dietReviewIntervalDays': picked},
      );
      ref.invalidate(_reviewIntervalProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(_dieticiansProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dieticians')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add dietician'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_dieticiansProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            children: [
              const SizedBox(height: 140),
              const Center(child: Text('Could not load dieticians')),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: OutlinedButton(
                  onPressed: () => ref.invalidate(_dieticiansProvider),
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
          data: (items) => ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 100),
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.infoBg,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 19, color: scheme.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'A dietician you add here sees every patient and can write a '
                        'diet plan for any of them. Set how often a patient’s food log '
                        'should be reviewed on that patient’s record.',
                        style: TextStyle(fontSize: 13.5, height: 1.45, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Clinic-wide, not per patient: with one dietician covering
              // hundreds of patients, a cadence set per patient meant almost
              // every patient had none, and so was never due for review.
              Consumer(
                builder: (context, ref, _) {
                  final days = ref.watch(_reviewIntervalProvider).valueOrNull;
                  return Material(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                      onTap: days == null ? null : () => _editInterval(days),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: AppColors.accentSoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.event_repeat_outlined,
                                size: 21,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Food-log review',
                                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    days == null
                                        ? 'Loading…'
                                        : 'Every $days days, for every patient',
                                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            if (days != null)
                              Text(
                                'Change',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    children: [
                      Icon(Icons.restaurant_menu_rounded, size: 50, color: scheme.outlineVariant),
                      const SizedBox(height: AppSpacing.md),
                      const Text(
                        'No dieticians yet',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add one and they can start guiding your patients.',
                        style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0)
                          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: 6,
                          ),
                          leading: UserAvatar(
                            name: items[i].name,
                            avatarUrl: null,
                            accent: AppColors.primary,
                            size: 44,
                          ),
                          title: Text(
                            items[i].name,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            items[i].phone,
                            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picks the clinic-wide review cadence. Preset chips rather than a free number
/// field: the useful answers are a handful of intervals, and "every 3 days"
/// typed by accident would flood the dietician's queue with the whole clinic.
class _IntervalSheet extends StatefulWidget {
  const _IntervalSheet({required this.current});

  final int current;

  @override
  State<_IntervalSheet> createState() => _IntervalSheetState();
}

class _IntervalSheetState extends State<_IntervalSheet> {
  static const _options = [7, 14, 21, 30, 45, 60];

  late int _selected = widget.current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Food-log review',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'How often the dietician should review each patient’s food log. '
            'A patient becomes due once this many days have passed since the '
            'dietician last wrote to them.',
            style: TextStyle(fontSize: 13.5, height: 1.45, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final days in _options)
                ChoiceChip(
                  label: Text('$days days'),
                  selected: _selected == days,
                  onSelected: (_) => setState(() => _selected = days),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: AppSpacing.minTapTarget + 6,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(context, _selected),
              child: const Text(
                'Save',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _Dietician {
  const _Dietician({required this.id, required this.name, required this.phone});

  final String id;
  final String name;
  final String phone;

  factory _Dietician.fromJson(Map<String, dynamic> j) => _Dietician(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    phone: j['phone']?.toString() ?? '',
  );
}

/// Creates a dietician account. Validated against the same rules the login and
/// register forms use, so an account made here behaves like any other.
class _AddDieticianSheet extends ConsumerStatefulWidget {
  const _AddDieticianSheet();

  @override
  ConsumerState<_AddDieticianSheet> createState() => _AddDieticianSheetState();
}

class _AddDieticianSheetState extends ConsumerState<_AddDieticianSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  /// Hidden until the first submit attempt, exactly as the login and register
  /// forms behave — errors that appear while someone is still typing the first
  /// character read as the form scolding them.
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  String? _serverError;
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _serverError = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _autovalidateMode = AutovalidateMode.onUserInteraction);
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(clinicianRepositoryProvider).addDietician(
        name: _name.text.trim(),
        phone: AuthValidators.toE164(_phone.text),
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _serverError = e.message;
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
      child: Form(
        key: _formKey,
        autovalidateMode: _autovalidateMode,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('New dietician', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'They can sign in with this number and password.',
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: AuthValidators.maxNameLength,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
                counterText: '',
              ),
              validator: (v) {
                final name = (v ?? '').trim();
                if (name.isEmpty) return 'Enter their name.';
                if (name.length < AuthValidators.minNameLength) {
                  return 'Name must be at least ${AuthValidators.minNameLength} characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              // Same pair as the login field: maxLength caps it and digitsOnly
              // strips anything pasted. A second length limiter on top made the
              // cursor jump when editing a full field.
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                hintText: '9830012345',
                prefixIcon: Icon(Icons.phone_outlined),
                prefixText: '${AuthValidators.countryCode} ',
                counterText: '',
              ),
              validator: (v) {
                final digits = AuthValidators.digitsOnly(v ?? '');
                if (digits.isEmpty) return 'Enter their mobile number.';
                if (digits.length != 10) return 'A mobile number is exactly 10 digits.';
                if (!AuthValidators.isValidPhone(digits)) {
                  return 'Indian mobile numbers start with 6, 7, 8 or 9.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              maxLength: AuthValidators.maxPasswordLength,
              onFieldSubmitted: (_) => _saving ? null : _save(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                counterText: '',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
              validator: (v) {
                final password = v ?? '';
                if (password.isEmpty) return 'Set a password for them.';
                if (password.length < AuthValidators.minPasswordLength) {
                  return 'At least ${AuthValidators.minPasswordLength} characters.';
                }
                return null;
              },
            ),
            if (_serverError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_serverError!, style: const TextStyle(fontSize: 13.5, color: AppColors.danger)),
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: AppSpacing.minTapTarget + 6,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text(
                        'Add dietician',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

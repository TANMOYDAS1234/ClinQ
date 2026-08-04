import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/data/upload_repository.dart';
import '../../../shared/widgets/authed_image.dart';
import '../data/food_log_repository.dart';
import '../domain/food_log.dart';
import 'food_log_providers.dart';

const _mealTypes = <(String, String)>[
  ('breakfast', 'Breakfast'),
  ('lunch', 'Lunch'),
  ('dinner', 'Dinner'),
  ('snack', 'Snack'),
  ('other', 'Other'),
];

String _mealLabel(String type) => _mealTypes.firstWhere((m) => m.$1 == type, orElse: () => ('other', 'Meal')).$2;

/// The patient's food log: meals they record (a photo and/or a note) for their
/// dietician to review.
class FoodLogScreen extends ConsumerWidget {
  const FoodLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(foodLogProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Food log')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _logMeal(context, ref),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Log a meal'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(foodLogProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            const Center(child: Text('Could not load your food log')),
            const SizedBox(height: AppSpacing.sm),
            Center(child: OutlinedButton(onPressed: () => ref.invalidate(foodLogProvider), child: const Text('Retry'))),
          ]),
          data: (entries) {
            if (entries.isEmpty) {
              return ListView(children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                Icon(Icons.restaurant_outlined, size: 54, color: scheme.outlineVariant),
                const SizedBox(height: AppSpacing.md),
                const Center(child: Text('No meals logged yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                const SizedBox(height: 6),
                Center(child: Text('Tap "Log a meal" to add what you ate.', style: TextStyle(color: scheme.onSurfaceVariant))),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 96),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) => _FoodCard(entry: entries[i]),
            );
          },
        ),
      ),
    );
  }

  Future<void> _logMeal(BuildContext context, WidgetRef ref) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _LogMealSheet(),
    );
    if (saved == true) ref.invalidate(foodLogProvider);
  }
}

class _FoodCard extends StatelessWidget {
  const _FoodCard({required this.entry});

  final FoodLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.photoUrl != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: AuthedImage(path: entry.photoUrl!, width: 64, height: 64, radius: 12),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(20)),
                        child: Text(_mealLabel(entry.mealType), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
                      ),
                      const Spacer(),
                      if (entry.createdAt != null)
                        Text(DateFormat('d MMM, h:mm a').format(entry.createdAt!), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  if (entry.note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(entry.note, style: const TextStyle(fontSize: 14.5, height: 1.35)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogMealSheet extends ConsumerStatefulWidget {
  const _LogMealSheet();

  @override
  ConsumerState<_LogMealSheet> createState() => _LogMealSheetState();
}

class _LogMealSheetState extends ConsumerState<_LogMealSheet> {
  String _mealType = 'breakfast';
  final _note = TextEditingController();
  final _picker = ImagePicker();
  File? _localPhoto;
  String? _photoAssetId;
  bool _uploading = false;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    final x = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (x == null) return;
    setState(() {
      _localPhoto = File(x.path);
      _uploading = true;
      _photoAssetId = null;
    });
    try {
      final asset = await ref.read(uploadRepositoryProvider).uploadImage(path: x.path, filename: x.name);
      if (mounted) setState(() => _photoAssetId = asset.id);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _localPhoto = null);
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (_note.text.trim().isEmpty && _photoAssetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a photo or a note')));
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(foodLogRepositoryProvider).create(
            mealType: _mealType,
            note: _note.text.trim(),
            photo: _photoAssetId,
          );
      navigator.pop(true);
    } on ApiException catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Log a meal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 8,
            children: [
              for (final (value, label) in _mealTypes)
                ChoiceChip(label: Text(label), selected: _mealType == value, onSelected: (_) => setState(() => _mealType = value)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'What did you eat? (e.g. 2 rotis, dal, salad)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_localPhoto != null)
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Image.file(_localPhoto!, width: 72, height: 72, fit: BoxFit.cover),
                      if (_uploading)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black26,
                            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton.icon(
                  onPressed: _uploading ? null : () => _showPhotoSource(context),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Change photo'),
                ),
              ],
            )
          else
            InkWell(
              onTap: () => _showPhotoSource(context),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('Add a photo of your meal', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: (_saving || _uploading) ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: AppColors.primary),
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : const Text('Save meal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          if (scheme.brightness == Brightness.dark) const SizedBox.shrink(),
        ],
      ),
    );
  }

  void _showPhotoSource(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }
}

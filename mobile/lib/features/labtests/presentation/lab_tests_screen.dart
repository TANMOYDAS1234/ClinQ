import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/data/upload_repository.dart';
import '../../../shared/widgets/authed_image.dart';
import '../data/lab_tests_repository.dart';
import '../domain/lab_tests.dart';
import 'lab_tests_providers.dart';

/// The tests the doctor advised and the reports the patient uploads against
/// them. A report is a photo of the printed result.
class LabTestsScreen extends ConsumerStatefulWidget {
  const LabTestsScreen({super.key});

  @override
  ConsumerState<LabTestsScreen> createState() => _LabTestsScreenState();
}

/// Where a report came from. A PDF is the common case — labs email them — and
/// it was the one route the screen did not offer.
enum _Source { document, camera, gallery }

class _LabTestsScreenState extends ConsumerState<LabTestsScreen> {
  final _picker = ImagePicker();
  String? _uploading;

  Future<void> _upload(String testName) async {
    final messenger = ScaffoldMessenger.of(context);
    final source = await _pickSource();
    if (source == null) return;

    // Path and display name, whichever way it was chosen.
    String path;
    String filename;

    if (source == _Source.document) {
      // Most lab reports arrive as a PDF by email or WhatsApp. Photographing a
      // phone screen to upload one was the only route before this, and it lost
      // every number on the page.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
        withData: false,
      );
      final file = result?.files.singleOrNull;
      if (file?.path == null) return;
      path = file!.path!;
      filename = file.name;
    } else {
      final x = await _picker.pickImage(
        source: source == _Source.camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (x == null) return;
      path = x.path;
      filename = x.name;
    }

    setState(() => _uploading = testName);
    try {
      final asset = await ref.read(uploadRepositoryProvider).uploadImage(path: path, filename: filename);
      await ref.read(labTestsRepositoryProvider).upload(testName: testName, photo: asset.id);
      ref.invalidate(labTestsProvider);
      messenger.showSnackBar(SnackBar(content: Text('$testName report uploaded')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<_Source?> _pickSource() {
    return showModalBottomSheet<_Source>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF or document'),
              subtitle: const Text('The report your lab emailed you'),
              onTap: () => Navigator.pop(ctx, _Source.document),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, _Source.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, _Source.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadOther() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Which test?'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. HbA1c, Lipid profile')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Next')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) await _upload(name);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(labTestsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My tests')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadOther,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('Upload report'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(labTestsProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            const Center(child: Text('Could not load your tests')),
            const SizedBox(height: AppSpacing.sm),
            Center(child: OutlinedButton(onPressed: () => ref.invalidate(labTestsProvider), child: const Text('Retry'))),
          ]),
          data: (view) => ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 96),
            children: [
              Text('ADVISED BY YOUR DOCTOR', style: _label(scheme)),
              const SizedBox(height: AppSpacing.sm),
              if (view.advised.isEmpty)
                _note(scheme, 'No tests advised yet. Your doctor will add them when they prescribe.')
              else
                Container(
                  decoration: _cardBox(scheme),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < view.advised.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
                        _AdvisedRow(
                          test: view.advised[i],
                          done: view.hasResultFor(view.advised[i]),
                          uploading: _uploading == view.advised[i],
                          onUpload: () => _upload(view.advised[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.xl),
              Text('UPLOADED REPORTS', style: _label(scheme)),
              const SizedBox(height: AppSpacing.sm),
              if (view.results.isEmpty)
                _note(scheme, 'Reports you upload appear here — your doctor and dietician can see them.')
              else
                for (final r in view.results) ...[
                  _ResultCard(result: r),
                  const SizedBox(height: AppSpacing.sm),
                ],
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _label(ColorScheme scheme) => TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: scheme.onSurfaceVariant);

  BoxDecoration _cardBox(ColorScheme scheme) => BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      );

  Widget _note(ColorScheme scheme, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: _cardBox(scheme),
        child: Text(text, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
      );
}

class _AdvisedRow extends StatelessWidget {
  const _AdvisedRow({required this.test, required this.done, required this.uploading, required this.onUpload});

  final String test;
  final bool done;
  final bool uploading;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle_rounded : Icons.biotech_outlined, size: 20, color: done ? AppColors.success : scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(test, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
          if (uploading)
            const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
          else
            TextButton(onPressed: onUpload, child: Text(done ? 'Re-upload' : 'Upload')),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final LabResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result.photoUrl != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: AuthedImage(path: result.photoUrl!, width: 56, height: 56, radius: 10),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(result.testName, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
                    if (result.createdAt != null)
                      Text(DateFormat('d MMM').format(result.createdAt!), style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
                if (result.note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(result.note, style: const TextStyle(fontSize: 13.5)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

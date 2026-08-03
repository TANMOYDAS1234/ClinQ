import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/data/upload_repository.dart';
import 'chat_attachment_strip.dart';
import 'voice_recorder_bar.dart';

/// What the attach button's bottom sheet offers.
enum _AttachChoice { camera, gallery, document }

/// Bottom composer: a rounded pill with an animated gradient border holding the
/// attach button, the growing text field and the voice-note mic, with a
/// circular send button alongside.
///
/// The mic records rather than dictates. Speaking is faster than typing Bengali
/// on a phone, and the clinic hears tone — breathlessness, distress — that a
/// transcript discards. The words still arrive as text (transcribed
/// server-side), so triage and the assistant read them exactly as before.
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({
    super.key,
    required this.onSend,
    required this.onSendVoiceNote,
    required this.isSending,
    required this.languageCode,
  });

  /// Called with the message text and the ids of any uploaded attachments.
  final void Function(String text, List<String> attachmentIds) onSend;

  /// Called with a finished recording's local path. The screen uploads it,
  /// which is where the transcript comes back from.
  final void Function(String path) onSendVoiceNote;
  final bool isSending;

  /// Drives the speech recogniser's locale.
  final String languageCode;

  @override
  ConsumerState<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<ChatComposer> {
  /// Server caps `attachments` at 5 per message.
  static const int _maxAttachments = 5;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _picker = ImagePicker();
  final List<PendingAttachment> _attachments = [];
  bool _hasText = false;
  bool _focused = false;

  /// True while a voice note is being recorded, which swaps the whole bar for
  /// [VoiceRecorderBar].
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncHasText);
    _focusNode.addListener(_syncFocus);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncHasText);
    _focusNode.removeListener(_syncFocus);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _syncHasText() {
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  void _syncFocus() {
    if (_focusNode.hasFocus != _focused) setState(() => _focused = _focusNode.hasFocus);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _canSend => _hasText || _attachments.isNotEmpty;

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final text = _controller.text.trim();

    // A photo (or several) can be sent with no caption at all — block only when
    // there is genuinely nothing to send.
    if (text.isEmpty && _attachments.isEmpty) return;
    if (_attachments.any((a) => a.isUploading)) {
      _snack(l10n.chatAttachUploading);
      return;
    }

    final ids = _attachments.map((a) => a.assetId).whereType<String>().toList();
    widget.onSend(text, ids);
    _controller.clear();
    setState(_attachments.clear);
  }

  Future<void> _pickAttachment() async {
    final l10n = AppLocalizations.of(context);
    if (_attachments.length >= _maxAttachments) {
      _snack(l10n.chatAttachLimit);
      return;
    }

    final choice = await showModalBottomSheet<_AttachChoice>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.chatAttachCamera, style: const TextStyle(fontSize: 16)),
              minTileHeight: AppSpacing.minTapTarget + 8,
              onTap: () => Navigator.of(sheetContext).pop(_AttachChoice.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.chatAttachGallery, style: const TextStyle(fontSize: 16)),
              minTileHeight: AppSpacing.minTapTarget + 8,
              onTap: () => Navigator.of(sheetContext).pop(_AttachChoice.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Document', style: TextStyle(fontSize: 16)),
              subtitle: const Text('PDF, Word, Excel, text…'),
              minTileHeight: AppSpacing.minTapTarget + 8,
              onTap: () => Navigator.of(sheetContext).pop(_AttachChoice.document),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == _AttachChoice.document) {
      await _pickDocuments(l10n);
      return;
    }

    // Gallery allows selecting several photos at once; the camera takes one.
    // Downscale before upload: a modern phone camera produces 8-12 MB files
    // that would trip the server's 12 MB cap over mobile data.
    final source = choice == _AttachChoice.camera ? ImageSource.camera : ImageSource.gallery;
    final List<XFile> files;
    try {
      if (source == ImageSource.gallery) {
        files = await _picker.pickMultiImage(maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
      } else {
        final one = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 2000,
          maxHeight: 2000,
          imageQuality: 85,
        );
        files = one == null ? const [] : [one];
      }
    } catch (_) {
      _snack(l10n.chatAttachFailed);
      return;
    }
    if (files.isEmpty || !mounted) return;

    // Only take as many as there are free slots left.
    for (final picked in files.take(_maxAttachments - _attachments.length)) {
      if (await picked.length() > UploadRepository.maxBytes) {
        if (mounted) _snack(l10n.chatAttachTooLarge);
        continue;
      }
      if (!mounted) return;
      await _uploadOne(picked, l10n);
    }
  }

  Future<void> _uploadOne(XFile picked, AppLocalizations l10n) async {
    final index = _attachments.length;
    setState(() => _attachments.add(PendingAttachment(localPath: picked.path)));
    try {
      final asset = await ref
          .read(uploadRepositoryProvider)
          .uploadImage(path: picked.path, filename: picked.name);
      if (!mounted) return;
      if (index < _attachments.length && _attachments[index].localPath == picked.path) {
        setState(() => _attachments[index] = _attachments[index].copyWith(assetId: asset.id));
      }
    } on ApiException {
      if (!mounted) return;
      if (index < _attachments.length && _attachments[index].localPath == picked.path) {
        setState(() => _attachments[index] = _attachments[index].copyWith(failed: true));
      }
      _snack(l10n.chatAttachFailed);
    }
  }

  /// Pick one or more documents (PDF / Office / text) and upload each, alongside
  /// any photos already staged.
  Future<void> _pickDocuments(AppLocalizations l10n) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv'],
      );
    } catch (_) {
      if (mounted) _snack(l10n.chatAttachFailed);
      return;
    }
    if (result == null || !mounted) return;
    for (final f in result.files.take(_maxAttachments - _attachments.length)) {
      final path = f.path;
      if (path == null) continue;
      if (f.size > UploadRepository.maxBytes) {
        if (mounted) _snack(l10n.chatAttachTooLarge);
        continue;
      }
      if (!mounted) return;
      await _uploadDocument(path, f.name, l10n);
    }
  }

  Future<void> _uploadDocument(String path, String name, AppLocalizations l10n) async {
    final index = _attachments.length;
    setState(() => _attachments.add(PendingAttachment(localPath: path, documentName: name)));
    try {
      final asset = await ref.read(uploadRepositoryProvider).uploadImage(path: path, filename: name);
      if (!mounted) return;
      if (index < _attachments.length && _attachments[index].localPath == path) {
        setState(() => _attachments[index] = _attachments[index].copyWith(assetId: asset.id));
      }
    } on ApiException {
      if (!mounted) return;
      if (index < _attachments.length && _attachments[index].localPath == path) {
        setState(() => _attachments[index] = _attachments[index].copyWith(failed: true));
      }
      _snack(l10n.chatAttachFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    // Recording takes over the whole bar. Leaving the text field visible
    // alongside would suggest both are live, and a patient talking at a screen
    // that still shows a cursor cannot tell which one is listening.
    if (_recording) {
      return VoiceRecorderBar(
        onCancel: () => setState(() => _recording = false),
        onSend: (path, _) {
          setState(() => _recording = false);
          widget.onSendVoiceNote(path);
        },
      );
    }

    return Container(
      // Transparent bar so the chat wallpaper shows behind the composer,
      // WhatsApp-style, instead of a solid strip hiding it. The input pill keeps
      // its own fill so typing stays readable.
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChatAttachmentStrip(
              attachments: _attachments,
              onRemove: (i) => setState(() => _attachments.removeAt(i)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    // The whole pill focuses the field, not just the glyphs of
                    // the text area inside it — tapping the padding either side
                    // used to read as the keyboard needing two taps to open.
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (!_focusNode.hasFocus) _focusNode.requestFocus();
                      },
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 52),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(26),
                          // A plain static border, exactly like the doctor's
                          // composer. The rotating gradient used to repaint every
                          // frame as the keyboard slid up, which made the open
                          // stutter.
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: l10n.chatAttach,
                              onPressed: widget.isSending ? null : _pickAttachment,
                              constraints: const BoxConstraints(
                                minWidth: AppSpacing.minTapTarget,
                                minHeight: AppSpacing.minTapTarget,
                              ),
                              icon: Icon(Icons.attach_file_rounded, color: scheme.onSurfaceVariant),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                focusNode: _focusNode,
                                minLines: 1,
                                maxLines: 5,
                                textCapitalization: TextCapitalization.sentences,
                                style: const TextStyle(fontSize: 16),
                                decoration: InputDecoration(
                                  hintText: l10n.chatComposerHint,
                                  // The field grows to 5 lines, and without
                                  // this the placeholder wrapped with it â€”
                                  // opening the screen on a two-line hint and
                                  // a pill twice the height it needs.
                                  hintMaxLines: 1,
                                  // Null every border state: the app theme sets
                                  // enabled/focused borders explicitly, which
                                  // otherwise draw a second box inside the pill.
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  focusedErrorBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  filled: false,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                                ),
                                onSubmitted: (_) => _submit(),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Padding(
                              padding: const EdgeInsets.only(right: 6, bottom: 4),
                              // The mic now records a voice note rather than
                              // dictating into the field. Speaking is the
                              // point for patients who find typing Bengali on
                              // a phone slow, and the clinic hears tone â€”
                              // breathlessness, distress â€” that a transcript
                              // alone throws away. The words still arrive as
                              // text, transcribed server-side, so triage and
                              // the assistant read them exactly as before.
                              child: IconButton(
                                tooltip: l10n.chatRecordVoice,
                                onPressed: widget.isSending
                                    ? null
                                    : () => setState(() => _recording = true),
                                icon: Icon(Icons.mic_none_rounded, color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                        ),
                      ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _SendButton(
                    enabled: _canSend && !widget.isSending,
                    isSending: widget.isSending,
                    onSend: _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular brand-primary send button. Dim when there is nothing to send,
/// a spinner while sending.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.isSending, required this.onSend});

  final bool enabled;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppColors.primaryDark : AppColors.primary;

    return Semantics(
      button: true,
      enabled: enabled,
      label: l10n.chatSend,
      child: Material(
        color: enabled ? color : color.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onSend : null,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Center(
              child: isSending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

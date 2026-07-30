import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/data/upload_repository.dart';
import 'animated_gradient_border.dart';
import 'chat_attachment_strip.dart';
import 'mic_button.dart';

/// Bottom composer, styled like a modern AI assistant input: a rounded pill
/// with an animated gradient border (Gemini-style) holding the attach button,
/// the growing text field and the dictation mic, with a circular send button
/// alongside.
class ChatComposer extends ConsumerStatefulWidget {
  const ChatComposer({
    super.key,
    required this.onSend,
    required this.isSending,
    required this.languageCode,
  });

  /// Called with the message text and the ids of any uploaded attachments.
  final void Function(String text, List<String> attachmentIds) onSend;
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
  bool _listening = false;

  /// Field contents before the current dictated utterance. Null when not
  /// dictating. See [_onTranscript].
  String? _dictationBase;

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

    if (text.isEmpty) {
      // The server requires non-empty text even with a photo, so a caption is
      // always needed — say so rather than failing silently.
      if (_attachments.isNotEmpty) _snack(l10n.chatAttachNeedsText);
      return;
    }
    if (_attachments.any((a) => a.isUploading)) {
      _snack(l10n.chatAttachUploading);
      return;
    }

    final ids = _attachments.map((a) => a.assetId).whereType<String>().toList();
    widget.onSend(text, ids);
    _controller.clear();
    setState(_attachments.clear);
  }

  /// Renders the live transcript as the patient speaks.
  ///
  /// [_dictationBase] holds everything in the field before the current
  /// utterance began. Each revision is drawn after it, replacing the previous
  /// guess rather than stacking on it — otherwise "how are you" would arrive as
  /// "how how are how are you". When an utterance is committed it becomes the
  /// new base, so the next one appends after it. Typed text is never
  /// overwritten.
  void _onTranscript(String words, bool isFinal) {
    final base = _dictationBase ??= _controller.text.trimRight();
    final text = words.isEmpty ? base : (base.isEmpty ? words : '$base $words');

    // Set text and caret together — assigning `.text` alone resets the
    // selection to the start, which fights the user on every partial.
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

    if (isFinal) _dictationBase = text;
  }

  void _onListeningChanged(bool listening) {
    // Drop the base when dictation ends so the next session re-reads whatever
    // is in the field, including anything typed by hand in between.
    if (!listening) _dictationBase = null;
    setState(() => _listening = listening);
  }

  void _onMicUnavailable(String reason) {
    final l10n = AppLocalizations.of(context);
    _snack(reason == 'denied' ? l10n.voicePermissionTitle : l10n.voiceUnavailable);
  }

  Future<void> _pickAttachment() async {
    final l10n = AppLocalizations.of(context);
    if (_attachments.length >= _maxAttachments) {
      _snack(l10n.chatAttachLimit);
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.chatAttachCamera, style: const TextStyle(fontSize: 16)),
              minTileHeight: AppSpacing.minTapTarget + 8,
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.chatAttachGallery, style: const TextStyle(fontSize: 16)),
              minTileHeight: AppSpacing.minTapTarget + 8,
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        // Downscale before upload: a modern phone camera produces 8-12 MB
        // files that would trip the server's 12 MB cap over mobile data.
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );
    } catch (_) {
      _snack(l10n.chatAttachFailed);
      return;
    }
    if (picked == null || !mounted) return;

    if (await picked.length() > UploadRepository.maxBytes) {
      if (mounted) _snack(l10n.chatAttachTooLarge);
      return;
    }
    if (!mounted) return;

    final index = _attachments.length;
    setState(() => _attachments.add(PendingAttachment(localPath: picked!.path)));

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
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
                    child: AnimatedGradientBorder(
                      active: _focused || _listening,
                      listening: _listening,
                      radius: 26,
                      // The whole pill focuses the field, not just the glyphs
                      // of the text area inside it. Tapping the padding either
                      // side used to do nothing, which read as the keyboard
                      // needing two taps to open.
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
                              child: MicButton(
                                languageCode: widget.languageCode,
                                onTranscript: _onTranscript,
                                onListeningChanged: _onListeningChanged,
                                onUnavailable: _onMicUnavailable,
                              ),
                            ),
                          ],
                        ),
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
            // Only while dictating. Speech UIs fail when the user cannot tell
            // whether the mic is still listening, so the state is named and the
            // way out of it is stated outright.
            if (_listening)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  l10n.chatTapToStop,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.danger,
                  ),
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

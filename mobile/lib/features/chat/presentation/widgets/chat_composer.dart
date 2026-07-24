
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/data/upload_repository.dart';
import 'chat_attachment_strip.dart';
import 'hold_to_talk_overlay.dart';
import 'voice_input_sheet.dart';
import 'voice_recognizer.dart';

/// Bottom composer: a rounded pill holding the attach action and the text
/// field, with a circular action button alongside that cross-fades between
/// microphone and send depending on whether anything has been typed.
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
  final _picker = ImagePicker();
  final List<PendingAttachment> _attachments = [];
  bool _hasText = false;

  /// Non-null while a press-and-hold voice session is in progress.
  VoiceHoldController? _holdController;
  VoiceRecognizer? _recognizer;
  OverlayEntry? _holdOverlay;

  /// Anchors the floating lock and recording bar to the real mic button.
  final GlobalKey _micKey = GlobalKey();

  /// Where the finger first landed, so cancel/lock are measured as travel from
  /// the press point rather than absolute screen position.
  Offset _holdOrigin = Offset.zero;

  /// Slide thresholds, in logical pixels of travel from the press point.
  static const double _cancelThreshold = 90; // leftward → discard
  static const double _lockThreshold = 90; // upward → hands-free

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncHasText);
  }

  @override
  void dispose() {
    // Leaving the chat mid-recording must not leak the overlay or the mic.
    _holdOverlay?.remove();
    _recognizer?.removeListener(_onRecognizerStatus);
    _recognizer?.dispose();
    _holdController?.dispose();
    _controller.removeListener(_syncHasText);
    _controller.dispose();
    super.dispose();
  }

  void _syncHasText() {
    final has = _controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final text = _controller.text.trim();

    if (text.isEmpty) {
      // The server requires non-empty text on every message, so a photo can
      // never be sent alone — say so rather than failing silently.
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
        // Downscale before upload: a modern phone camera produces 8–12 MB
        // files that would trip the server's 12 MB cap over a clinic's mobile
        // data, and the assistant gains nothing from full resolution.
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

    // Show the thumbnail immediately, then fill in the id when the upload
    // returns — the patient sees their photo without waiting on the network.
    final index = _attachments.length;
    setState(() => _attachments.add(PendingAttachment(localPath: picked!.path)));

    try {
      final asset = await ref
          .read(uploadRepositoryProvider)
          .uploadImage(path: picked.path, filename: picked.name);
      if (!mounted) return;
      // The strip may have been edited while the upload was in flight.
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

  /// Press-and-hold: the sheet opens on long-press and ends when the finger
  /// lifts. Sliding left far enough cancels, as in WhatsApp — but this
  /// transcribes rather than recording audio, because the triage rules read
  /// text and audio the server never sees as text would bypass them.
  void _startHoldToTalk(Offset globalPosition) {
    if (widget.isSending || _holdController != null) return;

    // Anchor the overlay to the mic button's real position on screen.
    final box = _micKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final micRect = box.localToGlobal(Offset.zero) & box.size;

    _holdOrigin = globalPosition;
    unawaited(HapticFeedback.mediumImpact());

    final hold = VoiceHoldController();
    final recognizer = VoiceRecognizer(widget.languageCode)..addListener(_onRecognizerStatus);
    setState(() {
      _holdController = hold;
      _recognizer = recognizer;
    });
    unawaited(recognizer.start());

    _holdOverlay = OverlayEntry(
      builder: (_) => HoldToTalkView(
        recognizer: recognizer,
        hold: hold,
        micRect: micRect,
        onLockedSend: () => unawaited(_finishHold()),
        onLockedCancel: () => unawaited(_cancelHold()),
      ),
    );
    Overlay.of(context).insert(_holdOverlay!);
  }

  /// If permission is refused or no recogniser exists, abandon the session and
  /// tell the patient, rather than leaving an empty recording bar up.
  void _onRecognizerStatus() {
    final rec = _recognizer;
    if (rec == null) return;
    if (rec.status == VoiceStatus.denied || rec.status == VoiceStatus.unavailable) {
      final l10n = AppLocalizations.of(context);
      _snack(rec.status == VoiceStatus.denied ? l10n.voicePermissionTitle : l10n.voiceUnavailable);
      unawaited(_cancelHold());
    }
  }

  void _updateHold(Offset globalPosition) {
    final hold = _holdController;
    if (hold == null || hold.locked || hold.cancelled) return;
    final dx = globalPosition.dx - _holdOrigin.dx;
    final dy = globalPosition.dy - _holdOrigin.dy;

    final lockProgress = (-dy / _lockThreshold).clamp(0.0, 1.0);
    // Up wins over left: once the finger is meaningfully rising toward the
    // lock, a stray sideways wobble must not arm cancel — a cancel is
    // unrecoverable, so it should be the harder of the two to trigger.
    final cancelArmed = dx < -_cancelThreshold && lockProgress < 0.4;

    final wasLocked = hold.locked;
    hold.update(lockProgress: lockProgress, cancelArmed: cancelArmed);
    if (hold.locked && !wasLocked) HapticFeedback.mediumImpact();
  }

  void _endHold() {
    final hold = _holdController;
    if (hold == null || hold.locked) return; // locked: the overlay's buttons end it
    if (hold.cancelArmed) {
      HapticFeedback.heavyImpact();
      unawaited(_cancelHold());
    } else {
      HapticFeedback.lightImpact();
      unawaited(_finishHold());
    }
  }

  /// Release / locked-Send: keep whatever was transcribed.
  Future<void> _finishHold() async {
    final transcript = await _recognizer?.stop();
    _teardownHold();
    if (transcript != null && mounted) _insertTranscript(transcript);
  }

  /// Slide-to-cancel / locked-Cancel: discard.
  Future<void> _cancelHold() async {
    await _recognizer?.abort();
    _teardownHold();
  }

  void _teardownHold() {
    _holdOverlay?.remove();
    _holdOverlay = null;
    _recognizer?.removeListener(_onRecognizerStatus);
    _recognizer?.dispose();
    _recognizer = null;
    _holdController?.dispose();
    _holdController = null;
    if (mounted) setState(() {});
  }

  Future<void> _openVoiceSheet() async {
    final transcript = await VoiceInputSheet.show(context, languageCode: widget.languageCode);
    if (transcript == null || !mounted) return;
    _insertTranscript(transcript);
  }

  void _insertTranscript(String transcript) {

    // Deliberately placed in the field rather than sent. Speech recognition
    // mishears numbers, and here a number is a blood sugar reading — the
    // patient must see it before it reaches triage.
    final existing = _controller.text.trim();
    _controller.text = existing.isEmpty ? transcript : '$existing $transcript';
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      // Opaque, with a hairline rule above it. Without this the dotted
      // background and the last suggestion card bleed through behind the
      // composer instead of scrolling cleanly under it.
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
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(28),
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
                            icon: Icon(
                              Icons.attach_file_rounded,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              style: const TextStyle(fontSize: 16),
                              decoration: InputDecoration(
                                hintText: l10n.chatComposerHint,
                                // Every border state must be nulled
                                // individually. The app theme sets
                                // `enabledBorder`/`focusedBorder` explicitly,
                                // and those take precedence over `border` —
                                // nulling only `border` drew a second outlined
                                // box inside this pill, teal and 2px wide once
                                // focused.
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                // The theme also fills inputs; the pill
                                // already provides the surface.
                                filled: false,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              onSubmitted: (_) => _submit(),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _ActionButton(
                    key: _micKey,
                    isSending: widget.isSending,
                    // An attached photo needs a caption, so the send button
                    // appears once either is present.
                    showSend: _hasText || _attachments.isNotEmpty,
                    onSend: _submit,
                    onVoice: _openVoiceSheet,
                    onHoldStart: _startHoldToTalk,
                    onHoldUpdate: _updateHold,
                    onHoldEnd: _endHold,
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

/// Circular teal button: microphone when the field is empty, send once
/// something is typed. The two cross-fade *and* scale, because this is the
/// most-tapped control on the screen and a hard swap reads as a glitch.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.isSending,
    required this.showSend,
    required this.onSend,
    required this.onVoice,
    required this.onHoldStart,
    required this.onHoldUpdate,
    required this.onHoldEnd,
  });

  final bool isSending;
  final bool showSend;
  final VoidCallback onSend;
  final VoidCallback onVoice;
  final ValueChanged<Offset> onHoldStart;
  final ValueChanged<Offset> onHoldUpdate;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final holdEnabled = !isSending && !showSend;

    return Semantics(
      button: true,
      label: showSend ? l10n.chatSend : l10n.voiceTapToSpeak,
      // A single detector owns tap AND the whole long-press. The long-press
      // callbacks are bound unconditionally: Flutter fixes a gesture's
      // callbacks at press time, so gating the move handler on an "is holding"
      // flag (false at that instant) left it permanently null — which is why
      // slide-to-cancel never fired. `onLongPressMoveUpdate` delivers position
      // continuously for the whole press, so cancel and lock are tracked from
      // it, not from a separate drag recogniser that would fight it in the
      // gesture arena.
      child: GestureDetector(
        onTap: isSending ? null : (showSend ? onSend : onVoice),
        onLongPressStart: holdEnabled ? (d) => onHoldStart(d.globalPosition) : null,
        onLongPressMoveUpdate: holdEnabled ? (d) => onHoldUpdate(d.globalPosition) : null,
        onLongPressEnd: holdEnabled ? (_) => onHoldEnd() : null,
        onLongPressCancel: holdEnabled ? onHoldEnd : null,
        child: Material(
          color: AppColors.primary,
          shape: const CircleBorder(),
          child: SizedBox(
            width: 56,
            height: 56,
            child: Center(
              child: isSending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.8, end: 1.0).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Icon(
                        showSend ? Icons.send_rounded : Icons.mic_rounded,
                        key: ValueKey(showSend),
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

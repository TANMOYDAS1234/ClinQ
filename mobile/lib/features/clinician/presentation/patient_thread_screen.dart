import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/data/upload_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../chat/domain/chat_message.dart';

import '../../chat/presentation/widgets/chat_message_bubble.dart';
import '../../../shared/widgets/chat_background.dart';
import '../../chat/presentation/widgets/voice_recorder_bar.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../data/clinician_repository.dart';

/// What the doctor's attach button offers.
enum _DoctorAttach { camera, gallery, document }

/// The clinician's view of a patient's conversation.
///
/// Renders with [ChatMessageBubble] — the same widget the patient's Care Team
/// screen uses — so the doctor is looking at exactly what the patient is
/// looking at, down to the emergency cards and citations. A separate clinician
/// chat UI was what let the two drift into showing different conversations.
class PatientThreadScreen extends ConsumerStatefulWidget {
  const PatientThreadScreen({super.key, required this.patientId, this.patientName});

  final String patientId;
  final String? patientName;

  @override
  ConsumerState<PatientThreadScreen> createState() => _PatientThreadScreenState();
}

class _PatientThreadScreenState extends ConsumerState<PatientThreadScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  List<ChatMessage> _messages = const [];
  String? _patientName;

  /// Carried so the doctor can call from inside the conversation, which is
  /// where the decision to stop typing and phone someone is actually made.
  String? _patientPhone;

  /// The photo the patient set. Part of recognising who you are talking to,
  /// so it is read from the thread rather than left as an initial.
  String? _patientAvatarUrl;
  bool _loading = true;
  bool _sending = false;

  /// True while the doctor is recording a reply, which swaps the composer for
  /// [VoiceRecorderBar] — same treatment as the patient's side.
  bool _recording = false;
  Object? _error;

  /// Whether the newest message has scrolled out of view. Same affordance the
  /// patient has: on a long thread, reading back and then returning to the
  /// bottom otherwise means a lot of dragging.
  bool _showJumpToLatest = false;

  /// Keeps the conversation live while the clinician has it open, so a message
  /// the patient sends appears without reopening the screen. Same interval as
  /// the patient's side, for the same reason: no socket or push channel exists.
  static const _pollInterval = Duration(seconds: 3);
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _patientName = widget.patientName;
    _load();
    _poll = Timer.periodic(_pollInterval, (_) => _pollForUpdates());
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final away = pos.maxScrollExtent - pos.pixels > 240;
    if (away != _showJumpToLatest) setState(() => _showJumpToLatest = away);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Silent refresh: no spinner, no error, and state is replaced only when a
  /// message actually arrived — otherwise every tick would rebuild the
  /// transcript under the doctor's scrolling.
  Future<void> _pollForUpdates() async {
    if (!mounted || _sending || _loading) return;
    try {
      final result = await ref.read(clinicianRepositoryProvider).patientThread(widget.patientId);
      if (!mounted || result.messages.length <= _messages.length) return;
      setState(() => _messages = result.messages);
      _scrollToBottom();
    } on ApiException {
      // Ignored — the next tick retries.
    }
  }

  Future<void> _load() async {
    try {
      final result = await ref.read(clinicianRepositoryProvider).patientThread(widget.patientId);
      if (!mounted) return;
      setState(() {
        _messages = result.messages;
        _patientName = result.patientName ?? _patientName;
        _patientPhone = result.patientPhone ?? _patientPhone;
        _patientAvatarUrl = result.patientAvatarUrl ?? _patientAvatarUrl;
        _loading = false;
        _error = null;
      });
      _scrollToBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  /// Pins the thread to the newest message.
  ///
  /// Jumped twice, a beat apart. On the first frame after a load the list has
  /// only built the rows it can see, so `maxScrollExtent` is an underestimate —
  /// jumping to it lands partway up and leaves the doctor scrolling down to
  /// find the message they opened the thread to read. The second jump runs once
  /// the remaining rows have been laid out and the extent is real.
  void _scrollToBottom() {
    void jump() {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) jump();
      });
    });
  }

  Future<void> _call() async {
    final phone = _patientPhone;
    if (phone == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!await launchUrl(Uri(scheme: 'tel', path: phone))) {
      messenger.showSnackBar(SnackBar(content: Text('Could not start a call to $phone')));
    }
  }

  /// Records a reply instead of typing it.
  ///
  /// A doctor between patients can say in fifteen seconds what would take a
  /// minute to thumb-type, and the patient hears their actual voice — which
  /// carries reassurance that text does not. Uploaded and transcribed the same
  /// way as the patient's, so the thread stays readable either way.
  Future<void> _sendVoiceNote(String path) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      final asset = await ref.read(uploadRepositoryProvider).uploadImage(
        path: path,
        filename: path.split(RegExp(r'[/\\]')).last,
        kind: UploadKind.voiceNote,
        patientId: widget.patientId,
      );
      await ref.read(clinicianRepositoryProvider).messagePatient(
        patientId: widget.patientId,
        // WhatsApp-style: the message text is just a marker, not the transcript —
        // so the thread, the inbox preview and the patient's push notification
        // all read "Voice message" rather than the spoken words.
        content: 'Voice message',
        attachments: [asset.id],
      );
      await _load();
    } on ApiException {
      messenger.showSnackBar(const SnackBar(content: Text('Could not send. Please try again.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Sends a photo to the patient — the doctor's version of the patient's
  /// attach button. Uploads it, then sends it as a message with the text in the
  /// box as its caption (or a default, so the message is never empty).
  Future<void> _sendImage() async {
    final choice = await _pickAttachSource();
    if (choice == null || !mounted) return;
    if (choice == _DoctorAttach.document) {
      await _sendDocuments();
      return;
    }
    final picker = ImagePicker();
    final source = choice == _DoctorAttach.camera ? ImageSource.camera : ImageSource.gallery;
    // Gallery allows picking several at once; the camera takes one.
    final List<XFile> files;
    if (source == ImageSource.gallery) {
      files = await picker.pickMultiImage(maxWidth: 2000, imageQuality: 85);
    } else {
      final f = await picker.pickImage(source: ImageSource.camera, maxWidth: 2000, imageQuality: 85);
      files = f == null ? const [] : [f];
    }
    if (files.isEmpty || !mounted) return;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ids = <String>[];
      for (final file in files.take(5)) {
        final asset = await ref.read(uploadRepositoryProvider).uploadImage(
          path: file.path,
          filename: file.name,
          kind: UploadKind.other,
          patientId: widget.patientId,
        );
        ids.add(asset.id);
      }
      // Caption is optional — photos can go on their own.
      await ref.read(clinicianRepositoryProvider).messagePatient(
        patientId: widget.patientId,
        content: _controller.text.trim(),
        attachments: ids,
      );
      _controller.clear();
      await _load();
    } on ApiException {
      messenger.showSnackBar(const SnackBar(content: Text('Could not send the photo. Please try again.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<_DoctorAttach?> _pickAttachSource() {
    return showModalBottomSheet<_DoctorAttach>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, _DoctorAttach.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, _DoctorAttach.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Document'),
              subtitle: const Text('PDF, Word, Excel, text…'),
              onTap: () => Navigator.pop(ctx, _DoctorAttach.document),
            ),
          ],
        ),
      ),
    );
  }

  /// Sends one or more documents (PDF / Office / text) to the patient, owned by
  /// the patient so they can open them.
  Future<void> _sendDocuments() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv'],
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not pick the file.')));
      }
      return;
    }
    final picked = result?.files.where((f) => f.path != null).take(5).toList() ?? const [];
    if (picked.isEmpty || !mounted) return;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ids = <String>[];
      for (final f in picked) {
        final asset = await ref.read(uploadRepositoryProvider).uploadImage(
          path: f.path!,
          filename: f.name,
          kind: UploadKind.other,
          patientId: widget.patientId,
        );
        ids.add(asset.id);
      }
      await ref.read(clinicianRepositoryProvider).messagePatient(
        patientId: widget.patientId,
        content: _controller.text.trim(),
        attachments: ids,
      );
      _controller.clear();
      await _load();
    } on ApiException {
      messenger.showSnackBar(const SnackBar(content: Text('Could not send the file. Please try again.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(clinicianRepositoryProvider)
          .messagePatient(patientId: widget.patientId, content: text);
      _controller.clear();
      // Re-read rather than appending locally, so the doctor sees the message
      // exactly as it was stored — and as the patient will receive it.
      await _load();
    } on ApiException {
      messenger.showSnackBar(const SnackBar(content: Text('Could not send. Please try again.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(
              name: _patientName ?? '?',
              avatarUrl: _patientAvatarUrl,
              accent: AppColors.primary,
              size: 36,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _patientName ?? 'Conversation',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        actions: [
          // The patient's full record — clinical summary, prescribe, dietician,
          // test reports — opens from here; the chat is where the doctor is.
          IconButton(
            tooltip: 'Patient record & prescribe',
            icon: const Icon(Icons.assignment_ind_outlined, color: AppColors.primary),
            onPressed: () => context.push('/clinician/patients/${widget.patientId}', extra: _patientName),
          ),
          // Calling belongs here rather than on the inbox row: the decision to
          // stop typing and phone someone is made while reading the exchange,
          // not while scanning the list.
          IconButton(
            tooltip: 'Call ${_patientName ?? 'patient'}',
            icon: const Icon(Icons.call_rounded, color: AppColors.primary),
            onPressed: _patientPhone == null ? null : _call,
          ),
        ],
      ),
      // Matches the patient's screen: a fixed background that never repaints as
      // the keyboard animates.
      resizeToAvoidBottomInset: false,
      body: ChatBackground(
        child: _KeyboardInset(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    _body(),
                    if (_showJumpToLatest)
                      Positioned(
                        right: AppSpacing.md,
                        bottom: AppSpacing.md,
                        child: Material(
                          color: AppColors.primary,
                          shape: const CircleBorder(),
                          elevation: 3,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _scrollToBottom,
                            child: const SizedBox(
                              width: 46,
                              height: 46,
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Recording replaces the composer, as on the patient's side.
              if (_recording)
                VoiceRecorderBar(
                  onCancel: () => setState(() => _recording = false),
                  onSend: (path, _) {
                    setState(() => _recording = false);
                    _sendVoiceNote(path);
                  },
                )
              else
                _Composer(
                  controller: _controller,
                  focusNode: _focusNode,
                  sending: _sending,
                  onSend: _send,
                  onRecord: () => setState(() => _recording = true),
                  onAttach: _sendImage,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load the conversation'),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 48, color: Theme.of(context).colorScheme.outlineVariant),
              const SizedBox(height: AppSpacing.md),
              Text(
                'No messages yet.\nAnything you send starts the conversation.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _messages.length,
      itemBuilder: (context, i) => RepaintBoundary(
        child: ChatMessageBubble(message: _messages[i], isClinicianView: true),
      ),
    );
  }
}

/// See the identical widget on the patient's chat screen: reading the keyboard
/// inset here confines the per-frame rebuild to this one widget instead of the
/// whole transcript.
class _KeyboardInset extends StatelessWidget {
  const _KeyboardInset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    required this.onRecord,
    required this.onAttach,
  });

  /// Starts a voice reply. A doctor between patients can say in fifteen seconds
  /// what would take a minute to thumb-type, and the patient hears an actual
  /// voice — which carries reassurance that text does not.
  final VoidCallback onRecord;

  /// Attach a photo to send the patient — same affordance the patient has, for
  /// sending back a marked-up report, a diagram, or a photographed note.
  final VoidCallback onAttach;

  final TextEditingController controller;

  /// Held by the screen rather than the TextField's own internal one, so a
  /// rebuild from the three-second poll cannot drop focus while the doctor is
  /// mid-sentence.
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      // Transparent bar so the chat wallpaper shows behind the composer,
      // WhatsApp-style, instead of a solid strip hiding it. The input pill keeps
      // its own fill so typing stays readable.
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                // Whole pill is the tap target, so the keyboard opens on the
                // first tap wherever it lands.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (!focusNode.hasFocus) focusNode.requestFocus();
                  },
                  child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Attach on the LEFT, matching the patient's composer.
                        IconButton(
                          tooltip: 'Attach a photo',
                          onPressed: sending ? null : onAttach,
                          icon: Icon(Icons.attach_file_rounded, color: scheme.onSurfaceVariant),
                        ),
                        Expanded(
                          child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'Reply to this patient…',
                        hintMaxLines: 1,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 15),
                      ),
                      onSubmitted: (_) => onSend(),
                    ),
                        ),
                        // Speak instead of typing, same as the patient has.
                        IconButton(
                          tooltip: 'Record a voice reply',
                          onPressed: sending ? null : onRecord,
                          icon: Icon(Icons.mic_none_rounded, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Material(
                color: AppColors.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: sending ? null : onSend,
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: Center(
                      child: sending
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
            ],
          ),
        ),
      ),
    );
  }
}

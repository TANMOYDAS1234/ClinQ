import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/chat_repository.dart';
import '../domain/chat_message.dart';
import '../domain/citation.dart';

/// Signals a mid-stream `error` event, caught to end the send cleanly.
class _StreamFailure implements Exception {
  const _StreamFailure();
}

class ChatState {
  const ChatState({
    this.sessionId,
    this.messages = const [],
    this.isSending = false,
    this.isLoadingHistory = false,
    this.error,
  });

  final String? sessionId;
  final List<ChatMessage> messages;
  final bool isSending;
  final bool isLoadingHistory;
  final ApiException? error;

  ChatState copyWith({
    String? sessionId,
    List<ChatMessage>? messages,
    bool? isSending,
    bool? isLoadingHistory,
    ApiException? error,
    bool clearError = false,
  }) {
    return ChatState(
      sessionId: sessionId ?? this.sessionId,
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Drives the AI chat screen: sending a message, showing a typing
/// indicator while awaiting the reply, switching between sessions, and
/// starting a fresh one.
class ChatController extends StateNotifier<ChatState> {
  ChatController(this._repository) : super(const ChatState());

  final ChatRepository _repository;

  static const _streamId = '__streaming__';

  Future<void> send({
    required String text,
    required String language,
    List<String>? attachments,
  }) async {
    // The server requires non-empty text even when files are attached, so a
    // photo can never be sent on its own.
    if (text.trim().isEmpty || state.isSending) return;
    final trimmed = text.trim();

    // Echo the patient's message instantly, before the stream even opens, so
    // tapping send feels immediate. Meta replaces it with the server's copy
    // (real id, attachment URLs) ~1.5s later.
    const tempUserId = '__temp_user__';
    final optimisticUser = ChatMessage(
      id: tempUserId,
      seq: -1,
      role: 'user',
      content: trimmed,
      language: language,
      urgency: 'routine',
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      isSending: true,
      clearError: true,
      messages: [...state.messages, optimisticUser],
    );

    var sawMeta = false;
    var streaming = '';
    try {
      await for (final (event, data) in _repository.streamMessage(
        sessionId: state.sessionId,
        text: trimmed,
        language: language,
        attachments: attachments,
      )) {
        switch (event) {
          case 'meta':
            sawMeta = true;
            final userMessage = ChatMessage.fromJson(_asMap(data['userMessage']));
            final placeholder = ChatMessage(
              id: _streamId,
              seq: userMessage.seq + 1,
              role: 'assistant',
              content: '',
              language: language,
              urgency: (data['triage']?['urgency'] ?? 'routine').toString(),
              createdAt: DateTime.now(),
              citations: _parseCitations(data['citations']),
            );
            // Swap the optimistic echo for the server's version, then add the
            // streaming assistant placeholder.
            final withoutTemp = state.messages.where((m) => m.id != tempUserId).toList();
            state = state.copyWith(
              sessionId: data['sessionId']?.toString() ?? state.sessionId,
              messages: [...withoutTemp, userMessage, placeholder],
            );
          case 'token':
            streaming += data['value']?.toString() ?? '';
            _updateStreaming(streaming);
          case 'replace':
            streaming = data['value']?.toString() ?? '';
            _updateStreaming(streaming);
          case 'done':
            final reply = ChatMessage.fromJson(_asMap(data['reply']));
            // Preserve the citations shown from meta on the final message.
            final current = state.messages.lastWhere(
              (m) => m.id == _streamId,
              orElse: () => reply,
            );
            _replaceStreaming(reply.copyWith(citations: current.citations));
            state = state.copyWith(isSending: false);
          case 'error':
            throw const _StreamFailure();
        }
      }
      // Stream ended without a terminal 'done' or 'error'.
      if (state.isSending) state = state.copyWith(isSending: false);
    } catch (e) {
      // If the stream never started, drop the optimistic echo and fall back to
      // the plain request so a patient is never left with nothing. If it failed
      // mid-stream (meta already shown), surface an error and drop the partial.
      if (!sawMeta) {
        state = state.copyWith(
          messages: state.messages.where((m) => m.id != tempUserId).toList(),
        );
        await _sendNonStreaming(trimmed, language, attachments);
      } else {
        _removeStreaming();
        state = state.copyWith(
          isSending: false,
          error: e is ApiException ? e : const ApiException(code: 'AI_UNAVAILABLE', message: 'stream failed'),
        );
      }
    }
  }

  /// The original, non-streaming path — used as a fallback when the stream
  /// cannot be opened at all.
  Future<void> _sendNonStreaming(String text, String language, List<String>? attachments) async {
    try {
      final result = await _repository.sendMessage(
        sessionId: state.sessionId,
        text: text,
        language: language,
        attachments: attachments,
      );
      state = state.copyWith(
        sessionId: result.sessionId,
        messages: [...state.messages, result.userMessage, result.reply],
        isSending: false,
      );
    } on ApiException catch (e) {
      state = state.copyWith(isSending: false, error: e);
    }
  }

  void _updateStreaming(String content) {
    final msgs = state.messages
        .map((m) => m.id == _streamId ? m.withContent(content) : m)
        .toList();
    state = state.copyWith(messages: msgs);
  }

  void _replaceStreaming(ChatMessage reply) {
    final msgs = state.messages.map((m) => m.id == _streamId ? reply : m).toList();
    state = state.copyWith(messages: msgs);
  }

  void _removeStreaming() {
    if (!state.messages.any((m) => m.id == _streamId)) return;
    state = state.copyWith(messages: state.messages.where((m) => m.id != _streamId).toList());
  }

  static Map<String, dynamic> _asMap(dynamic v) =>
      v is Map<String, dynamic> ? v : <String, dynamic>{};

  static List<Citation>? _parseCitations(dynamic raw) {
    if (raw is! List) return null;
    final list = raw
        .whereType<Map<String, dynamic>>()
        .map(Citation.fromJson)
        .toList();
    return list.isEmpty ? null : list;
  }

  /// Resend the most recent question. Used by the "Try again" action on an
  /// AI-unavailable fallback reply.
  ///
  /// Drops the fallback pair (the question and the scripted reply) first, so
  /// the retry replaces them rather than stacking a second copy. The question
  /// itself is preserved and resent.
  Future<void> retryLast({required String language}) async {
    if (state.isSending) return;
    final messages = state.messages;
    // Walk back to the last user message.
    final lastUserIndex = messages.lastIndexWhere((m) => m.isUser);
    if (lastUserIndex < 0) return;
    final question = messages[lastUserIndex].content;

    state = state.copyWith(messages: messages.sublist(0, lastUserIndex));
    await send(text: question, language: language);
  }

  Future<void> openSession(String sessionId) async {
    state = ChatState(sessionId: sessionId, isLoadingHistory: true);
    try {
      final paged = await _repository.getSessionMessages(sessionId, limit: 100);
      final messages = [...paged.items]..sort((a, b) => a.seq.compareTo(b.seq));
      state = state.copyWith(messages: messages, isLoadingHistory: false);
    } on ApiException catch (e) {
      state = state.copyWith(isLoadingHistory: false, error: e);
    }
  }

  void startNewChat() {
    state = const ChatState();
  }

  Future<bool> flagMessage(String messageId) async {
    try {
      await _repository.flagMessage(messageId);
      return true;
    } on ApiException {
      return false;
    }
  }

  Future<bool> archiveCurrentSession() async {
    final id = state.sessionId;
    if (id == null) return false;
    try {
      await _repository.archiveSession(id);
      return true;
    } on ApiException {
      return false;
    }
  }
}

final StateNotifierProvider<ChatController, ChatState> chatControllerProvider =
    StateNotifierProvider<ChatController, ChatState>((ref) {
      return ChatController(ref.watch(chatRepositoryProvider));
    });

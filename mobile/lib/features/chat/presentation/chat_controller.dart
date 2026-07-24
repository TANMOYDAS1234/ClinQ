import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/chat_repository.dart';
import '../domain/chat_message.dart';

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

  Future<void> send({
    required String text,
    required String language,
    List<String>? attachments,
  }) async {
    // The server requires non-empty text even when files are attached, so a
    // photo can never be sent on its own.
    if (text.trim().isEmpty || state.isSending) return;
    state = state.copyWith(isSending: true, clearError: true);
    try {
      final result = await _repository.sendMessage(
        sessionId: state.sessionId,
        text: text.trim(),
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

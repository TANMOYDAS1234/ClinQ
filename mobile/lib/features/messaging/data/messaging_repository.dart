import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/providers/core_providers.dart';
import '../domain/direct_message.dart';

/// Talks to `/messages` — the human doctor↔patient thread (separate from the
/// AI assistant chat).
class MessagingRepository {
  MessagingRepository(this._client);

  final ApiClient _client;

  // ---- Patient ----------------------------------------------------------

  Future<List<DirectMessage>> myThread() async {
    final json = await _client.getJson('/messages');
    return _list(json);
  }

  Future<DirectMessage> sendAsPatient(String content) async {
    final json = await _client.postJson('/messages', body: {'content': content});
    return DirectMessage.fromJson(json['message'] as Map<String, dynamic>);
  }

  Future<int> unreadCount() async {
    final json = await _client.getJson('/messages/unread');
    return (json['count'] as num?)?.toInt() ?? 0;
  }

  // ---- Clinician --------------------------------------------------------

  Future<List<MessageThread>> threads() async {
    final json = await _client.getJson('/messages/threads');
    final items = json['items'] as List? ?? const [];
    return items.whereType<Map<String, dynamic>>().map(MessageThread.fromJson).toList();
  }

  Future<List<DirectMessage>> patientThread(String patientId) async {
    final json = await _client.getJson('/messages/patient/$patientId');
    return _list(json);
  }

  Future<DirectMessage> sendToPatient(String patientId, String content) async {
    final json = await _client.postJson('/messages/patient/$patientId', body: {'content': content});
    return DirectMessage.fromJson(json['message'] as Map<String, dynamic>);
  }

  List<DirectMessage> _list(Map<String, dynamic> json) {
    final items = json['items'] as List? ?? const [];
    return items.whereType<Map<String, dynamic>>().map(DirectMessage.fromJson).toList();
  }
}

final Provider<MessagingRepository> messagingRepositoryProvider = Provider<MessagingRepository>((ref) {
  return MessagingRepository(ref.watch(apiClientProvider));
});

// ---- Providers ----------------------------------------------------------

/// The signed-in patient's own thread with the clinic.
final myThreadProvider = FutureProvider.autoDispose<List<DirectMessage>>((ref) {
  return ref.watch(messagingRepositoryProvider).myThread();
});

/// The patient's unread clinic-message count (for a badge).
final unreadClinicMessagesProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(messagingRepositoryProvider).unreadCount();
});

/// A specific patient's thread, viewed by a clinician.
final patientThreadProvider =
    FutureProvider.autoDispose.family<List<DirectMessage>, String>((ref, patientId) {
  return ref.watch(messagingRepositoryProvider).patientThread(patientId);
});

/// The clinician's message inbox.
final messageThreadsProvider = FutureProvider.autoDispose<List<MessageThread>>((ref) {
  return ref.watch(messagingRepositoryProvider).threads();
});

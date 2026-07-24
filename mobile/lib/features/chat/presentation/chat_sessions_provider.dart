import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/paged.dart';
import '../data/chat_repository.dart';
import '../domain/chat_session.dart';

final FutureProvider<Paged<ChatSession>> chatSessionsProvider = FutureProvider<Paged<ChatSession>>(
  (ref) => ref.watch(chatRepositoryProvider).getSessions(),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/providers/core_providers.dart';
import '../domain/food_log.dart';

/// Talks to `/patients/me/food-log` — the patient's own meal log.
class FoodLogRepository {
  FoodLogRepository(this._client);

  final ApiClient _client;
  static const _base = '/patients/me/food-log';

  Future<List<FoodLogEntry>> list() async {
    final json = await _client.getJson(_base);
    final items = json['items'] as List? ?? const [];
    return items.whereType<Map<String, dynamic>>().map(FoodLogEntry.fromJson).toList();
  }

  /// Removes a meal the patient logged by mistake. Hard delete: a photo of the
  /// wrong plate is an error, not history, and the dietician should not be
  /// planning around a meal that never happened.
  Future<void> delete(String id) async {
    await _client.delete('$_base/$id');
  }

  Future<void> create({required String mealType, String note = '', String? photo}) async {
    await _client.postJson(_base, body: {
      'mealType': mealType,
      if (note.isNotEmpty) 'note': note,
      if (photo != null) 'photo': photo,
    });
  }
}

final foodLogRepositoryProvider = Provider<FoodLogRepository>((ref) {
  return FoodLogRepository(ref.watch(apiClientProvider));
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/providers/core_providers.dart';
import '../domain/lab_tests.dart';

/// Talks to `/patients/me/lab-tests` — advised tests + the patient's uploaded
/// reports.
class LabTestsRepository {
  LabTestsRepository(this._client);

  final ApiClient _client;
  static const _base = '/patients/me/lab-tests';

  Future<LabTestsView> get() async {
    final json = await _client.getJson(_base);
    return LabTestsView.fromJson(json);
  }

  Future<void> upload({required String testName, String note = '', String? photo}) async {
    await _client.postJson(_base, body: {
      'testName': testName,
      if (note.isNotEmpty) 'note': note,
      if (photo != null) 'photo': photo,
    });
  }
}

final labTestsRepositoryProvider = Provider<LabTestsRepository>((ref) {
  return LabTestsRepository(ref.watch(apiClientProvider));
});

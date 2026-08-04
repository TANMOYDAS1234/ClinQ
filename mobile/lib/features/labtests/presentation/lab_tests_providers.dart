import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/lab_tests_repository.dart';
import '../domain/lab_tests.dart';

/// Advised tests + the patient's uploaded reports.
final labTestsProvider = FutureProvider.autoDispose<LabTestsView>(
  (ref) => ref.watch(labTestsRepositoryProvider).get(),
);

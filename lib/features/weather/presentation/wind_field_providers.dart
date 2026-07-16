import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/wind_field.dart';
import '../data/repositories/mock_wind_field_repository.dart';
import '../data/repositories/open_meteo_wind_field_repository.dart';
import '../data/repositories/wind_field_repository.dart';

final windFieldRepositoryProvider = Provider<WindFieldRepository>(
  (ref) => OpenMeteoWindFieldRepository(),
);

/// 화면 진입/새로고침 시 조회하고, 실패하면 합성 바람장으로 폴백한다.
final windFieldProvider = FutureProvider.autoDispose<WindField>((ref) async {
  final repo = ref.watch(windFieldRepositoryProvider);
  try {
    return await repo.fetchField();
  } catch (_) {
    return MockWindFieldRepository().fetchField();
  }
});

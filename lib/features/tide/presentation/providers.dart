import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../locations/data/models/sea_location.dart';
import '../data/models/tide_data.dart';
import '../data/repositories/mock_tide_repository.dart';
import '../data/repositories/tide_repository.dart';

/// 조석 리포지토리 주입 지점. 실 API 연동 시 여기서 구현체만 교체한다.
final tideRepositoryProvider = Provider<TideRepository>(
  (ref) => MockTideRepository(),
);

typedef TideQuery = ({SeaLocation location, DateTime date});

final tideDayProvider = FutureProvider.family<TideDay, TideQuery>((ref, query) {
  return ref
      .watch(tideRepositoryProvider)
      .fetchTideDay(query.location, query.date);
});

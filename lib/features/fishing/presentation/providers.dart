import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../locations/data/models/sea_location.dart';
import '../data/models/fishing_index.dart';
import '../data/repositories/fishing_repository.dart';
import '../data/repositories/mock_fishing_repository.dart';

/// 낚시지수 리포지토리 주입 지점.
///
/// 공공데이터포털 API(바다낚시지수) 활용신청은 승인되었으나 응답 필드 매핑을
/// 확정하기 전까지는 목 구현을 사용한다. 확정 후 DataGoKrFishingRepository로
/// 교체한다 (실패 시 목 폴백 래퍼 포함 예정).
final fishingRepositoryProvider = Provider<FishingRepository>(
  (ref) => MockFishingRepository(),
);

final fishingForecastProvider =
    FutureProvider.family<FishingForecast, SeaLocation>((ref, location) {
      return ref.watch(fishingRepositoryProvider).fetchForecast(location);
    });

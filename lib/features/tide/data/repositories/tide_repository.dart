import '../../../../core/errors/data_errors.dart';
import '../../../../core/utils/mul_ttae.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/tide_data.dart';

/// 조석 데이터 소스 추상화.
///
/// 제공 범위 계약:
/// - 조석(만조/간조·조위) 예보: 오늘 기준 과거 1년 ~ **미래 1년**
///   ([maxTideForecastRange]). 범위를 벗어나면 [DataRangeException].
/// - 그 너머(미래 2년까지)는 조석 없이 단순 물때만 제공한다
///   (`core/utils/mul_ttae.dart`, UI에서 처리).
///
/// 현재 구현: [MockTideRepository] (합성 데이터)
/// 계획: KhoaTideRepository — KHOA 바다누리 조석예보 API 연동
abstract class TideRepository {
  Future<TideDay> fetchTideDay(SeaLocation location, DateTime date);

  /// [primary] 실패 시 [fallback]으로 폴백하는 래퍼를 만든다 (NFR-03).
  /// 제공 범위 위반([DataRangeException])은 양쪽에 공통이므로 폴백하지 않는다.
  factory TideRepository.withFallback({
    required TideRepository primary,
    required TideRepository fallback,
  }) = _FallbackTideRepository;

  /// [date]가 조석 예보 제공 범위인지 검사하고, 벗어나면 예외를 던진다.
  static void ensureInRange(DateTime date, {DateTime? now}) {
    final today = DateTime.now();
    final base = now ?? DateTime(today.year, today.month, today.day);
    final diff = DateTime(date.year, date.month, date.day).difference(base);
    if (diff > maxTideForecastRange || diff < -maxTideForecastRange) {
      throw const DataRangeException('조석 예보는 오늘 기준 ±1년 범위만 제공됩니다');
    }
  }
}

class _FallbackTideRepository implements TideRepository {
  const _FallbackTideRepository({
    required this.primary,
    required this.fallback,
  });

  final TideRepository primary;
  final TideRepository fallback;

  @override
  Future<TideDay> fetchTideDay(SeaLocation location, DateTime date) async {
    try {
      return await primary.fetchTideDay(location, date);
    } on DataRangeException {
      rethrow;
    } catch (_) {
      return fallback.fetchTideDay(location, date);
    }
  }
}

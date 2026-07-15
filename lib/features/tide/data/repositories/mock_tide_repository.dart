import 'dart:math' as math;

import '../../../../core/utils/mul_ttae.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/tide_data.dart';
import 'tide_repository.dart';

/// 합성 조석 데이터 리포지토리.
///
/// 반일주조(M2, 주기 12.42시간)를 기본으로 하고, 삭망(사리/조금) 주기에 따라
/// 진폭을 변조해 실제와 유사한 형태의 조위 곡선을 만든다.
/// 해역별 평균 조차(서해 큼, 동해 작음)를 반영한다.
class MockTideRepository implements TideRepository {
  static const _m2PeriodHours = 12.4206012;

  @override
  Future<TideDay> fetchTideDay(SeaLocation location, DateTime date) async {
    TideRepository.ensureInRange(date);
    final day = DateTime(date.year, date.month, date.day);

    double heightAt(DateTime t) => _heightCm(location, t);

    final hourly = List<double>.generate(
      25,
      (h) => heightAt(day.add(Duration(hours: h))),
    );

    // 5분 간격으로 훑으며 국소 최대/최소(만조/간조)를 찾는다.
    final extremes = <TideExtreme>[];
    const step = Duration(minutes: 5);
    var prev = heightAt(day.subtract(step));
    var curr = heightAt(day);
    for (
      var t = day;
      t.isBefore(day.add(const Duration(days: 1)));
      t = t.add(step)
    ) {
      final next = heightAt(t.add(step));
      TideExtreme? found;
      if (curr >= prev && curr > next) {
        found = TideExtreme(time: t, heightCm: curr, isHigh: true);
      } else if (curr <= prev && curr < next) {
        found = TideExtreme(time: t, heightCm: curr, isHigh: false);
      }
      if (found != null) {
        // 수치 미세 진동으로 같은 종류의 극값이 연속되면 더 극단적인 쪽만 남긴다.
        final last = extremes.isEmpty ? null : extremes.last;
        if (last != null && last.isHigh == found.isHigh) {
          final keepNew = found.isHigh
              ? found.heightCm > last.heightCm
              : found.heightCm < last.heightCm;
          if (keepNew) {
            extremes[extremes.length - 1] = found;
          }
        } else {
          extremes.add(found);
        }
      }
      prev = curr;
      curr = next;
    }

    return TideDay(
      date: day,
      locationId: location.id,
      extremes: extremes,
      hourlyHeightsCm: hourly,
    );
  }

  double _heightCm(SeaLocation location, DateTime t) {
    final (meanCm, amplitudeCm) = switch (location.region) {
      '서해' => (450.0, 320.0),
      '남해' => (180.0, 120.0),
      '제주' => (150.0, 110.0),
      _ => (40.0, 15.0), // 동해는 조차가 작다
    };

    // 사리(삭망 직후) 부근에서 진폭 최대, 조금 부근에서 최소.
    // 진폭이 하루 중에 계단식으로 점프하지 않도록 연속 월령을 사용한다.
    final lunarAge = lunarAgeDays(t);
    final springNeap =
        0.65 + 0.35 * math.cos(2 * math.pi * (lunarAge - 1.5) / 14.765).abs();

    // 지점별 위상차: 경도 기반 고정 오프셋 (합성 데이터용).
    final phaseOffsetHours = (location.longitude - 126.0) * 0.8;

    final hoursSinceEpoch =
        t.millisecondsSinceEpoch / Duration.millisecondsPerHour;
    final phase =
        2 * math.pi * (hoursSinceEpoch - phaseOffsetHours) / _m2PeriodHours;

    // 약한 일주조 성분을 더해 만조 높이가 번갈아 달라지는 일조부등을 흉내낸다.
    final diurnal = 0.15 * amplitudeCm * math.sin(phase / 2);

    return meanCm + amplitudeCm * springNeap * math.cos(phase) + diurnal;
  }
}

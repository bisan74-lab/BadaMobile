import 'dart:math' as math;

import '../../../../core/utils/mul_ttae.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/fishing_index.dart';
import 'fishing_repository.dart';

/// 합성 바다낚시지수 리포지토리.
///
/// 물때(사리/조금)와 좌표 시드를 반영해 그럴듯한 5단계 지수를 만든다.
/// 사리 부근은 물색·조류 탓에 낮게, 중간 물때는 높게 나오는 경향을 흉내낸다.
/// 홈 화면의 4주(과거 2주~미래 2주) 날짜 이동을 지원하도록 오늘 기준
/// -14일 ~ +13일(28일)을 만든다.
class MockFishingRepository implements FishingRepository {
  static const _pastDays = 14;
  static const _totalDays = 28;

  @override
  Future<FishingForecast> fetchForecast(SeaLocation location) async {
    final seed = (location.latitude * 11 + location.longitude * 3) % 5;
    // 해역별 기준 어종을 전부 생성해 홈 화면에서 여러 어종을 함께 볼 수
    // 있게 한다(어종마다 시드를 조금씩 달리해 값이 겹치지 않게 한다).
    final speciesList = preferredSpeciesForRegion(location.region);
    final today = DateTime.now();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: _pastDays));

    final indices = <FishingIndex>[];
    for (var d = 0; d < _totalDays; d++) {
      final date = start.add(Duration(days: d));
      final mulTtae = mulTtaeFor(
        date,
        system: mulTtaeSystemForRegion(location.region),
      );
      // 중간 물때(3~10물)에서 높고, 사리·조금 극단에서 낮은 점수.
      final base = mulTtae.isSari || mulTtae.isJogeum ? 2.4 : 3.6;
      for (final (speciesIndex, species) in speciesList.indexed) {
        final speciesSeed = seed + speciesIndex * 1.7;
        for (final (slotIndex, slot) in const ['오전', '오후'].indexed) {
          final wobble =
              math.sin(date.day * 1.7 + slotIndex * 2.1 + speciesSeed) * 1.2;
          final score = (base + wobble).round().clamp(1, 5);
          indices.add(
            FishingIndex(
              date: date,
              timeSlot: slot,
              grade: FishingGrade.fromScore(score),
              species: species,
              waveHeightM: double.parse(
                (0.4 + 0.5 * math.sin(date.day + slotIndex + speciesSeed).abs())
                    .toStringAsFixed(1),
              ),
              waterTempC: double.parse(
                (20 + 3 * math.sin(date.day / 5 + speciesSeed)).toStringAsFixed(
                  1,
                ),
              ),
            ),
          );
        }
      }
    }
    return FishingForecast(locationId: location.id, indices: indices);
  }
}

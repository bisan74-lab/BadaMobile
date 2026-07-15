import 'dart:math' as math;

import '../../../../core/utils/mul_ttae.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/fishing_index.dart';
import 'fishing_repository.dart';

/// 합성 바다낚시지수 리포지토리.
///
/// 물때(사리/조금)와 좌표 시드를 반영해 그럴듯한 5단계 지수를 만든다.
/// 사리 부근은 물색·조류 탓에 낮게, 중간 물때는 높게 나오는 경향을 흉내낸다.
class MockFishingRepository implements FishingRepository {
  static const _days = 7;

  @override
  Future<FishingForecast> fetchForecast(SeaLocation location) async {
    final seed = (location.latitude * 11 + location.longitude * 3) % 5;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);

    final indices = <FishingIndex>[];
    for (var d = 0; d < _days; d++) {
      final date = start.add(Duration(days: d));
      final mulTtae = mulTtaeFor(
        date,
        system: mulTtaeSystemForRegion(location.region),
      );
      // 중간 물때(3~10물)에서 높고, 사리·조금 극단에서 낮은 점수.
      final base = mulTtae.isSari || mulTtae.isJogeum ? 2.4 : 3.6;
      for (final (slotIndex, slot) in const ['오전', '오후'].indexed) {
        final wobble = math.sin(date.day * 1.7 + slotIndex * 2.1 + seed) * 1.2;
        final score = (base + wobble).round().clamp(1, 5);
        indices.add(
          FishingIndex(
            date: date,
            timeSlot: slot,
            grade: FishingGrade.fromScore(score),
            species: '감성돔',
            waveHeightM: double.parse(
              (0.4 + 0.5 * math.sin(date.day + slotIndex + seed).abs())
                  .toStringAsFixed(1),
            ),
            waterTempC: double.parse(
              (20 + 3 * math.sin(date.day / 5 + seed)).toStringAsFixed(1),
            ),
          ),
        );
      }
    }
    return FishingForecast(locationId: location.id, indices: indices);
  }
}

import 'package:bada_mobile/core/utils/mul_ttae.dart';
import 'package:bada_mobile/features/fishing/data/models/fishing_index.dart';
import 'package:bada_mobile/features/fishing/data/models/jigging_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

/// 잔잔한 날(바람·파고 감점 없음) 기준 점수.
double calmScore(String species, double tide, int month) =>
    estimateJiggingScore(
      species: species,
      tideStrength: tide,
      windMs: 2,
      gustMs: 4,
      waveM: 0.3,
      month: month,
    );

MulTtae west(int index) =>
    MulTtae(index: index, lunarDay: 1, system: MulTtaeSystem.west7);

void main() {
  group('tideStrengthFraction', () {
    test('조위 변화폭을 0~1로 정규화한다', () {
      // 대조기 수준(800cm 변화폭) → 1.0
      expect(tideStrengthFraction([0, 400, 800, 400, 0]), closeTo(1.0, 0.001));
      // 조금 수준(200cm) → 0.25
      expect(
        tideStrengthFraction([100, 200, 300, 200, 100]),
        closeTo(0.25, 0.001),
      );
      expect(tideStrengthFraction(const []), 0);
    });

    test('상한을 넘겨도 1을 넘지 않는다', () {
      expect(tideStrengthFraction([0, 1200]), 1.0);
    });
  });

  group('springNeapPhase', () {
    test('사리가 1, 조금이 0에 가깝다', () {
      expect(springNeapPhase(west(6)), closeTo(1.0, 0.001)); // 7물 = 사리
      expect(springNeapPhase(west(13)), lessThan(0.05)); // 조금
      expect(springNeapPhase(west(14)), lessThan(0.05)); // 무시
      // 8물때식은 8물이 사리 한가운데.
      expect(
        springNeapPhase(
          const MulTtae(index: 7, lunarDay: 1, system: MulTtaeSystem.south8),
        ),
        closeTo(1.0, 0.001),
      );
      expect(
        springNeapPhase(
          const MulTtae(index: 14, lunarDay: 1, system: MulTtaeSystem.south8),
        ),
        lessThan(0.05),
      );
    });

    test('사리에서 멀어질수록 단조 감소한다', () {
      var prev = springNeapPhase(west(6));
      for (final i in [5, 4, 3, 2, 1, 0]) {
        final v = springNeapPhase(west(i));
        expect(v, lessThan(prev), reason: 'index $i');
        prev = v;
      }
    });
  });

  group('relativeTideStrength', () {
    test('서해 조금은 조차가 커도 "느린 물"이다', () {
      // 제보 사례: 무창포 조금인데 조차가 376cm(절대 기준으론 0.47 = "보통").
      // 절대값을 쓰면 최적을 한참 넘겨 거의 모든 날이 매우나쁨이 됐다.
      final strength = relativeTideStrength(mulTtae: west(13), dayRangeCm: 376);
      expect(strength, lessThan(0.1));
      expect(tideStrengthFraction([0, 376]), greaterThan(0.4)); // 옛 방식
    });

    test('같은 물때면 지점이 달라도 세기가 비슷하다', () {
      // 서해(사리 900cm)와 남해(사리 270cm)의 조금.
      final west900 = relativeTideStrength(mulTtae: west(13), dayRangeCm: 405);
      final south270 = relativeTideStrength(
        mulTtae: const MulTtae(
          index: 14,
          lunarDay: 8,
          system: MulTtaeSystem.south8,
        ),
        dayRangeCm: 122,
      );
      expect((west900 - south270).abs(), lessThan(0.05));
    });

    test('조차가 아주 작은 곳은 사리여도 세기 상한이 낮다', () {
      final east = relativeTideStrength(mulTtae: west(6), dayRangeCm: 40);
      final west900 = relativeTideStrength(mulTtae: west(6), dayRangeCm: 900);
      expect(east, lessThan(west900));
      // 그래도 조금과는 확실히 달라야 한다(전 물때가 한 등급으로 눌리면
      // 물때 차이가 화면에서 사라진다).
      expect(
        east - relativeTideStrength(mulTtae: west(13), dayRangeCm: 18),
        greaterThan(0.3),
      );
    });

    test('물때가 사리로 갈수록 세기가 단조 증가한다', () {
      double at(int index) => relativeTideStrength(
        mulTtae: west(index),
        dayRangeCm: 750 * (0.45 + 0.55 * springNeapPhase(west(index))),
      );
      var prev = at(13); // 조금
      for (final i in [0, 1, 2, 3, 4, 5, 6]) {
        final v = at(i);
        expect(v, greaterThan(prev), reason: 'index $i');
        prev = v;
      }
    });
  });

  group('바람 정보 없음', () {
    test('null로 넘기면 그 항목은 감점하지 않는다', () {
      // 예보 범위 밖 날짜(2주 뒤 등)엔 바람·파고가 아예 없다. 이때는
      // 물때·제철로만 판단해야 한다.
      final noData = estimateJiggingScore(
        species: '쭈꾸미',
        tideStrength: 0.05,
        month: 10,
      );
      final calm = estimateJiggingScore(
        species: '쭈꾸미',
        tideStrength: 0.05,
        windMs: 0,
        gustMs: 0,
        waveM: 0,
        month: 10,
      );
      expect(noData, closeTo(calm, 0.0001));
      expect(noData, greaterThan(0.5));
    });

    test('일부만 있으면 있는 항목만 감점한다', () {
      // 육지 쪽 지점은 파고가 없고 바람만 온다.
      final windOnly = estimateJiggingScore(
        species: '쭈꾸미',
        tideStrength: 0.05,
        windMs: 12,
        month: 10,
      );
      final none = estimateJiggingScore(
        species: '쭈꾸미',
        tideStrength: 0.05,
        month: 10,
      );
      expect(windOnly, lessThan(none));
      // 파고까지 있으면 더 떨어진다.
      expect(
        estimateJiggingScore(
          species: '쭈꾸미',
          tideStrength: 0.05,
          windMs: 12,
          waveM: 2.5,
          month: 10,
        ),
        lessThan(windOnly),
      );
    });
  });

  group('"매우나쁨"은 성수기엔 안 나온다', () {
    test('9~11월엔 조류가 아무리 세도 잔잔하면 "나쁨"에서 멈춘다', () {
      // 제철엔 물이 많이 흘러도 잡힌다 — 조류 하나로 바닥을 치면 안 된다.
      for (final s in estimatedSpeciesCatalog) {
        for (var m = 9; m <= 11; m++) {
          for (final tide in [0.0, 0.25, 0.5, 0.75, 1.0]) {
            expect(
              estimateJiggingGrade(species: s, tideStrength: tide, month: m),
              isNot(FishingGrade.veryBad),
              reason: '$s $m월 조류 $tide: 날씨가 나쁘지도 않은데 매우나쁨',
            );
            expect(
              estimateJiggingGrade(
                species: s,
                tideStrength: tide,
                windMs: 2,
                gustMs: 4,
                waveM: 0.3,
                month: m,
              ),
              isNot(FishingGrade.veryBad),
              reason: '$s $m월 조류 $tide: 잔잔한 날인데 매우나쁨',
            );
          }
        }
      }
    });

    test('강풍·높은 파고에서는 "매우나쁨"이 나온다', () {
      // 반대 방향 — 경고가 죽으면 안 된다.
      for (final s in estimatedSpeciesCatalog) {
        expect(
          estimateJiggingGrade(
            species: s,
            tideStrength: 0.05, // 조류는 최상
            windMs: 15,
            gustMs: 23,
            waveM: 3.0,
            month: 10, // 성수기
          ),
          FishingGrade.veryBad,
          reason: '$s: 강풍·높은 파고인데 매우나쁨이 아니다',
        );
      }
    });

    test('성수기 등급 분포가 목표대로 나온다', () {
      // 이 앱은 약간의 희망을 주자는 방침이라 목표 분포를 못박는다.
      // 서해 기준 15개 물때가 놓이는 상대 세기(사리를 축으로 좌우 대칭이라
      // 8개 값 중 사리만 홀수, 나머지는 두 칸씩).
      const strengths = <double>[
        0.011, 0.011, // 조금·무시
        0.096, 0.096, // 1물·13물
        0.250, 0.250, // 2물·12물
        0.448, 0.448, // 3물·11물
        0.655, 0.655, // 4물·10물
        0.835, 0.835, // 5물·9물
        0.957, 0.957, // 6물·8물
        1.000, // 7물(사리)
      ];
      Map<FishingGrade, int> distribution(String s, int month) {
        final counts = <FishingGrade, int>{};
        for (final t in strengths) {
          final g = estimateJiggingGrade(
            species: s,
            tideStrength: t,
            month: month,
          );
          counts[g] = (counts[g] ?? 0) + 1;
        }
        return counts;
      }

      const peak = {
        FishingGrade.veryGood: 2,
        FishingGrade.good: 4,
        FishingGrade.normal: 6,
        FishingGrade.bad: 3,
      };
      const shoulder = {
        FishingGrade.veryGood: 2,
        FishingGrade.good: 2,
        FishingGrade.normal: 8,
        FishingGrade.bad: 3,
      };
      // 11월은 개체수가 확 줄어드는 끝물이라 매우좋음이 아예 없다.
      const late = {
        FishingGrade.good: 2,
        FishingGrade.normal: 8,
        FishingGrade.bad: 5,
      };
      for (final s in estimatedSpeciesCatalog) {
        expect(distribution(s, 9), peak, reason: '$s 9월');
        expect(distribution(s, 10), shoulder, reason: '$s 10월');
        expect(distribution(s, 11), late, reason: '$s 11월');
      }
    });
  });

  group('제철 가중치', () {
    test('12개월이 모두 채워져 있다', () {
      // 빠진 달이 하한(0.30)으로 떨어지면 그 달은 물때가 아무리 좋아도
      // 한 등급으로 눌려 물때 차이가 화면에서 사라진다.
      for (final s in estimatedSpeciesCatalog) {
        for (var m = 1; m <= 12; m++) {
          expect(
            calmScore(s, 0.05, m),
            greaterThan(0.15),
            reason: '$s $m월: 최적 물때인데도 "나쁨" 아래로 눌렸다',
          );
        }
      }
    });

    test('9월 > 10월 > 11월 순으로 내려간다', () {
      // 9월 금어기 해제 직후가 최고이고, 11월은 개체수가 확 줄어드는 끝물.
      for (final s in estimatedSpeciesCatalog) {
        final sep = calmScore(s, 0.05, 9);
        final oct = calmScore(s, 0.05, 10);
        final nov = calmScore(s, 0.05, 11);
        expect(sep, greaterThan(oct), reason: '$s: 9월 > 10월');
        expect(oct, greaterThan(nov), reason: '$s: 10월 > 11월');
      }
      for (final s in ['쭈꾸미', '갑오징어']) {
        expect(
          calmScore(s, 0.05, 9),
          greaterThan(calmScore(s, 0.05, 8) * 1.5),
          reason: '$s: 9월 ≫ 8월(금어기 해제)',
        );
      }
    });

    test('비수기에도 물때 차이가 등급으로 드러난다', () {
      // 제보 화면(8월)에서 세 어종이 물때와 무관하게 전부 매우나쁨이던 문제.
      // 어종마다 좋아하는 물때가 다르므로, 특정 물때가 아니라 **한 달 안에서
      // 등급이 갈리는지**를 본다.
      const strengths = <double>[0.011, 0.096, 0.25, 0.448, 0.655, 0.835, 1.0];
      for (final s in estimatedSpeciesCatalog) {
        final grades = {
          for (final t in strengths)
            estimateJiggingGrade(species: s, tideStrength: t, month: 8),
        };
        expect(
          grades.length,
          greaterThanOrEqualTo(2),
          reason: '$s 8월: 물때가 달라도 전부 ${grades.first.label}',
        );
        // 그 어종이 가장 좋아하는 물때는 바닥이 아니어야 한다.
        final best = strengths
            .map(
              (t) =>
                  estimateJiggingScore(species: s, tideStrength: t, month: 8),
            )
            .reduce((a, b) => a > b ? a : b);
        expect(best, greaterThan(0.15), reason: '$s 8월: 최적 물때도 바닥');
      }
    });
  });

  group('조류 선호', () {
    test('쭈꾸미는 물이 느린 날이 좋다', () {
      final slow = calmScore('쭈꾸미', 0.15, 9); // 성수기
      final fast = calmScore('쭈꾸미', 0.85, 9);
      expect(slow, greaterThan(fast));
      expect(slow, greaterThan(0.7));
    });

    test('갑오징어는 약한 중간 > 정지 > 중간 > 급류 순', () {
      // 사용자 실사용 경험. 바닥 채비 낚시라 과한 조류가 없는 조류보다
      // 훨씬 해롭다 — 좌우 대칭 곡선으로는 이 순서가 나오지 않는다.
      final weak = calmScore('갑오징어', 0.30, 10); // 약한 중간
      final still = calmScore('갑오징어', 0.05, 10); // 정지
      final mid = calmScore('갑오징어', 0.50, 10); // 중간
      final fast = calmScore('갑오징어', 0.95, 10); // 급류
      expect(weak, greaterThan(still));
      expect(still, greaterThan(mid));
      expect(mid, greaterThan(fast));
    });

    test('세 어종 모두 정지가 급류보다 낫다', () {
      // 조류가 세면 라인이 눕고 바닥을 못 잡아 조작 자체가 안 된다.
      for (final s in ['쭈꾸미', '갑오징어', '문어']) {
        expect(
          calmScore(s, 0.02, 10),
          greaterThan(calmScore(s, 0.95, 10)),
          reason: '$s: 정지가 급류보다 나아야 한다',
        );
      }
    });

    test('문어는 조류를 크게 타지 않는다', () {
      final slow = calmScore('문어', 0.15, 10);
      final fast = calmScore('문어', 0.85, 10);
      // 두 어종보다 조류에 따른 낙차가 작아야 한다.
      final octoSpread = (slow - fast).abs();
      final jjukSpread =
          (calmScore('쭈꾸미', 0.15, 10) - calmScore('쭈꾸미', 0.85, 10)).abs();
      expect(octoSpread, lessThan(jjukSpread));
    });
  });

  group('바람·파고 감점', () {
    test('바람이 세면 조류가 좋아도 등급이 떨어진다', () {
      const best = (species: '쭈꾸미', tide: 0.18, month: 10);
      final calm = estimateJiggingScore(
        species: best.species,
        tideStrength: best.tide,
        windMs: 2,
        gustMs: 4,
        waveM: 0.3,
        month: best.month,
      );
      final blow = estimateJiggingScore(
        species: best.species,
        tideStrength: best.tide,
        windMs: 13,
        gustMs: 20,
        waveM: 2.6,
        month: best.month,
      );
      expect(blow, lessThan(calm * 0.35));
    });
  });

  group('제철', () {
    test('쭈꾸미는 가을이 봄보다 높다', () {
      expect(
        calmScore('쭈꾸미', 0.18, 10),
        greaterThan(calmScore('쭈꾸미', 0.18, 4)),
      );
    });

    test('문어는 봄에도 좋다', () {
      expect(calmScore('문어', 0.4, 4), greaterThan(0.6));
    });
  });

  group('등급 변환', () {
    test('좋은 조건은 좋은 등급, 나쁜 조건은 나쁜 등급', () {
      final good = estimateJiggingGrade(
        species: '쭈꾸미',
        tideStrength: 0.18,
        windMs: 2,
        gustMs: 4,
        waveM: 0.3,
        month: 10,
      );
      final bad = estimateJiggingGrade(
        species: '쭈꾸미',
        tideStrength: 0.95,
        windMs: 14,
        gustMs: 22,
        waveM: 3,
        month: 4,
      );
      expect(good.score, greaterThanOrEqualTo(FishingGrade.good.score));
      expect(bad, FishingGrade.veryBad);
    });

    test('모르는 어종은 0점', () {
      expect(calmScore('참돔', 0.3, 10), 0);
    });
  });

  group('목록', () {
    test('추정 어종은 관측 어종과 겹치지 않는다', () {
      for (final s in estimatedSpeciesCatalog) {
        expect(fishingSpeciesCatalog, isNot(contains(s)));
      }
      expect(estimatedSpeciesCatalog, ['쭈꾸미', '갑오징어', '문어']);
    });
  });
}

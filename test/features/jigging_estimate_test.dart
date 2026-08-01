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

  group('조류 선호', () {
    test('쭈꾸미는 물이 느린 날이 좋다', () {
      final slow = calmScore('쭈꾸미', 0.15, 10);
      final fast = calmScore('쭈꾸미', 0.85, 10);
      expect(slow, greaterThan(fast));
      expect(slow, greaterThan(0.7));
    });

    test('갑오징어는 조금 흐를 때가 좋다', () {
      final still = calmScore('갑오징어', 0.05, 10);
      final some = calmScore('갑오징어', 0.45, 10);
      final fast = calmScore('갑오징어', 0.95, 10);
      // 정지도 급류도 아닌 중간이 가장 좋아야 한다.
      expect(some, greaterThan(still));
      expect(some, greaterThan(fast));
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

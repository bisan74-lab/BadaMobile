import 'package:bada_mobile/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compassKo', () {
    test('주요 방위를 한글로 변환한다', () {
      expect(compassKo(0), '북');
      expect(compassKo(90), '동');
      expect(compassKo(180), '남');
      expect(compassKo(270), '서');
      expect(compassKo(45), '북동');
      expect(compassKo(225), '남서');
    });

    test('360도 경계와 음수 각도를 처리한다', () {
      expect(compassKo(360), '북');
      expect(compassKo(-90), '서');
      expect(compassKo(354), '북');
    });
  });

  test('formatMonthDay는 한국어 요일을 포함한다', () {
    // 2026-07-15는 수요일
    expect(formatMonthDay(DateTime(2026, 7, 15)), '7월 15일 (수)');
  });

  test('수치 포맷', () {
    expect(formatWind(3.25), '3.3m/s');
    expect(formatWave(1.0), '1.0m');
    expect(formatTideHeight(123.6), '124cm');
  });
}

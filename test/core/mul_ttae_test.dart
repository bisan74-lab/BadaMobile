import 'package:bada_mobile/core/utils/mul_ttae.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mulTtaeForLunarDay (7물때식)', () {
    test('음력 10일은 1물', () {
      expect(mulTtaeForLunarDay(10).label, '1물');
      expect(mulTtaeForLunarDay(25).label, '1물');
    });

    test('음력 8일·23일은 조금', () {
      expect(mulTtaeForLunarDay(8).label, '조금');
      expect(mulTtaeForLunarDay(23).label, '조금');
      expect(mulTtaeForLunarDay(8).isJogeum, isTrue);
    });

    test('음력 9일·24일은 무시', () {
      expect(mulTtaeForLunarDay(9).label, '무시');
      expect(mulTtaeForLunarDay(24).label, '무시');
    });

    test('음력 1일·16일은 7물(사리 부근)', () {
      expect(mulTtaeForLunarDay(1).label, '7물');
      expect(mulTtaeForLunarDay(16).label, '7물');
      expect(mulTtaeForLunarDay(16).isSari, isTrue);
    });

    test('15일 주기로 순환한다', () {
      for (var day = 1; day <= 15; day++) {
        expect(
          mulTtaeForLunarDay(day).index,
          mulTtaeForLunarDay(day + 15).index,
        );
      }
    });
  });

  group('approximateLunarDay', () {
    test('기준 신월 직후는 음력 1일', () {
      expect(approximateLunarDay(DateTime.utc(2000, 1, 6, 20)), 1);
    });

    test('신월 + 14일은 보름 부근(14~16일)', () {
      final day = approximateLunarDay(DateTime.utc(2000, 1, 20, 20));
      expect(day, inInclusiveRange(14, 16));
    });

    test('한 삭망월 뒤에는 같은 음력 일자로 돌아온다', () {
      final a = approximateLunarDay(DateTime.utc(2024, 3, 10));
      final b = approximateLunarDay(
        DateTime.utc(2024, 3, 10).add(const Duration(days: 30)),
      );
      // 29.53일 주기이므로 30일 뒤는 같은 날 또는 하루 차이.
      expect((b - a).abs() <= 1 || (b - a).abs() >= 28, isTrue);
    });
  });
}

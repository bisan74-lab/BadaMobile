import 'package:bada_mobile/core/utils/mul_ttae.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('7물때식 (서해)', () {
    test('음력 10일·25일은 1물', () {
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

  group('8물때식 (남해·동해·제주)', () {
    MulTtae south(int day) =>
        mulTtaeForLunarDay(day, system: MulTtaeSystem.south8);

    test('음력 1일·16일은 8물', () {
      expect(south(1).label, '8물');
      expect(south(16).label, '8물');
      expect(south(16).isSari, isTrue);
    });

    test('음력 9일·24일은 1물', () {
      expect(south(9).label, '1물');
      expect(south(24).label, '1물');
    });

    test('음력 8일·23일은 조금이고 무시는 없다', () {
      expect(south(8).label, '조금');
      expect(south(23).label, '조금');
      expect(mulTtaeLabelsSouth8, isNot(contains('무시')));
    });

    test('같은 날 서해와 남해 물때 번호는 1 차이난다', () {
      // 예: 음력 1일 → 서해 7물, 남해 8물
      for (final day in [1, 5, 16, 20]) {
        final west = mulTtaeForLunarDay(day);
        expect(
          '${int.parse(west.label.replaceAll('물', '')) + 1}물',
          south(day).label,
        );
      }
    });
  });

  group('mulTtaeSystemForRegion', () {
    test('서해만 7물때식, 나머지는 8물때식', () {
      expect(mulTtaeSystemForRegion('서해'), MulTtaeSystem.west7);
      expect(mulTtaeSystemForRegion('남해'), MulTtaeSystem.south8);
      expect(mulTtaeSystemForRegion('동해'), MulTtaeSystem.south8);
      expect(mulTtaeSystemForRegion('제주'), MulTtaeSystem.south8);
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

    test('2년 뒤 날짜에도 유효한 음력 일자를 반환한다 (단순 물때 2년 제공)', () {
      final farFuture = DateTime.now().add(maxSimpleMulTtaeRange);
      final day = approximateLunarDay(farFuture);
      expect(day, inInclusiveRange(1, 30));
      expect(mulTtaeFor(farFuture).label, isNotEmpty);
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

  group('천문 신월 기반 정확한 음력·물때 (실제 물때표 대조)', () {
    // KST 자정을 UTC로: 2026-07-24 00:00 KST = 2026-07-23 15:00 UTC.
    DateTime kstMidnightUtc(int y, int m, int d) =>
        DateTime.utc(y, m, d).subtract(const Duration(hours: 9));

    test('녹동항 2026-07-24는 음력 11일·3물(바다타임 물때표와 일치)', () {
      // 예전 평균삭망월 근사는 음력 9일·1물로 어긋났다(신월이 평균에서
      // 벗어난 달이라 날짜 경계를 넘음). 실제 신월은 2026-07-14 18:45 KST라
      // 7월24일은 음력 11일이 맞고, 8물때식으로 3물이다.
      final day = approximateLunarDay(kstMidnightUtc(2026, 7, 24));
      expect(day, 11);
      expect(mulTtaeForLunarDay(day, system: MulTtaeSystem.south8).label, '3물');
    });

    test('신월이 든 KST 날짜(2026-07-14)는 음력 1일', () {
      // 신월 2026-07-14 18:45 KST — 그날 이른 시각(정오)도 같은 음력 1일.
      expect(approximateLunarDay(DateTime.utc(2026, 7, 14, 3)), 1);
    });

    test('신월 전날(2026-07-13)은 직전 달 그믐(29~30일)', () {
      final day = approximateLunarDay(kstMidnightUtc(2026, 7, 13));
      expect(day, inInclusiveRange(29, 30));
    });
  });
}

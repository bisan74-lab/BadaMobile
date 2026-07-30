import 'package:bada_mobile/features/weather/presentation/weather_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 3시간 간격 표(상세 예보와 같은 형태).
  List<DateTime> steps3h(DateTime start, int n) => [
    for (var i = 0; i < n; i++) start.add(Duration(hours: 3 * i)),
  ];

  group('currentStepIndex — "지금"은 지나온 칸을 가리킨다', () {
    final start = DateTime(2026, 7, 30, 12); // 12,15,18,21,0,3,6,9
    final times = steps3h(start, 8);

    test('22:58이면 21시 칸이다 (00시가 더 가깝지만 미래라 안 된다)', () {
      final idx = currentStepIndex(times, DateTime(2026, 7, 30, 22, 58));
      expect(times[idx], DateTime(2026, 7, 30, 21));
    });

    test('칸 시각과 정확히 같으면 그 칸이다', () {
      final idx = currentStepIndex(times, DateTime(2026, 7, 30, 18));
      expect(times[idx], DateTime(2026, 7, 30, 18));
    });

    test('칸 직후(18:01)면 그 칸을 유지한다', () {
      final idx = currentStepIndex(times, DateTime(2026, 7, 30, 18, 1));
      expect(times[idx], DateTime(2026, 7, 30, 18));
    });

    test('다음 칸 직전(20:59)까지도 앞 칸이다', () {
      final idx = currentStepIndex(times, DateTime(2026, 7, 30, 20, 59));
      expect(times[idx], DateTime(2026, 7, 30, 18));
    });

    test('자정을 넘겨 00:30이면 00시 칸으로 넘어간다', () {
      final idx = currentStepIndex(times, DateTime(2026, 7, 31, 0, 30));
      expect(times[idx], DateTime(2026, 7, 31, 0));
    });

    test('표 전체가 미래면 첫 칸을 쓴다', () {
      final idx = currentStepIndex(times, DateTime(2026, 7, 30, 9));
      expect(idx, 0);
    });

    test('표 전체가 과거면 마지막 칸을 쓴다', () {
      final idx = currentStepIndex(times, DateTime(2026, 8, 5));
      expect(idx, times.length - 1);
    });

    test('빈 목록도 0을 돌려준다', () {
      expect(currentStepIndex(const [], DateTime(2026, 7, 30)), 0);
    });
  });
}

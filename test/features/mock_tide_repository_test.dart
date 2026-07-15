import 'package:bada_mobile/features/locations/data/sample_locations.dart';
import 'package:bada_mobile/features/tide/data/repositories/mock_tide_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final repo = MockTideRepository();
  final date = DateTime(2026, 7, 15);

  test('25개의 시간별 조위를 반환한다', () async {
    final tide = await repo.fetchTideDay(sampleLocations.first, date);
    expect(tide.hourlyHeightsCm, hasLength(25));
    expect(tide.date, DateTime(2026, 7, 15));
  });

  test('만조/간조가 번갈아 나타난다', () async {
    final tide = await repo.fetchTideDay(sampleLocations.first, date);
    expect(tide.extremes.length, inInclusiveRange(3, 5));
    for (var i = 1; i < tide.extremes.length; i++) {
      expect(
        tide.extremes[i].isHigh,
        isNot(tide.extremes[i - 1].isHigh),
        reason: '만조와 간조는 번갈아 나타나야 한다',
      );
    }
  });

  test('만조 조위가 간조 조위보다 높다', () async {
    final tide = await repo.fetchTideDay(sampleLocations.first, date);
    final highs = tide.extremes.where((e) => e.isHigh).map((e) => e.heightCm);
    final lows = tide.extremes.where((e) => !e.isHigh).map((e) => e.heightCm);
    expect(highs, isNotEmpty);
    expect(lows, isNotEmpty);
    expect(
      highs.reduce((a, b) => a < b ? a : b),
      greaterThan(lows.reduce((a, b) => a > b ? a : b)),
    );
  });

  test('서해 지점의 조차가 동해 지점보다 크다', () async {
    final west = await repo.fetchTideDay(
      sampleLocations.firstWhere((l) => l.region == '서해'),
      date,
    );
    final east = await repo.fetchTideDay(
      sampleLocations.firstWhere((l) => l.region == '동해'),
      date,
    );

    double range(List<double> hs) =>
        hs.reduce((a, b) => a > b ? a : b) - hs.reduce((a, b) => a < b ? a : b);

    expect(
      range(west.hourlyHeightsCm),
      greaterThan(range(east.hourlyHeightsCm)),
    );
  });
}

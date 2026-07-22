import 'dart:convert';
import 'dart:math' as math;

import 'package:bada_mobile/features/weather/data/models/wind_field.dart';
import 'package:bada_mobile/features/weather/data/repositories/mock_wind_field_repository.dart';
import 'package:bada_mobile/features/weather/data/repositories/open_meteo_wind_field_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('windToUv', () {
    void expectClose(double a, double b) => expect(a, closeTo(b, 1e-9));

    test('북풍(0도, 남쪽으로 붐)은 v가 음수', () {
      final (u, v) = windToUv(10, 0);
      expectClose(u, 0);
      expectClose(v, -10);
    });

    test('동풍(90도, 서쪽으로 붐)은 u가 음수', () {
      final (u, v) = windToUv(10, 90);
      expectClose(u, -10);
      expectClose(v, 0);
    });

    test('남풍(180도, 북쪽으로 붐)은 v가 양수', () {
      final (u, v) = windToUv(10, 180);
      expectClose(u, 0);
      expectClose(v, 10);
    });

    test('서풍(270도, 동쪽으로 붐)은 u가 양수', () {
      final (u, v) = windToUv(10, 270);
      expectClose(u, 10);
      expectClose(v, 0);
    });
  });

  group('WindField.sample (쌍선형 보간)', () {
    // 2x2 격자: (lat,lon) 코너마다 다른 u값, 나머지는 0.
    final field = WindField(
      time: DateTime(2026, 7, 16),
      minLat: 0,
      maxLat: 10,
      minLon: 0,
      maxLon: 10,
      latSteps: 2,
      lonSteps: 2,
      u: [0, 10, 20, 30], // (0,0)=0 (0,10)=10 (10,0)=20 (10,10)=30
      v: [0, 0, 0, 0],
    );

    test('격자점에서는 그 값과 정확히 일치한다', () {
      expect(field.sample(0, 0)!.$1, 0);
      expect(field.sample(0, 10)!.$1, 10);
      expect(field.sample(10, 0)!.$1, 20);
      expect(field.sample(10, 10)!.$1, 30);
    });

    test('중앙점은 네 코너의 평균이다', () {
      final (u, _) = field.sample(5, 5)!;
      expect(u, closeTo((0 + 10 + 20 + 30) / 4, 1e-9));
    });

    test('범위 밖은 null을 돌려준다', () {
      expect(field.sample(-1, 5), isNull);
      expect(field.sample(5, 11), isNull);
    });
  });

  group('WindField.sample (적응형/비균일 격자 + bicubic)', () {
    // 4x4 비균일 격자(적응형 격자를 흉내): 위·경도 간격이 점점 넓어진다.
    const lats = [0.0, 1.0, 3.0, 6.0];
    const lons = [0.0, 2.0, 3.0, 7.0];
    // u(i,j) = i*10 + j로 둬서 각 격자점의 정확한 기대값을 바로 계산한다.
    final u = [
      for (final _ in lats)
        for (final _ in lons) 0.0,
    ];
    for (var i = 0; i < lats.length; i++) {
      for (var j = 0; j < lons.length; j++) {
        u[i * lons.length + j] = i * 10.0 + j;
      }
    }
    final field = WindField(
      time: DateTime(2026, 7, 22),
      minLat: lats.first,
      maxLat: lats.last,
      minLon: lons.first,
      maxLon: lons.last,
      latSteps: lats.length,
      lonSteps: lons.length,
      lats: lats,
      lons: lons,
      u: u,
      v: List.filled(u.length, 0),
    );

    test('격자점(비균일 간격)에서는 그 값과 정확히 일치한다', () {
      for (var i = 0; i < lats.length; i++) {
        for (var j = 0; j < lons.length; j++) {
          final (uu, _) = field.sample(lats[i], lons[j])!;
          expect(uu, closeTo(i * 10.0 + j, 1e-6), reason: 'i=$i j=$j');
        }
      }
    });

    test('격자 사이 값은 주변 값들 사이 범위 안에 있다(과도한 오버슈트 없음)', () {
      final (uu, _) = field.sample(2.0, 2.5)!;
      expect(uu, greaterThan(0));
      expect(uu, lessThan(field.u.reduce((a, b) => a > b ? a : b)));
    });

    test('범위 밖은 null', () {
      expect(field.sample(-1, 0), isNull);
      expect(field.sample(0, 8), isNull);
    });
  });

  group('OpenMeteoWindFieldRepository', () {
    test('격자점 수만큼 요청하고 u/v로 변환해 반환한다', () async {
      const latSteps = OpenMeteoWindFieldRepository.latSteps;
      const lonSteps = OpenMeteoWindFieldRepository.lonSteps;
      final total = latSteps * lonSteps;

      // 격자는 배치(≤100좌표)로 나뉘어 여러 번 요청되고 순서대로 합쳐진다.
      final client = MockClient((request) async {
        expect(request.url.host, 'api.open-meteo.com');
        expect(request.url.path, '/v1/forecast');
        final lats = request.url.queryParameters['latitude']!.split(',');
        final lons = request.url.queryParameters['longitude']!.split(',');
        expect(lats.length, lons.length);
        expect(lats.length, lessThanOrEqualTo(100)); // 한 요청은 배치 크기 이하
        expect(request.url.queryParameters['wind_speed_unit'], 'ms');

        final list = List.generate(
          lats.length,
          (i) => {
            'current': {
              'time': '2026-07-16T09:00',
              'wind_speed_10m': 5.0,
              'wind_direction_10m': 180.0, // 남풍 → v=+5, u=0
            },
          },
        );
        return http.Response(
          jsonEncode(list),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final repo = OpenMeteoWindFieldRepository(client: client);
      final field = await repo.fetchField();

      expect(field.latSteps, latSteps);
      expect(field.lonSteps, lonSteps);
      expect(field.u, hasLength(total));
      expect(field.v, hasLength(total));
      for (var i = 0; i < total; i++) {
        expect(field.u[i], closeTo(0, 1e-9));
        expect(field.v[i], closeTo(5, 1e-9));
      }
    });

    test('응답 개수가 요청과 다르면 예외를 던진다', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });
      final repo = OpenMeteoWindFieldRepository(client: client);
      expect(repo.fetchField, throwsFormatException);
    });

    test('fetchSeries는 시간별 격자를 요청 시간 수만큼 반환한다', () async {
      const latSteps = OpenMeteoWindFieldRepository.latSteps;
      const lonSteps = OpenMeteoWindFieldRepository.lonSteps;
      final total = latSteps * lonSteps;
      const hours = 6;

      // 격자는 배치(≤100좌표)로 나뉘어 여러 번 요청되고 순서대로 합쳐진다.
      final client = MockClient((request) async {
        expect(
          request.url.queryParameters['hourly'],
          contains('wind_speed_10m'),
        );
        final lats = request.url.queryParameters['latitude']!.split(',');
        expect(lats.length, lessThanOrEqualTo(100));
        final times = List.generate(
          24,
          (h) => '2026-07-16T${h.toString().padLeft(2, '0')}:00',
        );
        final list = List.generate(
          lats.length,
          (i) => {
            'hourly': {
              'time': times,
              'wind_speed_10m': List.filled(24, 5.0),
              'wind_direction_10m': List.filled(24, 180.0),
            },
          },
        );
        return http.Response(
          jsonEncode(list),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final repo = OpenMeteoWindFieldRepository(client: client);
      final series = await repo.fetchSeries(hours: hours);

      expect(series.length, hours);
      for (final field in series.hourly) {
        expect(field.u, hasLength(total));
        expect(field.v[0], closeTo(5, 1e-9)); // 남풍 → v=+5
      }
      expect(series.at(0).time, series.hourly.first.time);
      expect(series.at(9999).time, series.hourly.last.time); // 범위 밖은 끝 고정
    });

    test('fetchPointSeries는 지점 좌표를 그대로 요청해 시간별 바람을 준다', () async {
      final client = MockClient((request) async {
        // 격자 배치가 아니라 탭한 좌표 하나를 그대로 요청한다.
        expect(request.url.queryParameters['latitude'], '36.2500');
        expect(request.url.queryParameters['longitude'], '126.0800');
        expect(
          request.url.queryParameters['hourly'],
          contains('wind_speed_10m'),
        );
        final times = List.generate(
          24,
          (h) => '2026-07-20T${h.toString().padLeft(2, '0')}:00',
        );
        return http.Response(
          jsonEncode({
            'hourly': {
              'time': times,
              'wind_speed_10m': List.filled(24, 8.0),
              'wind_direction_10m': List.filled(24, 180.0),
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final repo = OpenMeteoWindFieldRepository(client: client);
      final list = await repo.fetchPointSeries(36.25, 126.08);

      expect(list, hasLength(24));
      expect(list.first.speedMs, closeTo(8, 1e-9));
      expect(list.first.directionDeg, closeTo(180, 1e-9));
      expect(list[23].time.hour, 23);
    });
  });

  group('MockWindFieldRepository', () {
    test('격자 크기가 실데이터 리포지토리와 동일하고 유효한 값만 담는다', () async {
      final field = await MockWindFieldRepository().fetchField();
      const total =
          OpenMeteoWindFieldRepository.latSteps *
          OpenMeteoWindFieldRepository.lonSteps;
      expect(field.u, hasLength(total));
      expect(field.v, hasLength(total));
      for (var i = 0; i < total; i++) {
        expect(field.u[i].isFinite, isTrue);
        expect(field.v[i].isFinite, isTrue);
        expect(
          math.sqrt(field.u[i] * field.u[i] + field.v[i] * field.v[i]),
          lessThan(30),
        );
      }
    });

    test('fetchSeries는 요청 시간 수만큼 스냅샷을 만든다', () async {
      final series = await MockWindFieldRepository().fetchSeries(hours: 12);
      expect(series.length, 12);
      const total =
          OpenMeteoWindFieldRepository.latSteps *
          OpenMeteoWindFieldRepository.lonSteps;
      for (final field in series.hourly) {
        expect(field.u, hasLength(total));
      }
    });
  });
}

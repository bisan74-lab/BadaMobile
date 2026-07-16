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

  group('OpenMeteoWindFieldRepository', () {
    test('격자점 수만큼 요청하고 u/v로 변환해 반환한다', () async {
      const latSteps = OpenMeteoWindFieldRepository.latSteps;
      const lonSteps = OpenMeteoWindFieldRepository.lonSteps;
      final total = latSteps * lonSteps;

      final client = MockClient((request) async {
        expect(request.url.host, 'api.open-meteo.com');
        expect(request.url.path, '/v1/forecast');
        final lats = request.url.queryParameters['latitude']!.split(',');
        final lons = request.url.queryParameters['longitude']!.split(',');
        expect(lats, hasLength(total));
        expect(lons, hasLength(total));
        expect(request.url.queryParameters['wind_speed_unit'], 'ms');

        final list = List.generate(
          total,
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
  });
}

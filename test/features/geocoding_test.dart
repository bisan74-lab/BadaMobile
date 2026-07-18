import 'dart:convert';

import 'package:bada_mobile/features/locations/data/geocoding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('지오코딩 결과를 이름·상위행정구역·좌표로 파싱한다', () async {
    final client = MockClient((req) async {
      expect(req.url.host, 'geocoding-api.open-meteo.com');
      expect(req.url.queryParameters['name'], '마곡동');
      return http.Response(
        jsonEncode({
          'results': [
            {
              'name': '마곡동',
              'latitude': 37.56,
              'longitude': 126.83,
              'admin1': '서울특별시',
              'admin2': '강서구',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final places = await GeocodingRepository(client: client).search('마곡동');
    expect(places, hasLength(1));
    expect(places.first.name, '마곡동');
    expect(places.first.admin, '서울특별시 강서구');
    expect(places.first.latitude, 37.56);
    final loc = places.first.toLocation();
    expect(loc.inland, isTrue);
    expect(loc.latitude, 37.56);
  });

  test('짧은 검색어·빈 결과는 빈 목록', () async {
    final client = MockClient((req) async => http.Response('{}', 200));
    final repo = GeocodingRepository(client: client);
    expect(await repo.search('가'), isEmpty);
    expect(await repo.search('없는지명'), isEmpty);
  });
}

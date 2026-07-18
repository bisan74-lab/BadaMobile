import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models/sea_location.dart';

/// 지오코딩 검색 결과 한 건(지명 + 좌표).
class GeoPlace {
  const GeoPlace({
    required this.name,
    required this.admin,
    required this.latitude,
    required this.longitude,
  });

  final String name;

  /// 상위 행정구역 표기(예: "서울특별시 강서구").
  final String admin;
  final double latitude;
  final double longitude;

  String get displayName => admin.isEmpty ? name : '$name · $admin';

  /// 선택 시 앱 전역에서 쓰는 즉석 [SeaLocation]으로 변환.
  SeaLocation toLocation() => SeaLocation(
    id: 'geo_${latitude.toStringAsFixed(4)}_${longitude.toStringAsFixed(4)}',
    name: name,
    region: '검색',
    latitude: latitude,
    longitude: longitude,
    inland: true,
  );
}

/// Open-Meteo Geocoding API(무료·키 불필요)로 지명을 검색한다.
/// 시/군/구·읍/면/동 등 등록된 지명을 좌표와 함께 돌려준다(전 세계).
class GeocodingRepository {
  GeocodingRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const _host = 'geocoding-api.open-meteo.com';

  Future<List<GeoPlace>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final uri = Uri.https(_host, '/v1/search', {
      'name': q,
      'count': '8',
      'language': 'ko',
    });
    final res = await _client.get(uri);
    if (res.statusCode != 200) return const [];
    final root = jsonDecode(utf8.decode(res.bodyBytes));
    if (root is! Map<String, dynamic>) return const [];
    final results = root['results'];
    if (results is! List) return const [];
    return [
      for (final r in results)
        if (r is Map<String, dynamic> &&
            r['latitude'] != null &&
            r['longitude'] != null)
          GeoPlace(
            name: r['name']?.toString() ?? '',
            admin: [
              r['admin1'],
              r['admin2'],
              r['admin3'],
            ].where((v) => v != null && v.toString().isNotEmpty).join(' '),
            latitude: (r['latitude'] as num).toDouble(),
            longitude: (r['longitude'] as num).toDouble(),
          ),
    ];
  }
}

/// 해양 관측/예보 지점.
class SeaLocation {
  const SeaLocation({
    required this.id,
    required this.name,
    required this.region,
    required this.latitude,
    required this.longitude,
    this.khoaStationCode,
    this.khoaStationCodes,
    this.rank = 2,
    this.inland = false,
  });

  final String id;
  final String name;

  /// 서해 / 남해 / 동해 / 제주 / 내륙
  final String region;
  final double latitude;
  final double longitude;

  /// KHOA 바다누리 조위관측소 코드 (실 API 연동 시 사용, 단일 관측소).
  final String? khoaStationCode;

  /// 지점이 여러 관측소 "사이"에 있어 단일 관측소로는 오차가 큰 경우,
  /// 인접 관측소 2~4곳을 지정하면 조석을 **거리가중으로 보간**한다
  /// (매칭된 만조/간조끼리 시각·조위를 거리비례 평균 → 위상차 진폭손실 없음).
  /// 지정 시 [khoaStationCode]보다 우선한다.
  final List<String>? khoaStationCodes;

  /// 조석 실데이터에 쓸 관측소 코드 목록(다지점 우선, 없으면 단일, 둘 다
  /// 없으면 빈 목록 → 합성 폴백).
  List<String> get tideStationCodes {
    final multi = khoaStationCodes;
    if (multi != null && multi.isNotEmpty) return multi;
    final single = khoaStationCode;
    return single != null ? [single] : const [];
  }

  /// 표시 우선순위(1=주요 항구/대도시 → 3=소규모). 지도 확대 단계별 라벨
  /// 노출과 겹침 방지에 쓴다(작을수록 먼저 표시).
  final int rank;

  /// 내륙 도시 등 바다 지도 마커로는 부적합하지만 날씨 검색에는 필요한 지점.
  /// true면 Windy 지도 마커에서는 제외하고, 검색·날씨에서는 그대로 쓴다.
  final bool inland;

  @override
  bool operator ==(Object other) => other is SeaLocation && other.id == id;

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'region': region,
    'latitude': latitude,
    'longitude': longitude,
    'khoaStationCode': khoaStationCode,
    'khoaStationCodes': khoaStationCodes,
    'rank': rank,
    'inland': inland,
  };

  factory SeaLocation.fromJson(Map<String, dynamic> j) => SeaLocation(
    id: j['id'] as String,
    name: j['name'] as String,
    region: j['region'] as String,
    latitude: (j['latitude'] as num).toDouble(),
    longitude: (j['longitude'] as num).toDouble(),
    khoaStationCode: j['khoaStationCode'] as String?,
    khoaStationCodes: (j['khoaStationCodes'] as List?)
        ?.map((e) => e as String)
        .toList(),
    rank: (j['rank'] as num?)?.toInt() ?? 2,
    inland: j['inland'] as bool? ?? false,
  );
}

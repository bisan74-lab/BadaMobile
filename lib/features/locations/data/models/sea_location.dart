/// 해양 관측/예보 지점.
class SeaLocation {
  const SeaLocation({
    required this.id,
    required this.name,
    required this.region,
    required this.latitude,
    required this.longitude,
    this.khoaStationCode,
  });

  final String id;
  final String name;

  /// 서해 / 남해 / 동해 / 제주
  final String region;
  final double latitude;
  final double longitude;

  /// KHOA 바다누리 조위관측소 코드 (실 API 연동 시 사용).
  final String? khoaStationCode;

  @override
  bool operator ==(Object other) => other is SeaLocation && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

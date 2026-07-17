/// 해역별 기준 어종 우선순위. 서해는 쭈꾸미·갑오징어, 남해는 문어,
/// 동해는 문어·광어·우럭 순으로 대표 지수를 고른다.
List<String> preferredSpeciesForRegion(String region) => switch (region) {
  '서해' => const ['쭈꾸미', '갑오징어'],
  '남해' => const ['문어', '광어', '우럭'],
  '동해' => const ['문어', '광어', '우럭'],
  _ => const ['문어', '광어', '우럭'],
};

/// 바다낚시지수 등급 (국립해양조사원 5단계).
enum FishingGrade {
  veryBad('매우나쁨', 1),
  bad('나쁨', 2),
  normal('보통', 3),
  good('좋음', 4),
  veryGood('매우좋음', 5);

  const FishingGrade(this.label, this.score);

  final String label;

  /// 1(매우나쁨) ~ 5(매우좋음)
  final int score;

  static FishingGrade fromScore(int score) =>
      values.firstWhere((g) => g.score == score.clamp(1, 5));

  static FishingGrade fromLabel(String label) => values.firstWhere(
    (g) => g.label == label.trim(),
    orElse: () => FishingGrade.normal,
  );
}

/// 특정 지점·날짜·시간대·어종의 바다낚시지수.
class FishingIndex {
  const FishingIndex({
    required this.date,
    required this.timeSlot,
    required this.grade,
    this.species,
    this.pointName,
    this.tidePhase,
    this.waveHeightM,
    this.waterTempC,
  });

  final DateTime date;

  /// '오전' / '오후'
  final String timeSlot;
  final FishingGrade grade;

  /// 대상 어종 (감성돔, 참돔, 농어 등 — API가 어종별 지수를 제공).
  final String? species;

  /// 낚시 포인트 이름 (예: 가거도).
  final String? pointName;

  /// 물때 구분 (대조기/중조기/소조기 등).
  final String? tidePhase;
  final double? waveHeightM;
  final double? waterTempC;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'timeSlot': timeSlot,
    'grade': grade.name,
    'species': species,
    'pointName': pointName,
    'tidePhase': tidePhase,
    'waveHeightM': waveHeightM,
    'waterTempC': waterTempC,
  };

  factory FishingIndex.fromJson(Map<String, dynamic> json) => FishingIndex(
    date: DateTime.parse(json['date'] as String),
    timeSlot: json['timeSlot'] as String,
    grade: FishingGrade.values.byName(json['grade'] as String),
    species: json['species'] as String?,
    pointName: json['pointName'] as String?,
    tidePhase: json['tidePhase'] as String?,
    waveHeightM: (json['waveHeightM'] as num?)?.toDouble(),
    waterTempC: (json['waterTempC'] as num?)?.toDouble(),
  );
}

/// 지점별 낚시지수 예보 묶음.
class FishingForecast {
  const FishingForecast({required this.locationId, required this.indices});

  final String locationId;

  /// 날짜·시간대 순.
  final List<FishingIndex> indices;

  /// [date]와 같은 날짜의 지수들 (모든 어종).
  List<FishingIndex> forDate(DateTime date) => indices
      .where(
        (i) =>
            i.date.year == date.year &&
            i.date.month == date.month &&
            i.date.day == date.day,
      )
      .toList();

  /// [date]의 대표 어종 지수. [preferredSpecies] 우선순위대로 찾고,
  /// 하나도 없으면 그 날짜에 있는 첫 어종으로 대체한다.
  List<FishingIndex> representativeForDate(
    DateTime date, {
    List<String> preferredSpecies = const ['감성돔'],
  }) {
    final day = forDate(date);
    if (day.isEmpty) return day;
    final bySpecies = <String?, List<FishingIndex>>{};
    for (final i in day) {
      bySpecies.putIfAbsent(i.species, () => []).add(i);
    }
    for (final species in preferredSpecies) {
      final match = bySpecies[species];
      if (match != null) return match;
    }
    return bySpecies.values.first;
  }

  Map<String, dynamic> toJson() => {
    'locationId': locationId,
    'indices': indices.map((i) => i.toJson()).toList(),
  };

  factory FishingForecast.fromJson(Map<String, dynamic> json) =>
      FishingForecast(
        locationId: json['locationId'] as String,
        indices: (json['indices'] as List)
            .map((i) => FishingIndex.fromJson(i as Map<String, dynamic>))
            .toList(),
      );
}

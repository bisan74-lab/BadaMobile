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

/// 특정 지점·날짜·시간대의 바다낚시지수.
class FishingIndex {
  const FishingIndex({
    required this.date,
    required this.timeSlot,
    required this.grade,
    this.species,
    this.waveHeightM,
    this.waterTempC,
  });

  final DateTime date;

  /// '오전' / '오후'
  final String timeSlot;
  final FishingGrade grade;

  /// 대상 어종 (API가 어종별 지수를 제공).
  final String? species;
  final double? waveHeightM;
  final double? waterTempC;
}

/// 지점별 낚시지수 예보 묶음.
class FishingForecast {
  const FishingForecast({required this.locationId, required this.indices});

  final String locationId;

  /// 날짜·시간대 순.
  final List<FishingIndex> indices;

  /// [date]와 같은 날짜의 지수들.
  List<FishingIndex> forDate(DateTime date) => indices
      .where(
        (i) =>
            i.date.year == date.year &&
            i.date.month == date.month &&
            i.date.day == date.day,
      )
      .toList();
}

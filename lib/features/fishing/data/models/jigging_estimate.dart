/// 물때(조류 세기)와 바람으로 **추정**하는 어종 지수.
///
/// 바다낚시지수 API가 주는 어종은 감성돔·농어·돌돔·벵에돔·우럭·참돔 6종뿐이라
/// (`gubun`을 바꿔도 늘지 않는다) 쭈꾸미·갑오징어·문어는 관측 기반 지수를
/// 받을 수 없다. 대신 이 세 어종은 **조류 세기에 대한 선호가 뚜렷해서**
/// 앱이 이미 가진 값(그날 조위 변화폭 + 지점 예보의 바람·파고)으로 대략적인
/// 좋고 나쁨을 짚을 수 있다.
///
/// **관측값이 아니라 추정값이다.** 화면에서는 반드시 "추정"으로 표시하고,
/// 관측 기반 지수와 섞어서 같은 것처럼 보이게 하지 않는다.
library;

import 'dart:math' as math;

import 'fishing_index.dart';

/// 이 방식으로 지수를 만들 수 있는 어종. [fishingSpeciesCatalog](관측 기반)와
/// 겹치지 않는다.
const estimatedSpeciesCatalog = <String>['쭈꾸미', '갑오징어', '문어'];

/// 사용자가 고를 수 있는 어종 전체 = 관측 기반 + 추정.
/// 선택을 저장·복원할 때 이 목록으로 거른다(둘 중 하나만 쓰면 추정 어종을
/// 골라도 저장이 안 된다).
const allSelectableSpecies = <String>[
  ...fishingSpeciesCatalog,
  ...estimatedSpeciesCatalog,
];

/// 어종별 조류 선호. [optimum]은 가장 좋은 조류 세기(0~1), [tolerance]는
/// 그 주변으로 얼마나 너그러운지다(클수록 조류를 덜 탄다).
///
/// - 쭈꾸미: 물이 느린 날에 잘 된다 → 낮은 쪽에 좁게
/// - 갑오징어: 조금 흘러야 잘 된다 → 중간에서 조금 낮은 쪽
/// - 문어: 조류를 크게 타지 않는다 → 넓게
const _tidePreference = <String, ({double optimum, double tolerance})>{
  '쭈꾸미': (optimum: 0.18, tolerance: 0.24),
  '갑오징어': (optimum: 0.45, tolerance: 0.26),
  '문어': (optimum: 0.40, tolerance: 0.48),
};

/// 어종별 제철(월). 이 세 어종은 계절을 크게 타서, 조류·바람이 아무리 좋아도
/// 철이 아니면 잘 안 나온다. 값은 그 달의 가중치(0~1)다.
const _season = <String, Map<int, double>>{
  // 가을이 성수기. 초여름 새끼는 잡지 않는 게 관례라 낮게 둔다.
  '쭈꾸미': {8: 0.55, 9: 1.0, 10: 1.0, 11: 0.8, 12: 0.4},
  // 쭈꾸미보다 조금 늦게 시작해 겨울까지 이어진다.
  '갑오징어': {9: 0.7, 10: 1.0, 11: 1.0, 12: 0.8, 1: 0.4, 5: 0.5, 6: 0.5},
  // 봄·가을 두 번 좋고 한여름·한겨울에 처진다.
  '문어': {
    1: 0.5,
    2: 0.6,
    3: 0.85,
    4: 1.0,
    5: 0.9,
    6: 0.6,
    7: 0.45,
    8: 0.45,
    9: 0.7,
    10: 0.95,
    11: 1.0,
    12: 0.7,
  },
};

/// 그날 조위 변화폭으로 매긴 조류 세기(0~1).
///
/// 대조기 조차(약 800cm)를 상한으로 정규화한다. 물때 화면의 "조류세기"
/// 막대와 **같은 값**이라, 화면에 보이는 세기와 추정 지수가 어긋나지 않는다.
double tideStrengthFraction(List<double> hourlyHeightsCm) {
  if (hourlyHeightsCm.isEmpty) return 0;
  final maxV = hourlyHeightsCm.reduce(math.max);
  final minV = hourlyHeightsCm.reduce(math.min);
  return ((maxV - minV) / 800).clamp(0.0, 1.0);
}

/// 바람·파고가 만드는 감점(0~1). 셋 다 배·연안에서 채비를 세워 하는 낚시라
/// 바람이 세면 조류 선호와 무관하게 조과가 떨어진다.
double _weatherFactor(double windMs, double gustMs, double waveM) {
  // 4m/s까지는 감점 없음, 12m/s에서 바닥.
  double drop(double v, double from, double to) =>
      ((v - from) / (to - from)).clamp(0.0, 1.0);
  final byWind = 1 - 0.75 * drop(windMs, 4, 12);
  final byGust = 1 - 0.45 * drop(gustMs, 9, 18);
  final byWave = 1 - 0.60 * drop(waveM, 0.8, 2.5);
  return (byWind * byGust * byWave).clamp(0.05, 1.0);
}

/// 어종·조건으로 추정 점수(0~1)를 낸다. 등급이 필요하면
/// [estimateJiggingGrade]를 쓴다.
double estimateJiggingScore({
  required String species,
  required double tideStrength,
  required double windMs,
  required double gustMs,
  required double waveM,
  required int month,
}) {
  final pref = _tidePreference[species];
  if (pref == null) return 0;

  // 선호 세기에서 멀어질수록 종 모양으로 떨어진다.
  final d = (tideStrength - pref.optimum) / pref.tolerance;
  final byTide = math.exp(-d * d);

  final bySeason = _season[species]?[month] ?? 0.25;
  final byWeather = _weatherFactor(windMs, gustMs, waveM);

  return (byTide * bySeason * byWeather).clamp(0.0, 1.0);
}

/// 추정 점수를 화면에 쓰는 5단계 등급으로 바꾼다.
FishingGrade estimateJiggingGrade({
  required String species,
  required double tideStrength,
  required double windMs,
  required double gustMs,
  required double waveM,
  required int month,
}) {
  final score = estimateJiggingScore(
    species: species,
    tideStrength: tideStrength,
    windMs: windMs,
    gustMs: gustMs,
    waveM: waveM,
    month: month,
  );
  if (score >= 0.72) return FishingGrade.veryGood;
  if (score >= 0.52) return FishingGrade.good;
  if (score >= 0.32) return FishingGrade.normal;
  if (score >= 0.15) return FishingGrade.bad;
  return FishingGrade.veryBad;
}

/// 추정 지수 한 칸(어종 × 오전/오후).
class JiggingEstimate {
  const JiggingEstimate({
    required this.species,
    required this.timeSlot,
    required this.grade,
  });

  final String species;

  /// '오전' / '오후'.
  final String timeSlot;
  final FishingGrade grade;
}

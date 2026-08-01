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

import '../../../../core/utils/mul_ttae.dart';
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

/// 어종별 조류 선호 곡선. `(조류 세기, 계수)` 제어점을 선형 보간해 쓴다.
///
/// **종 모양 수식(가우시안)이 아니라 제어점 표인 이유**: 물때는 15단계 이산값
/// 이고, 화면에 나오는 **등급 분포를 직접 정해야** 하기 때문이다. 수식으로는
/// 최적 부근이 평평해서 "1물만 매우좋음, 조금·2물은 좋음" 같은 배분이 아예
/// 안 나온다(실제로 여러 번 시도해 안 되는 걸 확인했다). 제어점을 물때 위상
/// 값에 맞춰 두면 원하는 분포가 그대로 나오고, 나중에 조정하기도 쉽다.
///
/// x값은 [relativeTideStrength]가 내는 **지점 상대 세기**이고, 서해 기준으로
/// 15개 물때가 놓이는 위상값(아래 주석)과 같은 자리에 제어점을 뒀다.
/// 조차가 작은 곳은 세기가 덜 올라가 곡선의 왼쪽만 쓰므로 조금 더 후하게
/// 나온다(동해에선 사리여도 물이 덜 가니 맞는 방향이다).
///
///     조금·무시 0.011 │ 1·13물 0.096 │ 2·12물 0.25 │ 3·11물 0.448
///     4·10물 0.655   │ 5·9물 0.835  │ 6·8물 0.957 │ 7물(사리) 1.0
///
/// - 쭈꾸미: 1물이 정점, 조금·2물이 그다음. 세지면 완만히 내려간다.
/// - 갑오징어: 2물(약한 중간)이 정점. **정지 > 중간 > 급류** 순
///   (사용자 실사용 경험) — 그래서 왼쪽이 오른쪽보다 높게 시작한다.
/// - 문어: 3물 부근이 정점이고 양쪽이 넓다(조류를 크게 타지 않는다).
const _tideCurve = <String, List<(double, double)>>{
  '쭈꾸미': [
    (0.000, 0.60),
    (0.096, 0.92),
    (0.250, 0.54),
    (0.448, 0.46),
    (0.655, 0.40),
    (0.835, 0.35),
    (0.957, 0.22),
    (1.000, 0.18),
  ],
  '갑오징어': [
    (0.000, 0.52),
    (0.096, 0.60),
    (0.250, 0.92),
    (0.448, 0.46),
    (0.655, 0.40),
    (0.835, 0.35),
    (0.957, 0.22),
    (1.000, 0.18),
  ],
  '문어': [
    (0.000, 0.44),
    (0.096, 0.46),
    (0.250, 0.60),
    (0.448, 0.92),
    (0.655, 0.54),
    (0.835, 0.40),
    (0.957, 0.22),
    (1.000, 0.18),
  ],
};

/// [_tideCurve]를 선형 보간한다. 모르는 어종이면 null.
double? _tideFactor(String species, double strength) {
  final pts = _tideCurve[species];
  if (pts == null) return null;
  if (strength <= pts.first.$1) return pts.first.$2;
  for (var i = 1; i < pts.length; i++) {
    if (strength <= pts[i].$1) {
      final (x0, y0) = pts[i - 1];
      final (x1, y1) = pts[i];
      return y0 + (y1 - y0) * (strength - x0) / (x1 - x0);
    }
  }
  return pts.last.$2;
}

/// 어종별 제철(월). 이 세 어종은 계절을 크게 타서, 조류·바람이 아무리 좋아도
/// 철이 아니면 잘 안 나온다. 값은 그 달의 가중치다.
///
/// **12개월을 빠짐없이 채운다.** 예전엔 성수기 몇 달만 적고 나머지는 기본값
/// 0.25로 떨어뜨렸는데, 그러면 비수기에 물때가 아무리 좋아도 무조건 "매우나쁨"
/// 한 칸으로 눌려 **물때 차이가 화면에서 사라졌다**(8월 갑오징어가 조금이든
/// 사리든 전부 매우나쁨으로 보이던 원인).
///
/// 그래서 비수기 하한을 [_seasonFloor] 근처로 둔다 — 비수기라는 사실은 등급을
/// 확실히 낮추되, 그 안에서 조금/사리 차이는 여전히 드러나게 한다.
///
/// **[_peakSeason]과 [_shoulderSeason]이 화면의 등급 분포를 정한다.** 성수기
/// (1.0)엔 15개 물때가 매우좋음 2 / 좋음 4 / 보통 6 / 나쁨 3으로 갈리고,
/// 성수기 다음 단계(0.85)에선 좋음 한 쌍이 보통으로 내려가 매우좋음 2 / 좋음 2
/// / 보통 8 / 나쁨 3이 된다. 값을 바꾸면 `tool/verify_jigging.dart`로 분포를
/// 다시 확인한다.
const _season = <String, Map<int, double>>{
  // 9월(금어기 해제 직후)이 최고, 10·11월이 그다음.
  '쭈꾸미': {
    1: 0.40,
    2: 0.40,
    3: 0.40,
    4: 0.40,
    5: 0.40,
    6: 0.40,
    7: 0.40,
    8: 0.45,
    9: _peakSeason,
    10: _shoulderSeason,
    11: _shoulderSeason,
    12: 0.50,
  },
  // 쭈꾸미와 같은 배에서 같은 시기에 난다. 봄엔 산란기 큰 개체(왕갑오)가
  // 붙어 가을만큼은 아니어도 조금 올라간다.
  '갑오징어': {
    1: 0.50,
    2: 0.45,
    3: 0.45,
    4: 0.55,
    5: 0.60,
    6: 0.55,
    7: 0.40,
    8: 0.50,
    9: _peakSeason,
    10: _shoulderSeason,
    11: _shoulderSeason,
    12: 0.55,
  },
  // 가을이 가장 좋고 봄에도 한 번 더 붙는다.
  '문어': {
    1: 0.55,
    2: 0.60,
    3: 0.75,
    4: _shoulderSeason,
    5: 0.80,
    6: 0.60,
    7: 0.45,
    8: 0.45,
    9: _peakSeason,
    10: _shoulderSeason,
    11: _shoulderSeason,
    12: 0.60,
  },
};

/// 성수기(9월) 가중치. [_tideCurve]와 등급 문턱이 이 값을 기준으로 맞춰져 있어
/// 15개 물때가 매우좋음 2 / 좋음 4 / 보통 6 / 나쁨 3으로 갈린다.
const double _peakSeason = 1.0;

/// 성수기 다음 단계(10·11월 등) 가중치. 좋음 한 쌍이 보통으로 내려가
/// 매우좋음 2 / 좋음 2 / 보통 8 / 나쁨 3이 된다.
const double _shoulderSeason = 0.85;

/// 제철 가중치의 하한. 달 정보가 없거나 표에 빠진 달에도 이 값을 쓴다.
const double _seasonFloor = 0.40;

/// 그날 조위 변화폭을 **절대 기준**(대조기 조차 약 800cm)으로 정규화한 값.
///
/// 물때 화면의 "조류세기" 막대가 쓰는 값이라 표시용으로는 유지하지만,
/// **추정 지수에는 쓰지 않는다**([relativeTideStrength] 참고).
double tideStrengthFraction(List<double> hourlyHeightsCm) {
  if (hourlyHeightsCm.isEmpty) return 0;
  return (dailyTideRangeCm(hourlyHeightsCm) / 800).clamp(0.0, 1.0);
}

/// 하루 조위 변화폭(최고−최저, cm).
double dailyTideRangeCm(List<double> hourlyHeightsCm) {
  if (hourlyHeightsCm.isEmpty) return 0;
  final maxV = hourlyHeightsCm.reduce(math.max);
  final minV = hourlyHeightsCm.reduce(math.min);
  return maxV - minV;
}

/// 사리(1) ↔ 조금(0) 위상. 물때 인덱스만으로 정해지므로 지점과 무관하다.
///
/// 7물때식은 7물(index 6), 8물때식은 8물(index 7)이 사리 한가운데다
/// ([MulTtae.isSari]와 같은 기준). 거기서 물때가 멀어질수록 코사인 모양으로
/// 0까지 내려가 조금·무시에서 바닥이 된다.
double springNeapPhase(MulTtae mulTtae) {
  final center = switch (mulTtae.system) {
    MulTtaeSystem.west7 => 6, // 7물
    MulTtaeSystem.south8 => 7, // 8물
  };
  var d = (mulTtae.index - center).abs().toDouble();
  if (d > 7.5) d = 15 - d; // 15단계 순환
  return 0.5 * (1 + math.cos(math.pi * d / 7.5));
}

/// 추정 지수가 쓰는 **지점 상대 조류 세기**(0~1). 그 지점의 조금이 0,
/// 사리가 1에 가깝다.
///
/// 예전엔 [tideStrengthFraction](조차 ÷ 800cm)을 그대로 썼는데, 이건 지점이
/// 아니라 **바다 전체를 한 자로 재는 절대값**이라 실제와 어긋났다. 무창포는
/// 가장 물이 죽는 조금에도 조차가 376cm(=0.47)라 "물이 센 날"로 읽혔고,
/// 통영은 사리에도 270cm(=0.34)라 "물이 느린 날"로 읽혔다. 그래서 서해에서는
/// 조금이든 사리든 전부 최적을 넘겨 **거의 모든 날이 매우나쁨**으로 나왔다
/// (사용자 제보: 무창포 8/20 조금인데 쭈꾸미·갑오징어 매우나쁨).
///
/// 낚시에서 중요한 건 "오늘 물이 그 자리 기준으로 센가"이므로, 물때
/// 위상([springNeapPhase])을 축으로 삼는다. 다만 동해처럼 조차가 원래 거의
/// 없는 곳은 사리여도 물이 안 가므로, 그날 조차와 위상으로 **그 지점의 사리
/// 조차를 역산해** 세기의 상한을 낮춘다.
double relativeTideStrength({
  required MulTtae mulTtae,
  required double dayRangeCm,
}) {
  final phase = springNeapPhase(mulTtae);
  // 우리나라 연안의 조금 조차는 대체로 사리의 40~50% 수준이다.
  final springRangeCm = dayRangeCm / (0.45 + 0.55 * phase);
  // 사리 조차 450cm 이상이면 상한 그대로, 작을수록 세기 상한을 낮춘다.
  // **하한 0.65는 일부러 높게 잡았다** — 더 낮추면 조차가 작은 동해·남해
  // 일부에서 세기 상한이 최적 근처에 박혀 15개 물때가 전부 같은 등급으로
  // 눌린다(검증 스크립트가 잡아낸 문제. 절대값 방식의 반대 방향 실패다).
  // 그래서 이 보정은 "동해 사리는 서해 사리만큼 세지 않다" 정도로만 약하게
  // 작용하고, 물때에 따른 변화는 어디서나 그대로 남는다.
  final scale = (springRangeCm / 450).clamp(0.65, 1.0);
  return (phase * scale).clamp(0.0, 1.0);
}

/// 바람·파고가 만드는 감점(0~1). 셋 다 배·연안에서 채비를 세워 하는 낚시라
/// 바람이 세면 조류 선호와 무관하게 조과가 떨어진다.
///
/// **값이 없는 항목은 감점하지 않는다.** 예보 범위 밖 날짜(2주 뒤 등)에는
/// 바람·파고가 아예 없는데, 예전엔 호출부에서 `?? 0`으로 채워 넘겼다. 지금
/// 값은 0으로 읽혀 우연히 감점이 없었지만, 실수로 다른 기본값을 넣으면 조용히
/// 엉뚱한 감점이 생긴다. 아예 null을 받아 **명시적으로 무시**한다.
double _weatherFactor(double? windMs, double? gustMs, double? waveM) {
  // 4m/s까지는 감점 없음, 12m/s에서 바닥.
  double drop(double v, double from, double to) =>
      ((v - from) / (to - from)).clamp(0.0, 1.0);
  final byWind = windMs == null ? 1.0 : 1 - 0.75 * drop(windMs, 4, 12);
  final byGust = gustMs == null ? 1.0 : 1 - 0.45 * drop(gustMs, 9, 18);
  final byWave = waveM == null ? 1.0 : 1 - 0.60 * drop(waveM, 0.8, 2.5);
  return (byWind * byGust * byWave).clamp(0.05, 1.0);
}

/// 어종·조건으로 추정 점수(0~1)를 낸다. 등급이 필요하면
/// [estimateJiggingGrade]를 쓴다.
///
/// [tideStrength]는 [relativeTideStrength]가 내는 지점 상대 세기다.
/// [windMs]·[gustMs]·[waveM]은 **모르면 null**로 넘긴다 — 그 항목은 감점에서
/// 빠지고, 셋 다 null이면 순전히 물때·제철로만 판단한다.
double estimateJiggingScore({
  required String species,
  required double tideStrength,
  double? windMs,
  double? gustMs,
  double? waveM,
  required int month,
}) {
  final byTide = _tideFactor(species, tideStrength);
  if (byTide == null) return 0;

  final bySeason = _season[species]?[month] ?? _seasonFloor;
  final byWeather = _weatherFactor(windMs, gustMs, waveM);

  return (byTide * bySeason * byWeather).clamp(0.0, 1.0);
}

/// 추정 점수를 화면에 쓰는 5단계 등급으로 바꾼다.
FishingGrade estimateJiggingGrade({
  required String species,
  required double tideStrength,
  double? windMs,
  double? gustMs,
  double? waveM,
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
  // 문턱은 [_tideCurve]·[_peakSeason]과 한 벌이다 — 성수기 15개 물때가
  // 매우좋음 2 / 좋음 4 / 보통 6 / 나쁨 3으로 갈리도록 맞춰 놨다.
  // "매우나쁨"(0.08 미만)은 성수기엔 아예 안 나오고, 비수기의 가장 센 물때나
  // 강풍·높은 파고에서만 닿는다.
  if (score >= 0.68) return FishingGrade.veryGood;
  if (score >= 0.48) return FishingGrade.good;
  if (score >= 0.28) return FishingGrade.normal;
  if (score >= 0.08) return FishingGrade.bad;
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

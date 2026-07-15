/// 물때 계산 유틸.
///
/// 해역별로 물때 셈법이 다르다:
/// - **서해(7물때식)**: 음력 1일 = 7물. 1물~13물 + 조금 + 무시(15단계).
///   음력 10일·25일 = 1물, 8일·23일 = 조금, 9일·24일 = 무시.
/// - **남해·동해·제주(8물때식)**: 음력 1일 = 8물. 1물~14물 + 조금(15단계).
///   음력 9일·24일 = 1물, 8일·23일 = 조금.
///
/// 음력 날짜는 알려진 신월(합삭) 시각으로부터 삭망월 주기로 근사한다.
/// 오차는 ±1일 수준으로, 이 근사는 **오늘로부터 2년 이내** 날짜에 대해
/// 단순 물때 제공 용도로 사용한다 ([maxSimpleMulTtaeRange]).
/// 추후 KHOA API의 음력/물때 정보로 교체할 수 있도록 분리해 두었다.
library;

/// 삭망월(신월→신월) 평균 주기 (일).
const double synodicMonthDays = 29.530588853;

/// 단순 물때(근사 음력 기반) 제공 범위: 오늘부터 2년.
const Duration maxSimpleMulTtaeRange = Duration(days: 365 * 2);

/// 조석(만조/간조·조위) 예보 제공 범위: 오늘부터 1년.
const Duration maxTideForecastRange = Duration(days: 365);

/// 기준 신월: 2000-01-06 18:14 UTC.
final DateTime _epochNewMoon = DateTime.utc(2000, 1, 6, 18, 14);

/// 해역별 물때 셈법.
enum MulTtaeSystem {
  /// 서해 7물때식: 음력 1일 = 7물.
  west7,

  /// 남해·동해·제주 8물때식: 음력 1일 = 8물.
  south8,
}

/// 7물때식 이름표. 인덱스 0 = 1물(음력 10일), 13 = 조금, 14 = 무시.
const List<String> mulTtaeLabelsWest7 = [
  '1물',
  '2물',
  '3물',
  '4물',
  '5물',
  '6물',
  '7물',
  '8물',
  '9물',
  '10물',
  '11물',
  '12물',
  '13물',
  '조금',
  '무시',
];

/// 8물때식 이름표. 인덱스 0 = 1물(음력 9일), 14 = 조금.
const List<String> mulTtaeLabelsSouth8 = [
  '1물',
  '2물',
  '3물',
  '4물',
  '5물',
  '6물',
  '7물',
  '8물',
  '9물',
  '10물',
  '11물',
  '12물',
  '13물',
  '14물',
  '조금',
];

/// 지역(해역) 이름 → 물때식. 서해만 7물때식, 나머지는 8물때식.
MulTtaeSystem mulTtaeSystemForRegion(String region) =>
    region == '서해' ? MulTtaeSystem.west7 : MulTtaeSystem.south8;

class MulTtae {
  const MulTtae({
    required this.index,
    required this.lunarDay,
    required this.system,
  });

  /// 0~14. 각 물때식 이름표의 인덱스.
  final int index;

  /// 근사 음력 일자 (1~30).
  final int lunarDay;

  final MulTtaeSystem system;

  String get label => switch (system) {
    MulTtaeSystem.west7 => mulTtaeLabelsWest7[index],
    MulTtaeSystem.south8 => mulTtaeLabelsSouth8[index],
  };

  /// 사리(대조기, 조차 최대) 부근 여부.
  bool get isSari => switch (system) {
    MulTtaeSystem.west7 => index >= 5 && index <= 7, // 6물~8물
    MulTtaeSystem.south8 => index >= 6 && index <= 8, // 7물~9물
  };

  /// 조금(소조기, 조차 최소) 부근 여부.
  bool get isJogeum => index >= 12;
}

/// 신월 이후 경과일(월령, 0 이상 [synodicMonthDays] 미만)을 연속값으로 구한다.
double lunarAgeDays(DateTime date) {
  final minutes = date.toUtc().difference(_epochNewMoon).inMinutes;
  final days = minutes / (24 * 60);
  final phase = days % synodicMonthDays;
  return phase < 0 ? phase + synodicMonthDays : phase;
}

/// [date]의 근사 음력 일자(1~30)를 구한다.
int approximateLunarDay(DateTime date) => lunarAgeDays(date).floor() + 1;

/// 음력 일자(1~30)에 대한 물때.
MulTtae mulTtaeForLunarDay(
  int lunarDay, {
  MulTtaeSystem system = MulTtaeSystem.west7,
}) {
  assert(lunarDay >= 1 && lunarDay <= 30);
  // 1물의 기준 음력 일자: 7물때식 = 10일, 8물때식 = 9일.
  final firstMulLunarDay = switch (system) {
    MulTtaeSystem.west7 => 10,
    MulTtaeSystem.south8 => 9,
  };
  final index = ((lunarDay - firstMulLunarDay) % 15 + 15) % 15;
  return MulTtae(index: index, lunarDay: lunarDay, system: system);
}

/// [date]의 물때.
MulTtae mulTtaeFor(
  DateTime date, {
  MulTtaeSystem system = MulTtaeSystem.west7,
}) => mulTtaeForLunarDay(approximateLunarDay(date), system: system);

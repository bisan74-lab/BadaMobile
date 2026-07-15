/// 물때(1물~13물, 조금, 무시) 계산 유틸.
///
/// 서해안에서 널리 쓰이는 7물때식을 기준으로 한다:
///   음력 10일·25일 = 1물, 음력 8일·23일 = 조금, 음력 9일·24일 = 무시,
///   음력 1일·16일 = 7물(사리 부근).
///
/// 음력 날짜는 알려진 신월(합삭) 시각으로부터 삭망월 주기로 근사한다.
/// 오차는 ±1일 수준으로 초기 버전에는 충분하며, 추후 KHOA API의
/// 음력/물때 정보로 교체할 수 있도록 분리해 두었다.
library;

/// 삭망월(신월→신월) 평균 주기 (일).
const double synodicMonthDays = 29.530588853;

/// 기준 신월: 2000-01-06 18:14 UTC.
final DateTime _epochNewMoon = DateTime.utc(2000, 1, 6, 18, 14);

/// 7물때식 이름표. 인덱스 0 = 1물, 12 = 13물, 13 = 조금, 14 = 무시.
const List<String> mulTtaeLabels = [
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

class MulTtae {
  const MulTtae({required this.index, required this.lunarDay});

  /// 0~14. [mulTtaeLabels] 인덱스.
  final int index;

  /// 근사 음력 일자 (1~30).
  final int lunarDay;

  String get label => mulTtaeLabels[index];

  /// 사리(대조기, 조차 최대) 부근 여부 — 6물~8물.
  bool get isSari => index >= 5 && index <= 7;

  /// 조금(소조기, 조차 최소) 부근 여부 — 13물·조금·무시.
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

/// 음력 일자(1~30)에 대한 7물때식 물때.
MulTtae mulTtaeForLunarDay(int lunarDay) {
  assert(lunarDay >= 1 && lunarDay <= 30);
  final index = ((lunarDay - 10) % 15 + 15) % 15;
  return MulTtae(index: index, lunarDay: lunarDay);
}

/// [date]의 물때 (7물때식).
MulTtae mulTtaeFor(DateTime date) =>
    mulTtaeForLunarDay(approximateLunarDay(date));

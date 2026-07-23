/// 물때 계산 유틸.
///
/// 해역별로 물때 셈법이 다르다:
/// - **서해(7물때식)**: 음력 1일 = 7물. 1물~13물 + 조금 + 무시(15단계).
///   음력 10일·25일 = 1물, 8일·23일 = 조금, 9일·24일 = 무시.
/// - **남해·동해·제주(8물때식)**: 음력 1일 = 8물. 1물~14물 + 조금(15단계).
///   음력 9일·24일 = 1물, 8일·23일 = 조금.
///
/// 음력 날짜는 **천문 신월(합삭) 시각을 Meeus 알고리즘(주기항 포함)으로 직접
/// 계산**해 KST 달력일 기준으로 매긴다(음력 1일 = 신월이 든 KST 날짜). 예전엔
/// 평균 삭망월만으로 근사했는데, 달의 궤도가 타원이라 실제 신월이 평균에서
/// ±0.5일 넘게 벗어나는 달이 있어 날짜 경계를 넘으면 음력일이 1~2일 어긋났다
/// (녹동항 2026-07-24: 음력 9일·1물로 잘못 표기 → 실제 음력 11일·3물). Meeus
/// 신월은 오차가 분 단위라 물때가 실제 물때표와 일치한다.
library;

import 'dart:math' as math;

/// 삭망월(신월→신월) 평균 주기 (일).
const double synodicMonthDays = 29.530588853;

/// 단순 물때(근사 음력 기반) 제공 범위: 오늘부터 2년.
const Duration maxSimpleMulTtaeRange = Duration(days: 365 * 2);

/// 조석(만조/간조·조위) 예보 제공 범위: 오늘부터 1년.
const Duration maxTideForecastRange = Duration(days: 365);

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

/// 신월 이후 경과일(월령, 0 이상 [synodicMonthDays] 미만)을 **천문 신월 기준**
/// 연속값으로 구한다. 만조 진폭의 사리/조금 변조 등 연속 위상이 필요한 곳에서
/// 쓴다.
double lunarAgeDays(DateTime date) {
  final utc = date.toUtc();
  final prev = _newMoonOnOrBefore(utc);
  final age = utc.difference(prev).inSeconds / 86400.0;
  // 수치 경계로 음수/주기 초과가 나오면 정규화.
  if (age < 0) return 0;
  if (age >= synodicMonthDays) return age % synodicMonthDays;
  return age;
}

/// [date]의 음력 일자(1~30)를 구한다. **KST 달력일 기준**: 신월(합삭)이 든
/// KST 날짜가 음력 1일이고, 이후 KST 자정마다 하루씩 증가한다.
int approximateLunarDay(DateTime date) {
  const kst = Duration(hours: 9);
  final utc = date.toUtc();
  // 이 시각이 속한 음력월을 시작시킨 신월(그 신월의 KST 날짜 ≤ 대상 KST 날짜
  // 중 가장 최근)을 찾는다. 신월이 KST 늦은 밤이면 같은 달력일의 이른 시각이
  // 신월보다 앞서므로, 순간이 아니라 **KST 달력일**로 비교해야 정확하다.
  final targetKstDay = _floorToDayUtc(utc.add(kst));
  var nm = _newMoonOnOrBefore(utc);
  var nmKstDay = _floorToDayUtc(nm.add(kst));
  // 신월이 대상과 같은 날 늦게 뜨는 경우 순간 비교로는 직전 삭을 잡으므로
  // 다음 신월의 KST 날짜가 아직 대상일 이하이면 그쪽으로 당긴다.
  final nextNm = _newMoonOnOrBefore(nm.add(const Duration(days: 40)));
  final nextKstDay = _floorToDayUtc(nextNm.add(kst));
  if (!nextKstDay.isAfter(targetKstDay) && nextKstDay.isAfter(nmKstDay)) {
    nm = nextNm;
    nmKstDay = nextKstDay;
  }
  final day = targetKstDay.difference(nmKstDay).inDays + 1;
  // 음력월은 29~30일이라 정상 범위 안. 방어적으로 1~30로 clamp.
  return day.clamp(1, 30);
}

DateTime _floorToDayUtc(DateTime t) => DateTime.utc(t.year, t.month, t.day);

/// [instant](UTC) 시각 **이전(포함) 가장 최근 신월(합삭)**의 UTC 시각.
/// Meeus 「Astronomical Algorithms」 49장의 삭·망 시각 공식(E·M·M'·F 주기항)을
/// 사용한다. 오차는 분 단위.
DateTime _newMoonOnOrBefore(DateTime instant) {
  final approxK = _kForInstant(instant);
  // approxK가 대상보다 뒤일 수 있으니 앞뒤로 훑어 대상 이하 중 가장 큰 신월.
  DateTime? best;
  for (var k = approxK + 1; k >= approxK - 2; k--) {
    final nm = _newMoonForK(k);
    if (!nm.isAfter(instant)) {
      best = nm;
      break;
    }
  }
  return best ?? _newMoonForK(approxK - 2);
}

/// 대략적인 삭 주기 번호 k(2000년 기준). 정확한 선택은 호출부에서 보정한다.
int _kForInstant(DateTime instant) {
  final year =
      instant.year +
      (instant.difference(DateTime.utc(instant.year)).inDays) / 365.25;
  return ((year - 2000) * 12.3685).round();
}

/// 삭 주기 번호 [k]의 신월(합삭) UTC 시각(Meeus 49장).
DateTime _newMoonForK(int k) {
  final t = k / 1236.85;
  final t2 = t * t, t3 = t2 * t, t4 = t3 * t;
  var jde =
      2451550.09766 +
      29.530588861 * k +
      0.00015437 * t2 -
      0.000000150 * t3 +
      0.00000000073 * t4;
  final e = 1 - 0.002516 * t - 0.0000074 * t2;
  double rad(double deg) => deg * math.pi / 180.0;
  final m = rad(2.5534 + 29.10535670 * k - 0.0000014 * t2 - 0.00000011 * t3);
  final mp = rad(
    201.5643 +
        385.81693528 * k +
        0.0107582 * t2 +
        0.00001238 * t3 -
        0.000000058 * t4,
  );
  final f = rad(
    160.7108 +
        390.67050284 * k -
        0.0016118 * t2 -
        0.00000227 * t3 +
        0.000000011 * t4,
  );
  final om = rad(124.7746 - 1.56375588 * k + 0.0020672 * t2 + 0.00000215 * t3);
  final s = math.sin;
  jde +=
      -0.40720 * s(mp) +
      0.17241 * e * s(m) +
      0.01608 * s(2 * mp) +
      0.01039 * s(2 * f) +
      0.00739 * e * s(mp - m) -
      0.00514 * e * s(mp + m) +
      0.00208 * e * e * s(2 * m) -
      0.00111 * s(mp - 2 * f) -
      0.00057 * s(mp + 2 * f) +
      0.00056 * e * s(2 * mp + m) -
      0.00042 * s(3 * mp) +
      0.00042 * e * s(m + 2 * f) +
      0.00038 * e * s(m - 2 * f) -
      0.00024 * e * s(2 * mp - m) -
      0.00017 * s(om) -
      0.00007 * s(mp + 2 * m) +
      0.00004 * s(2 * mp - 2 * f) +
      0.00004 * s(3 * m) +
      0.00003 * s(mp + m - 2 * f) +
      0.00003 * s(2 * mp + 2 * f) -
      0.00003 * s(mp + m + 2 * f) +
      0.00003 * s(mp - m + 2 * f) -
      0.00002 * s(mp - m - 2 * f) -
      0.00002 * s(3 * mp + m) +
      0.00002 * s(4 * mp);
  final a1 = rad(299.77 + 0.107408 * k - 0.009173 * t2);
  jde += 0.000325 * s(a1);
  return _julianDayToUtc(jde);
}

/// 율리우스일(JDE, TT ≈ UTC 근사)을 UTC [DateTime]으로 변환한다.
DateTime _julianDayToUtc(double jd) {
  final z0 = jd + 0.5;
  final z = z0.floor();
  final frac = z0 - z;
  int a;
  if (z < 2299161) {
    a = z;
  } else {
    final alpha = ((z - 1867216.25) / 36524.25).floor();
    a = z + 1 + alpha - (alpha / 4).floor();
  }
  final b = a + 1524;
  final c = ((b - 122.1) / 365.25).floor();
  final d = (365.25 * c).floor();
  final ei = ((b - d) / 30.6001).floor();
  final dayWithFrac = b - d - (30.6001 * ei).floor() + frac;
  final day = dayWithFrac.floor();
  final month = ei < 14 ? ei - 1 : ei - 13;
  final year = month > 2 ? c - 4716 : c - 4715;
  final secondsOfDay = ((dayWithFrac - day) * 86400).round();
  return DateTime.utc(year, month, day).add(Duration(seconds: secondsOfDay));
}

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

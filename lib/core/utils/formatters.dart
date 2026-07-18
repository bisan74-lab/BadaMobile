import 'package:intl/intl.dart';

final _hm = DateFormat('HH:mm');

const _weekdaysKo = ['월', '화', '수', '목', '금', '토', '일'];

String formatHm(DateTime t) => _hm.format(t);

/// 요일 한 글자 (월/화/수/목/금/토/일).
String weekdayKo(DateTime t) => _weekdaysKo[t.weekday - 1];

/// 예: "7월 15일 (수)". intl 로케일 초기화 없이 동작하도록 직접 조합한다.
String formatMonthDay(DateTime t) =>
    '${t.month}월 ${t.day}일 (${_weekdaysKo[t.weekday - 1]})';

/// 풍향(도, 바람이 불어오는 방향)을 16방위 한글 표기로 변환한다.
String compassKo(double degrees) {
  const dirs = [
    '북',
    '북북동',
    '북동',
    '동북동',
    '동',
    '동남동',
    '남동',
    '남남동',
    '남',
    '남남서',
    '남서',
    '서남서',
    '서',
    '서북서',
    '북서',
    '북북서',
  ];
  final normalized = ((degrees % 360) + 360) % 360;
  final idx = ((normalized + 11.25) / 22.5).floor() % 16;
  return dirs[idx];
}

/// m/s 풍속을 소수 1자리 문자열로.
String formatWind(double ms) => '${ms.toStringAsFixed(1)}m/s';

/// 파고(m)를 소수 1자리 문자열로.
String formatWave(double m) => '${m.toStringAsFixed(1)}m';

/// 파주기(초)를 문자열로.
String formatPeriod(double s) => '${s.toStringAsFixed(1)}s';

/// 조위(cm)를 정수 문자열로.
String formatTideHeight(double cm) => '${cm.round()}cm';

/// 파력(kW/m)을 보기 좋은 문자열로 (10 미만은 소수 1자리, 이상은 정수).
String formatWavePower(double kw) =>
    kw < 10 ? kw.toStringAsFixed(1) : kw.round().toString();

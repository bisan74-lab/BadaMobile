/// 한국 표준시(KST, UTC+9 — 서머타임 없음) 유틸.
///
/// Open-Meteo에는 `timezone=Asia/Seoul`로 요청하므로 응답의 시간 문자열은
/// 오프셋 없는 서울 벽시계 시각이고, `DateTime.parse`는 그 성분을 그대로
/// 읽는다. 이런 시각들과 비교·동기화하는 "지금"은 기기 시간대 설정이 아니라
/// 서울 기준이어야 하므로, UTC에 9시간을 직접 더해 기기 설정과 무관하게
/// 서울 시각을 만든다. 한국 시간대로 설정된 기기에서는 `DateTime.now()`와
/// 동일한 값이다(해외 로밍·시간대 설정 오류 등에서만 달라진다).
library;

/// 지금 시각(서울 벽시계). API 응답 시각(`DateTime.parse` 결과)과 같은
/// 로컬 플래그로 만들어 서로 안전하게 비교된다.
DateTime nowKst() {
  final u = DateTime.now().toUtc().add(const Duration(hours: 9));
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second);
}

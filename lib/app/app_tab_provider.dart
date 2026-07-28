import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 현재 선택된 하단 탭 인덱스(물때&날씨0 / Windy1 / 설정2).
///
/// 보통은 하단 라벨 내비게이션 바가 이 값을 바꾼다. 다만 Windy(1) 탭은
/// 몰입형 지도라 하단 바를 숨기고, 그 탭 안의 오른쪽 아이콘 내비게이션이
/// 이 값을 바꿔 다른 탭으로 이동한다. 값을 공유 provider로 둬서 탭 안 위젯이
/// 앱 셸의 탭을 바꿀 수 있게 한다.
///
/// 낚시정보(구 홈)·날씨 화면은 탭이 아니라 물때&날씨 화면의 오른쪽 메뉴에서
/// 푸시로 연다.
final appTabIndexProvider = StateProvider<int>((ref) => 0);

/// Windy(몰입형 지도) 탭의 인덱스.
const int windyTabIndex = 1;

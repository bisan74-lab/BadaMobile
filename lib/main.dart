import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/config/env.dart';
import 'core/storage/prefs.dart';
import 'core/widgets/ad_placeholder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // **세로 고정**(사용자 요구, 2026-08-06). 가로로 돌리면 물때표·상세예보
  // 표·오른쪽 세로 메뉴가 전부 다른 배치를 필요로 해서 제약이 너무 많아진다.
  //
  // 실제로 막는 건 플랫폼 설정이다(`AndroidManifest.xml`의
  // `android:screenOrientation`, iOS `Info.plist`의
  // `UISupportedInterfaceOrientations`) — 그쪽이라야 **앱이 켜지는 순간
  // 가로로 한 프레임 그려지는 것**까지 막힌다. 여기 있는 건 그 둘이 빠졌을
  // 때를 받치는 안전망이고, **셋을 함께 바꿔야** 한쪽만 돌아가지 않는다.
  // 첫 프레임을 늦추지 않으려고 기다리지 않는다.
  unawaited(
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  );
  // **광고 초기화를 기다리지 않는다.** 예전엔 여기서 await해서, 광고 SDK가
  // 굼뜬 기기에서는 최대 3초 동안 첫 프레임조차 안 나왔다. 초기화는 띄워만
  // 두고(`adsReady`) 화면을 먼저 올린다 — 배너 자리가 알아서 기다렸다 붙는다.
  adsReady = _initAds();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const BadaMobileApp(),
    ),
  );
}

/// 광고 SDK를 초기화하고, 성공했을 때만 배너 로드를 허용한다.
///
/// 광고는 부가 기능이라 초기화가 실패하거나 느려도 앱 실행을 막지 않는다:
/// 화면과 **병렬로** 돌고, 3초 안에 안 끝나면 그냥 포기한다(광고 자리는 앱
/// 소개 박스로 남는다). 광고 ID를 빈 값으로 주입한 빌드는 SDK를 아예 건드리지
/// 않는다.
Future<void> _initAds() async {
  if (Env.admobBannerAdUnitId.isEmpty) return;
  try {
    await MobileAds.instance.initialize().timeout(const Duration(seconds: 3));
    adsRuntimeEnabled = true;
  } catch (_) {
    adsRuntimeEnabled = false;
  }
}

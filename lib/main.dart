import 'package:flutter/material.dart';
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

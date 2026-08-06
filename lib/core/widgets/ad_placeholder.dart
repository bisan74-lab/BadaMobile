import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/env.dart';

/// 실제 광고를 로드해도 되는 상태인지. **[main]에서 광고 SDK 초기화에 성공한
/// 뒤에만 true로 켠다.** 기본값이 false라 위젯 테스트는 광고 플랫폼 채널을
/// 아예 건드리지 않고, 화면에는 아래 앱 소개 박스가 그대로 나온다.
bool adsRuntimeEnabled = false;

/// 광고 SDK 초기화가 끝나기를 기다리는 Future. `main()`이 채운다.
///
/// 예전엔 `main()`이 초기화를 **await한 뒤에야** `runApp`을 불렀다 — 광고는
/// 부가 기능인데도 최대 3초 동안 첫 프레임조차 안 그려졌다. 지금은 초기화를
/// 띄워만 두고 바로 화면을 올리고, 배너 자리가 이 Future를 기다렸다가
/// 준비되면 그때 로드한다.
///
/// 테스트에서는 null이라 광고 플랫폼 채널을 아예 건드리지 않는다.
Future<void>? adsReady;

/// 배너가 붙는 자리. 자리마다 광고 단위를 따로 두면 AdMob 리포트에서 어느
/// 화면이 얼마나 버는지 나눠 볼 수 있다.
enum AdSlot {
  /// 물때 화면 하단.
  tide,

  /// 설정 화면 하단.
  settings;

  String get adUnitId => switch (this) {
    AdSlot.tide => Env.admobBannerAdUnitId,
    AdSlot.settings => Env.admobSettingsBannerAdUnitId,
  };
}

/// 하단 광고 자리. 물때&날씨 화면과 설정 화면이 같은 위젯을 공유한다.
///
/// 배너가 실제로 로드되면 배너를, 그렇지 않으면(광고 비활성·로드 실패·
/// 오프라인) **같은 높이의 앱 소개 박스**를 보여준다. 광고가 없거나 실패해도
/// 레이아웃이 흔들리지 않고 빈 칸도 남지 않는다.
class AdPlaceholder extends StatefulWidget {
  const AdPlaceholder({super.key, required this.slot});

  final AdSlot slot;

  /// 배너(320×50)와 기존 소개 박스가 공유하는 높이.
  static const double height = 56;

  @override
  State<AdPlaceholder> createState() => _AdPlaceholderState();
}

class _AdPlaceholderState extends State<AdPlaceholder> {
  BannerAd? _banner;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (adsRuntimeEnabled) {
      _loadBanner();
    } else {
      // 아직 SDK 초기화가 안 끝났을 수 있다(첫 화면을 막지 않으려고 병렬로
      // 돌린다). 끝나면 그때 로드하고, 끝내 실패하면 소개 박스로 남는다.
      adsReady?.then((_) {
        if (mounted && adsRuntimeEnabled) _loadBanner();
      });
    }
  }

  void _loadBanner() {
    final adUnitId = widget.slot.adUnitId;
    if (!adsRuntimeEnabled || adUnitId.isEmpty) return;
    final banner = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          // 로드 실패(노출 재고 없음·오프라인 등)는 정상 상황이다. 배너를
          // 정리하고 소개 박스로 남는다.
          ad.dispose();
          if (mounted) setState(() => _banner = null);
        },
      ),
    );
    _banner = banner;
    // 광고는 부가 기능이므로, 어떤 이유로든 로드 호출이 실패해도 앱이
    // 죽지 않고 소개 박스로 넘어가게 한다.
    try {
      banner.load();
    } catch (_) {
      _banner = null;
    }
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = _banner;
    if (_loaded && banner != null) {
      return SizedBox(
        height: AdPlaceholder.height,
        child: Center(
          child: SizedBox(
            width: banner.size.width.toDouble(),
            height: banner.size.height.toDouble(),
            child: AdWidget(ad: banner),
          ),
        ),
      );
    }
    return const _AppIntroBox();
  }
}

/// 광고가 없을 때 같은 자리를 채우는 앱 소개 박스.
class _AppIntroBox extends StatelessWidget {
  const _AppIntroBox();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // **이 박스만 글자 배율에 상한을 둔다.** 높이가 배너 광고 규격
    // ([AdPlaceholder.height])에 묶여 있어 늘릴 수 없는데, 시스템 글자 크기를
    // 키우면 안의 두 줄이 그대로 넘친다. 광고 자리를 메우는 장식이라 여기서만
    // 배율을 제한하는 것이 맞다 — **본문 화면에는 이 방식을 쓰지 말 것**
    // (사용자의 접근성 설정을 무시하게 된다).
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: _box(context, scheme),
    );
  }

  Widget _box(BuildContext context, ColorScheme scheme) {
    return Container(
      height: AdPlaceholder.height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/icon/app_icon.png',
              width: 36,
              height: 36,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.waves, size: 32, color: scheme.primary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '바다윈디',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  '물때·날씨·바람을 한눈에 보는 낚시 도우미',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

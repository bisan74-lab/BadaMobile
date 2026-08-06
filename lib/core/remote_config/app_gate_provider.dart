import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/cache_store.dart';
import 'app_gate_config.dart';
import 'app_gate_repository.dart';

final appGateRepositoryProvider = Provider<AppGateRepository>(
  (ref) => AppGateRepository(),
);

/// 앱 시작 시 적용하는 강제 업데이트 게이트 상태.
///
/// **기다리지 않는다.** 예전엔 `FutureProvider`라서 설정을 받아올 때까지
/// 화면 전체가 스피너 하나였고, 그동안 어떤 화면도 만들어지지 않아 **조석
/// 요청조차 나가지 않았다** — 게이트 시간(최대 5초)이 데이터 시간에 그대로
/// 더해졌다(`test/perf/perf_startup_test.dart`가 이 순서를 쟀다).
///
/// 지금은 이렇게 동작한다.
/// - 지난 실행에서 저장해 둔 설정이 있으면 **그것을 즉시 적용**한다(대기 0).
///   막아야 할 기기는 켜자마자 안내 화면이 뜨고, 아닌 기기는 바로 앱이 뜬다.
///   새 설정은 백그라운드로 받아 **캐시에만** 저장한다 — 쓰던 도중에 화면이
///   안내 화면으로 바뀌지 않고, 다음 실행부터 반영된다.
/// - 캐시가 아예 없는 **설치 후 첫 실행**만, 앱을 먼저 띄우고 응답이 오면
///   그때 판단한다. 그 시점의 앱은 방금 스토어에서 받은 최신 버전이라
///   막을 것이 없다.
///
/// 설정을 확인하지 못하면(오프라인 등) 캐시에 손대지 않는다. 실패를
/// `disabled`로 저장해 버리면 막아야 할 기기가 풀린다.
class AppGateNotifier extends Notifier<AppGateConfig> {
  var _disposed = false;

  @override
  AppGateConfig build() {
    ref.onDispose(() => _disposed = true);
    final repo = ref.watch(appGateRepositoryProvider);
    final cache = ref.watch(cacheStoreProvider);
    final cached = repo.readCached(cache);
    unawaited(_refresh(repo, cache, applyNow: cached == null));
    return cached ?? AppGateConfig.disabled;
  }

  Future<void> _refresh(
    AppGateRepository repo,
    CacheStore cache, {
    required bool applyNow,
  }) async {
    final fresh = await repo.fetchOrNull();
    if (fresh == null) return; // 확인 실패 — 캐시를 건드리지 않는다
    await repo.writeCache(cache, fresh);
    if (applyNow && !_disposed) state = fresh;
  }
}

final appGateProvider = NotifierProvider<AppGateNotifier, AppGateConfig>(
  AppGateNotifier.new,
);

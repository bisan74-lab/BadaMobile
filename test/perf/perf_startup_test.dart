/// 첫 진입 로딩 기준선.
///
/// 사용자 제보 중 아직 안 잰 것: **"각 페이지의 로딩이 느리다."**
/// 지도 히트맵(개선 1)과 상세 예보 캐시(개선 2)를 고친 뒤에도 남는 부분이라,
/// 앱을 켜서 화면에 무엇이 뜨기까지 **무엇을 기다리는지** 여기서 잰다.
///
///     flutter test test/perf/perf_startup_test.dart
///
/// 재는 방식: 리포지토리를 전부 **지연을 넣은 목**으로 갈아 끼우고
/// (실제 왕복 지연을 흉내), 프레임을 돌리며 화면에 무엇이 언제 나타나는지
/// 기록한다. 시간 단언은 하지 않고(CI에서 들쭉날쭉하다) **"무엇이 무엇을
/// 기다리는가"**라는 구조만 못박는다.
library;

import 'package:bada_mobile/app/app.dart';
import 'package:bada_mobile/core/remote_config/app_gate_config.dart';
import 'package:bada_mobile/core/remote_config/app_gate_provider.dart';
import 'package:bada_mobile/core/remote_config/app_gate_repository.dart';
import 'package:bada_mobile/core/storage/prefs.dart';
import 'package:bada_mobile/features/fishing/data/models/fishing_index.dart';
import 'package:bada_mobile/features/fishing/data/repositories/fishing_repository.dart';
import 'package:bada_mobile/features/fishing/data/repositories/mock_fishing_repository.dart';
import 'package:bada_mobile/features/fishing/presentation/providers.dart';
import 'package:bada_mobile/features/locations/data/models/sea_location.dart';
import 'package:bada_mobile/features/tide/data/models/tide_data.dart';
import 'package:bada_mobile/features/tide/data/repositories/mock_tide_repository.dart';
import 'package:bada_mobile/features/tide/data/repositories/tide_repository.dart';
import 'package:bada_mobile/features/tide/presentation/providers.dart';
import 'package:bada_mobile/features/tide/presentation/tide_screen.dart';
import 'package:bada_mobile/features/weather/data/models/marine_weather.dart';
import 'package:bada_mobile/features/weather/data/repositories/marine_weather_repository.dart';
import 'package:bada_mobile/features/weather/data/repositories/mock_marine_weather_repository.dart';
import 'package:bada_mobile/features/weather/data/repositories/mock_wind_field_repository.dart';
import 'package:bada_mobile/features/weather/presentation/providers.dart';
import 'package:bada_mobile/features/weather/presentation/wind_field_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'perf_probe.dart';

/// 실제 왕복을 흉내 내는 지연. 한국에서 GitHub 릴리스 파일·data.go.kr은
/// 대략 이 정도 걸린다(느릴 땐 훨씬 더).
const _netLatency = Duration(milliseconds: 300);

/// 강제 업데이트 게이트 설정을 받아 오는 데 걸리는 시간.
const _gateLatency = Duration(milliseconds: 300);

/// 화면에 무엇이 언제 나타났는지 적어 두는 기록장.
class _Timeline {
  final _at = <String, Duration>{};
  final _watch = Stopwatch()..start();

  void mark(String what) => _at.putIfAbsent(what, () => _watch.elapsed);
  Duration? operator [](String what) => _at[what];
}

class _SlowTideRepository implements TideRepository {
  _SlowTideRepository(this.log);
  final _inner = MockTideRepository();
  final _Timeline log;

  @override
  Future<TideDay> fetchTideDay(SeaLocation location, DateTime date) async {
    log.mark('조석 요청 시작');
    await Future<void>.delayed(_netLatency);
    return _inner.fetchTideDay(location, date);
  }
}

class _SlowMarineRepository implements MarineWeatherRepository {
  _SlowMarineRepository(this.log);
  final _inner = MockMarineWeatherRepository();
  final _Timeline log;

  @override
  Future<MarineForecast> fetchForecast(
    SeaLocation location, {
    int hours = defaultForecastHours,
    int pastDays = 0,
  }) async {
    log.mark('예보 요청 시작');
    await Future<void>.delayed(_netLatency);
    return _inner.fetchForecast(location, hours: hours, pastDays: pastDays);
  }
}

class _SlowFishingRepository implements FishingRepository {
  _SlowFishingRepository(this.log);
  final _inner = MockFishingRepository();
  final _Timeline log;

  @override
  Future<FishingForecast> fetchForecast(SeaLocation location) async {
    log.mark('낚시지수 요청 시작');
    await Future<void>.delayed(_netLatency);
    return _inner.fetchForecast(location);
  }
}

/// 게이트 설정을 [_gateLatency] 뒤에 "막지 않음"으로 답하는 가짜 서버.
class _SlowGateRepository implements AppGateRepository {
  _SlowGateRepository(this.log, {required this.latency});
  final _Timeline log;
  final Duration latency;

  @override
  Future<AppGateConfig> fetch() async {
    log.mark('게이트 요청 시작');
    await Future<void>.delayed(latency);
    log.mark('게이트 응답 도착');
    return AppGateConfig.disabled;
  }
}

/// 앱을 켜서 프레임을 돌리며, 화면에 무엇이 언제 나타나는지 기록한다.
///
/// [gateLatency]만 다르게 두 번 돌려 비교하면 **게이트가 첫 화면을 얼마나
/// 늦추는지**가 그대로 나온다.
Future<_Timeline> _startApp(
  WidgetTester tester, {
  required Duration gateLatency,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final log = _Timeline();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appGateRepositoryProvider.overrideWithValue(
          _SlowGateRepository(log, latency: gateLatency),
        ),
        tideRepositoryProvider.overrideWithValue(_SlowTideRepository(log)),
        marineWeatherRepositoryProvider.overrideWithValue(
          _SlowMarineRepository(log),
        ),
        fishingRepositoryProvider.overrideWithValue(
          _SlowFishingRepository(log),
        ),
        windFieldRepositoryProvider.overrideWithValue(
          MockWindFieldRepository(),
        ),
      ],
      child: const BadaMobileApp(),
    ),
  );

  // 목이 진짜 Future.delayed로 기다리므로 테스트의 가짜 시간만으로는 끝나지
  // 않는다. runAsync로 실제 시간을 흘려 보내며 프레임을 진행한다.
  for (var i = 0; i < 240; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final onScreen = find.byType(TideScreen).evaluate().isNotEmpty;
    if (onScreen) log.mark('첫 화면(물때 탭)');
    // 스피너가 하나도 안 남았다 = 기다리던 것이 다 도착해 데이터가 붙었다.
    if (onScreen && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      log.mark('로딩 끝(데이터 표시)');
      break;
    }
  }
  return log;
}

void main() {
  testWidgets('기준선 — 앱을 켜서 첫 화면이 뜰 때까지', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final log = await _startApp(tester, gateLatency: _gateLatency);

    // 벽시계 절대값은 테스트 루프 오버헤드가 섞여 의미가 없다. **순서와
    // 간격**을 본다 — 무엇이 무엇을 기다리는가.
    const order = [
      '게이트 요청 시작',
      '게이트 응답 도착',
      '첫 화면(물때 탭)',
      '조석 요청 시작',
      '예보 요청 시작',
      '낚시지수 요청 시작',
      '로딩 끝(데이터 표시)',
    ];
    printReport('앱을 켠 순간부터의 순서', [
      for (final what in order)
        if (log[what] != null) Measurement(what, log[what]!),
    ]);
    // ignore: avoid_print
    print(
      '  ※ 절대 시간은 테스트 프레임 루프 오버헤드가 섞여 부풀려져 있다.\n'
      '     의미가 있는 것은 **순서**다: 게이트 → 조석 → 화면.\n'
      '     즉 첫 데이터까지 **순차 왕복 2번**을 기다린다(게이트, 조석).\n'
      '     게이트를 첫 화면 밖으로 빼면 1번이 된다.\n',
    );

    final gateArrived = log['게이트 응답 도착'];
    final firstScreen = log['첫 화면(물때 탭)'];
    expect(gateArrived, isNotNull, reason: '게이트 응답이 안 왔다 — 측정이 잘못됐다');
    expect(firstScreen, isNotNull, reason: '첫 화면이 끝내 안 떴다');

    // **핵심 구조 지표.** 지금은 게이트 응답이 온 뒤에야 첫 화면이 뜬다
    // (그전까지 화면 전체가 스피너 하나). 게이트가 5초까지 기다릴 수 있으므로
    // 느린 망에서는 그동안 앱이 아무것도 아니다.
    // **게이트를 첫 화면 밖으로 빼면 이 단언을 뒤집어야 한다.**
    expect(
      firstScreen! < gateArrived!,
      isFalse,
      reason: '게이트보다 화면이 먼저 떴다 — 개선됐다면 이 단언을 반대로 바꿔라',
    );

    // 데이터 요청도 게이트를 기다린다 — 게이트가 응답할 때까지 위젯이 아예
    // 안 만들어져서 요청조차 안 나간다. **게이트 지연이 데이터 지연에 그대로
    // 더해진다**(병렬이 아니다). 여기가 첫 진입이 느린 진짜 이유다.
    expect(log['조석 요청 시작'], isNotNull, reason: '조석을 아예 안 불렀다 — 화면 구성이 바뀐 것');
    expect(
      log['조석 요청 시작']! >= gateArrived,
      isTrue,
      reason: '조석 요청이 게이트보다 먼저 나갔다 — 개선됐다면 이 단언을 반대로 바꿔라',
    );

    // 첫 화면이 실제로 기다리는 것은 **조석 하나뿐**이다. 예보·낚시지수는
    // 그 화면의 "낚시정보" 패널을 열어야 나가므로 첫 진입 비용이 아니다.
    // (패널 기본값이 바뀌면 이 단언이 알려 준다.)
    expect(
      log['예보 요청 시작'],
      isNull,
      reason: '첫 화면이 예보까지 기다리게 됐다 — 첫 진입이 그만큼 느려진다',
    );
    expect(log['낚시지수 요청 시작'], isNull, reason: '첫 화면이 낚시지수까지 기다리게 됐다');
  });
}

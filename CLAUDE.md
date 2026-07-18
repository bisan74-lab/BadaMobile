# BadaMobile (바다윈디)

Flutter 앱. 바다타임(물때·조석)과 윈디(바람·해양 날씨 지도)를 하나로 합친
무료 한국어 낚시/해양 앱. Android 우선, iOS 확장 전제.

**세부 설계·데이터 연동·화면별 책임은 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)를,
요구사항(FR/NFR)은 [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)를 먼저 읽는다.**
이 파일은 그 두 문서에 없는, 매번 반복되는 실전 규칙만 담는다.

## 자주 쓰는 명령

```bash
flutter analyze          # 커밋 전 필수, 이슈 0이어야 함
flutter test              # 전체 테스트(현재 87개)
dart format lib test       # 커밋 전 포맷
```

## 반드시 지킬 것

- **API 키 커밋 금지**: `--dart-define=DATA_GO_KR_API_KEY=...`로만 주입
  (`core/config/env.dart`). Open-Meteo는 키 불필요.
- **Repository는 항상 실API → 캐싱 → 폴백(합성 데이터) 체인**으로 조립한다.
  새 데이터 소스를 추가할 때도 이 패턴을 따른다.
- **Ticker가 있는 화면(WeatherScreen)을 테스트할 때 `pumpAndSettle()` 쓰지
  말 것** — 계속 도는 애니메이션 때문에 멈추지 않는다. `pump()`로 프레임 수를
  지정해서 진행한다.
- **`app/app.dart`의 `IndexedStack`에 새 탭을 추가하면 `TickerMode(enabled:
  현재탭)`로 감싸야 한다** — 안 그러면 비활성 탭의 Ticker가 계속 돌아 다른
  탭 위젯 테스트가 멈춘다.
- 날씨 지도(`features/weather/presentation/`)의 `mapViewBounds`
  (`widgets/map_projection.dart`)는 **`OpenMeteoWindFieldRepository`의 격자
  범위(`minLat` 등)의 부분집합**이어야 한다 — 뷰가 격자보다 크면(밖으로 나가면)
  히트맵이 지도를 못 채운다. 현재 뷰는 북쪽을 잘라(maxLat 43.0) 격자
  (26.5~45.5)의 부분집합이므로 히트맵·해안선은 그대로 뷰를 채운다. 격자 범위
  자체를 바꾸면 `country_borders_data.dart`(해안선)도 같은 범위로 재추출해야
  한다(Natural Earth 50m geojson을 bbox로 클리핑, 공개 도메인 데이터).
- **강제 업데이트 게이트**(`core/remote_config/`): `remote_config/app_gate.json`의
  `forceUpgrade`를 true로 바꾸면(앱 재배포 없이) 이미 설치된 모든 기기에서
  앱 실행이 막히고 업데이트 안내 화면(`ForceUpgradeScreen`)만 뜬다 — 무료
  버전을 나중에 광고 버전으로 전환할 때 쓴다. 배포 전 `Env.forceUpgradeConfigUrl`
  기본값(지금은 이 브랜치의 GitHub raw 경로)을 실제로 유지할 위치로 바꿔야
  하고, `app_gate.json`의 `storeUrl`도 실제 스토어 링크로 채워야 한다. 설정을
  못 받아오면(오프라인 등) 항상 앱을 정상 실행한다 — 이 폴백 규칙은 절대
  건드리지 않는다.

## 릴리스 APK 빌드/전달

실제 기기로 확인이 필요하면 로컬 Android SDK 없이도 GitHub Actions로 빌드한다:
`release-apk.yml`(workflow_dispatch)을 트리거 → 완료되면 GitHub Release
(`test-build-N` 태그)에서 `app-release.apk`를 받아 전달한다. Actions
아티팩트가 아니라 Release를 쓰는 이유는 문서에 있음. 이 빌드는 실 API 키
없이 만들어 합성(mock) 데이터로 동작한다.

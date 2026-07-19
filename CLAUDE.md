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
  (`widgets/map_projection.dart`)와 **`OpenMeteoWindFieldRepository`의 격자
  범위(`minLat` 등)는 같은 bbox**(현재 위도 21~49, 경도 112~144 — 한국 중심에
  동아시아 주변국까지)를 써야 히트맵이 뷰를 정확히 채운다. 범위를 바꾸면
  `country_borders_data.dart`도 같은 bbox로 다시 뽑아야 한다(`tool/gen_coast.py`).
  이 파일은 **Natural Earth 10m 해안선·소형 섬·국경선·행정경계(주/성)·주요
  하천**(공개 도메인)을 bbox 클리핑·RDP 단순화해 자동 생성하며, 키별
  레이어(`해안선`·`국경`은 항상, `행정`·`강`은 확대 시)로 담는다
  (`CoastlinePainter`가 배율로 분기해 그린다). 제주·울릉도·외연도·다도해 등
  실제 섬이 그대로 들어 있다. 10m가 아니라 50m를 쓰면 섬이 대부분 빠지니 다시
  뽑을 때도 10m를 쓴다.
- 해안선·경계선(`CoastlinePainter`)과 도시 라벨(`MapCityLabelLayer`)은 **둘 다
  실제 WGS84 위경도**(Natural Earth 10m, 지명 좌표)를 그대로 쓴다.
  그래서 경도 보정 `kMapLonShift`(`map_projection.dart`)는 **0**이어야
  실제 지도와 맞고 서로도 정확히 겹친다 — 과거 -0.5°는 지금은 삭제된 항구
  점 마커에 맞추려던 오진단이었고, 해안선을 실제보다 서쪽으로 밀었다.
  값을 바꾸더라도 해안선·라벨은 **반드시 같은 값**을 써야 한다(한쪽만
  보정하면 라벨이 바다로 어긋난다). 지도에 항구 점은 없애고 라벨(rank별
  확대 단계 노출)만 지도 앱처럼 표시하며, `island:true` 항목(제주·울릉도·
  강화도·백령도 등)은 하늘색 마름모로 구분해 확대 시 바다 위 섬 이름도
  드러난다.
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

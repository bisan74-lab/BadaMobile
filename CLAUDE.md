# BadaMobile (바다윈디)

Flutter 앱. 바다타임(물때·조석)과 윈디(바람·해양 날씨 지도)를 하나로 합친
무료 한국어 낚시/해양 앱. Android 우선, iOS 확장 전제.

**iOS도 같은 저장소에서 간다**(`ios/`). 저장소를 나누거나 코드를 플랫폼별로
분기하지 않는다 — `lib/`는 공통이고, 갈리는 건 AdMob 광고 단위 ID 하나뿐이다
(`Env`가 `Platform.isIOS`로 읽는다. **iOS 키를 안 주면 안드로이드 단위로
폴백하지 않고 iOS 테스트 단위로 떨어진다** — 플랫폼이 다른 단위를 쓰면 광고가
조용히 사라지기 때문). 현재 상태와 남은 일은
[docs/IOS_SETUP.md](docs/IOS_SETUP.md).

**세부 설계·데이터 연동·화면별 책임은 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)를,
요구사항(FR/NFR)은 [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)를 먼저 읽는다.**
이 파일은 그 두 문서에 없는, 매번 반복되는 실전 규칙만 담는다.

**다음 작업: 성능 개선.** 화면 첫 로딩과 바람지도 화면 전환이 느리다는 제보가
있고, 구체적 후보 5개를 ARCHITECTURE.md "알려진 성능 이슈"에 정리해 뒀다.
**측정 → 수정 → 재측정** 순서를 지킨다.

**레이아웃을 건드리면 `text_scale_layout_test.dart`를 함께 돌린다** — 시스템
글자 크기 1.0~2.0배 × 화면 크기 2종으로 네 화면을 그려 오버플로를 잡는다.
`size.height - N` 같은 뺄셈은 **항상 clamp**할 것(음수가 되면 오버플로가
아니라 화면이 통째로 깨진다). 본문 화면에 `withClampedTextScaling`을 쓰는 건
접근성 설정 무시라 금지 — 크기가 외부 규격에 묶인 광고 자리에서만 예외다.

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
- **상세 예보 캐시는 "먼저 쓰는" 캐시다**
  (`caching_marine_weather_repository.dart`): 30분 안에 받아 온 것이 있으면
  네트워크를 아예 안 탄다(재조회 HTTP 5건 → 0건). 캐시로 답할 땐 지나간
  시간을 떼어 내지만 **`pastDays > 0`(홈 화면)은 자르지 않는다** — 그 과거가
  데이터다. 조회 실패 시 폴백은 나이를 안 따진다(오프라인에선 지나간 예보라도
  없는 것보다 낫다). 저장 형식은 `{fetchedAt, forecast}` 봉투이고, 봉투 없는
  옛 캐시는 신선하다고 보지 않는다.
- **지도 바람장은 서버 파일 우선**(`features/weather/.../github_wind_field_repository.dart`):
  GitHub Actions 크론(`.github/workflows/wind-data.yml` → `tool/fetch_wind.py`)이
  Open-Meteo에서 격자(현재 64×66≈0.62°, 4224점)를 배치로 받아 롤링 릴리스 `wind-data`의
  `wind_field.json.gz`(u/v를 cm/s int16 양자화)로 올리고, 앱은 그 파일 하나만
  내려받는다. 그래서 **사용자 기기는 Open-Meteo를 직접 다지점 호출하지 않아**
  분당 한도와 무관하고, 서버는 시간을 두고 배치로 받으므로 격자를 더 촘촘히
  뽑을 수 있다. 파일 실패 시 앱이 Open-Meteo 직접 호출→캐시→합성으로 폴백한다.
  파일 포맷을 바꾸면 `fetch_wind.py`와 `parseWindFieldFile`(및 그 테스트)을 함께
  맞춘다. **시간축도 비균일**(fmt 3): 앞 48시간은 1시간, 그 뒤는 3시간 간격이라
  `stepOffsets`(start로부터 경과 시간)를 담는다 — 균일 간격을 가정하면 시각이
  어긋난다. `caching_wind_field_repository`의 캐시 왕복도 이 배열을 보존해야
  한다. 수집 **간격**을 줄이는 건 의미가 없다(ECMWF가 하루 4번만 발표) —
  체감 신선도는 시간 해상도(`FINE_HOURS`)가 좌우한다.
- **서버 격자는 적응형(비균일)**: `fetch_wind.py`의 `_density_axis()`가 위·경도
  축마다 대한해협·서해·남해 연안(`LAT_FOCUS`/`LON_FOCUS`)에 밀도를 더 준
  비균일 좌표를 만든다(총점은 그대로, 핵심 해역만 더 촘촘히 재배치). 그래서
  파일엔 `latSteps`/`lonSteps` 외에 실제 축 좌표 배열 `lats`/`lons`(fmt 2)가
  들어 있고, `WindField`는 이걸 그대로 받아 **쌍3차(bicubic, 비균일 간격
  지원)**로 보간한다(`sample()`). `lats`/`lons`가 없는 구버전 파일·캐시는
  `WindField`가 `minLat`/`maxLat`/`latSteps`로 균일 격자를 재구성해 그대로
  동작한다(폴백 호환). 핵심 해역 범위를 바꾸면 `LAT_FOCUS`/`LON_FOCUS`/
  `DENSITY_BOOST`만 조정하면 된다.
- **지도 히트맵은 래스터 두 장을 한 벌(`_HeatmapPair`)로 묶어 한 번에
  교체한다**(`weather_screen.dart`): 전체 bbox 배경(저해상도)과 한반도
  핵심영역(고해상도)을 따로 setState하면, 그 사이 몇 프레임 동안 **새 시각의
  배경 위에 직전 시각의 핵심영역**이 덮여, 핵심영역 밖(화면 아래쪽 띠)만 먼저
  바뀌었다가 잠시 뒤 전체가 바뀌는 것처럼 보인다(영상 실측 약 0.12초).
  두 장은 `Future.wait`로 병렬로 굽고 setState는 한 번만 부른다.
  **단, 시간 슬라이더를 끄는 동안(`scrubbing`)에는 배경만 굽고 핵심영역은
  `null`로 둔다** — 고해상도가 배경의 5배 비용(88만 px vs 17만 px)이라 칸마다
  구우면 슬라이더가 밀린다. 손을 뗀 뒤 `_bakeCoreIfNeeded()`가 **배경은 그대로
  두고 핵심영역만** 채운다. 핵심영역이 `null`인 상태는 화면 전체가 같은 시각의
  저해상도라 문제가 없고, 금지되는 것은 **새 시각 배경 + 옛 시각 핵심영역**
  뿐이다. `wind_heatmap_swap_test.dart`가 이 둘을 구분해 검사한다.
- **히트맵엔 난류(turbulence) 도메인 워프를 얹는다**(`wind_heatmap.dart`의
  `_TurbulenceNoise`): 실제 모델 격자로는 다 담기 힘든 중규모 소용돌이를
  시각적으로 흉내 내려고, 색을 뽑을 좌표를 고정 시드 FBM 노이즈로 풍속에
  비례해 살짝 뒤튼다(무풍은 거의 그대로, 강풍일수록 더 흔들림). 실제 u/v
  값 자체는 바꾸지 않고 히트맵 렌더링에만 적용되며, 시드가 고정이라 시간이
  지나도 같은 위치는 같은 방식으로만 흔들려 지글거리지 않는다. 강도를
  바꾸려면 `_turbNoiseFreq`(소용돌이 크기)·`_turbMaxWarpDeg`(최대 뒤틀림)를
  조정한다.
- **홈·낚시정보 카드의 예보도 서버 파일 우선**
  (`features/weather/.../github_point_forecast_repository.dart`):
  `.github/workflows/point-forecast.yml` → `tool/fetch_points.py`가 3시간마다
  전국 지역(앱 `sample_locations.dart`를 파이썬이 그대로 읽는다)을 Open-Meteo
  다지점 요청 4번으로 모아 롤링 릴리스 `point-forecast`의
  `point_forecast.json.gz`(약 100KB)로 올린다. `OpenMeteoMarineRepository`는
  **지역 하나당 요청이 5번**(WAM 총파고·WAM 너울·GFS·수온·육상예보) 나가서
  새 지역마다 1~2초가 걸렸는데, 두 화면이 쓰는 건 날짜별 대표값 하나씩이라
  3시간 간격 파일이면 충분하다. **상세 예보 화면(`marineForecastProvider`)은
  이 파일을 쓰지 않는다** — 너울·파력이 필요하고 정밀도도 중요해서 직접
  호출을 유지한다. 파일에 없는 지역·다운로드 실패는 직접 호출로 폴백한다.
  값이 원본과 맞는지는 `tool/verify_points.py`가 표본 10곳을 같은 시각
  Open-Meteo와 대조해 확인하며, 수집 워크플로가 업로드 직후 함께 돌린다.
- **낚시지수도 서버 파일 우선**(`features/fishing/.../github_fishing_repository.dart`):
  GitHub Actions 크론(`.github/workflows/fishing-data.yml` → `tool/fetch_fishing.py`)이
  data.go.kr에서 전국 하루치를 모아 롤링 릴리스 `fishing-data`의
  `fishing_index.json.gz`(약 20KB)로 올리고, 앱은 그 파일 하나만 받는다.
  **이 API의 `numOfRows` 상한은 300이다** — 넘기면 HTTP 200에
  `resultCode: 10 INVALID_REQUEST_PARAMETER_ERROR`만 담긴 76B가 오고, 예전에
  3000으로 요청하다 늘 빈 응답을 받아 조용히 합성 데이터로 폴백했다(지역을
  바꿀 때마다 5~9초 걸리던 원인). 값을 바꿀 땐 `tool/probe_fishing.py`로
  실제 응답을 먼저 확인한다.
  **낡은 파일은 앱이 거부한다** — 파일에 오늘 날짜 지수가 없으면(수집이 멈춘
  상태) 서버 파일을 안 쓰고 직접 호출로 폴백한다. 안 그러면 릴리스에 남아
  있는 며칠 전 파일을 그대로 받아 "이 날짜의 낚시지수가 없습니다"만 뜬다
  (2026-08, data.go.kr 타임아웃으로 사흘 연속 수집 실패 때 실제로 발생).
  수집 쪽도 그때 함께 손봤다: 타임아웃 60→20초에 재시도 5회(백오프
  5·15·45·120초), `User-Agent` 명시(기본 `Python-urllib` UA를 조용히 버리는
  WAF 대비), API가 파라미터 오류를 답하면 재시도하지 않음(`ApiError`),
  크론 하루 4회 + **이미 오늘 파일이 올라와 있으면 수집 자체를 건너뜀**
  (`--check-published`).
- **어종 목록은 API가 실제로 주는 것만 담는다**(`fishing_index.dart`의
  `fishingSpeciesCatalog`): 2026-08 실측 기준 감성돔·농어·돌돔·벵에돔·우럭·
  참돔 **6종이 전부**다. `gubun`을 바꿔도 늘지 않는다 — 유효값은 `갯바위`·
  `선상` 둘뿐이고 두 응답이 서로 같다(나머지는 INVALID_REQUEST_PARAMETER_ERROR).
  그래서 광어·문어·쭈꾸미·갑오징어는 이 API로 얻을 수 없고, 목록에 넣으면
  지수가 영영 빈칸이다. API가 함께 주는 `기타어종`(묶음)·`-`(빈 값)도
  `nonSpeciesLabels`로 걸러 화면·선택 목록에서 제외한다.
  `seasonalSpecies`·`preferredSpeciesForRegion`도 이 목록 안에서만 고른다
  (테스트가 강제한다). 목록을 바꿀 땐 `tool/probe_fishing.py`(mode=gubun)로
  실제 어종을 먼저 확인한다.
- **쭈꾸미·갑오징어·문어는 관측이 아니라 추정이다**
  (`fishing/data/models/jigging_estimate.dart`): 공공데이터에 이 어종 지수가
  없어서, 그날 조류 세기와 지점 예보의 바람·돌풍·파고, 그리고 달별 제철
  가중치로 계산한다. **추가 네트워크 호출이 없다** — 화면이 이미 갖고 있는
  조위·예보만 쓴다. 화면에는 반드시 **"추정" 배지**를 달아 관측 지수와
  구분하고, 설정 > 데이터 출처와 스토어 설명에도 추정임을 명시한다.
  지켜야 할 세 가지:
  - **조류 세기는 `relativeTideStrength`(지점 상대)를 쓴다.
    `tideStrengthFraction`(조차÷800cm, 절대)을 쓰면 안 된다.** 절대값은 물때
    화면 "조류세기" 막대 표시용으로만 남겨 뒀다. 절대값을 쓰던 시절엔 무창포가
    **조금인데도** 조차 376cm(=0.47)라 "물이 센 날"로 읽혀 거의 모든 날이
    매우나쁨이었고, 반대로 통영은 사리에도 270cm(=0.34)라 늘 "느린 날"이었다.
    지금은 물때(사리↔조금) 위상을 축으로 삼고, 그날 조차로 그 지점의 사리
    조차를 역산해 세기 상한만 조정한다(동해처럼 조차가 없는 곳 대비).
    상한 하한값 0.50은 일부러 높다 — 더 낮추면 조차 작은 곳에서 15개 물때가
    전부 같은 등급으로 눌린다(반대 방향 실패).
  - **조류 선호 곡선은 좌우 비대칭**(`slowTolerance` / `fastTolerance`) — 셋 다
    바닥에 채비를 붙여 놓고 하는 낚시라 조류가 과한 것이 없는 것보다 훨씬
    해롭다. 대칭으로 두면 "정지"가 "급류"만큼 나쁘게 나온다. 갑오징어는
    **약한 중간 > 정지 > 중간 > 급류** 순(사용자 실사용 경험).
  - **조류 곡선은 수식이 아니라 제어점 표(`_tideCurve`)다.** 물때는 15단계
    이산값이라 화면 등급 분포를 직접 정해야 하는데, 가우시안은 최적 부근이
    평평해 "1물만 매우좋음, 조금·2물은 좋음" 같은 배분이 안 나온다.
    제어점 x값은 서해 기준 15개 물때가 놓이는 위상값과 같은 자리다.
  - **등급 분포를 목표치로 못박아 뒀다**(앱 방침: 약간 후하게).
    15개 물때 기준으로 `_peakSeason`(1.0, 9월)은 매우좋음 2 / 좋음 4 /
    보통 6 / 나쁨 3, `_shoulderSeason`(0.85, 10월·봄철)은 매우좋음 2 /
    좋음 2 / 보통 8 / 나쁨 3, `_lateSeason`(0.72, 11월 끝물)은 매우좋음
    없이 좋음 2 / 보통 8 / 나쁨 5. **물때는 사리를 축으로 좌우 대칭이라
    등급이 2칸(13%) 단위로만 움직인다** — 5% 단위 조정은 구조상 불가능하다.
    `_tideCurve`·`_season`·등급 문턱은 **한 벌**이라 하나만 바꾸면 분포가
    깨진다.
  - **제철 가중치(`_season`)는 12개월을 빠짐없이 채운다.** 빠진 달이 하한으로
    떨어지면 그 달은 물때가 아무리 좋아도 한 등급으로 눌려 **물때 차이가
    화면에서 사라진다**(8월 갑오징어가 전 물때 매우나쁨이던 원인).
    쭈꾸미·갑오징어는 **9월(금어기 해제)이 최고, 10월이 그다음, 11월은
    개체수가 확 줄어드는 끝물**(사용자 실사용 경험).
  - **"매우나쁨"은 성수기(9~11월)엔 나오지 않는다.** 제철엔 물이 많이 흘러도
    잡히기 때문이다. 바닥(0.08 미만)은 비수기의 가장 센 물때나 강풍·높은
    파고에서만 닿는다(연중 대략 5~7%).
  - **바람·파고는 없으면 `null`로 넘긴다**(`?? 0`으로 채우지 않는다).
    예보 범위 밖 날짜엔 값이 아예 없고, 그때는 물때·제철로만 판단해야 한다.

  상수를 바꾸면 `dart run tool/verify_jigging.dart`로 전국 대표 지점 × 15개
  물때 × 12개월 등급 분포를 뽑아 불변식(물때 변별력, 한쪽 끝으로 눌리지 않음,
  어종별 선호 방향, 제보 사례 재현)을 확인하고, `jigging_estimate_test.dart`도
  같이 돌린다.
- **어종 선택 목록은 그 지역에 값이 있는 어종만 보여준다**
  (`FishingForecast.availableSpecies`): 포인트마다 주는 어종이 달라서, 전체
  카탈로그를 그대로 띄우면 고르고도 빈칸이 나온다. 물때 화면·홈 화면의 선택
  UI 둘 다 이 집합으로 좁힌다(예보를 아직 못 받았으면 카탈로그 전체).
- **앱이 Open-Meteo를 직접 호출하는 경로(폴백)의 격자 총 좌표 수는 600 미만
  유지**(현재 21×24=504): 무료 한도가 분당 600콜이고 다지점 요청은 좌표
  1개=1콜이라, 넘기면 요청 한 번에 한도를 초과해 **매번 429 → 합성 폴백**이
  된다(837점으로 올렸다가 실제로 겪음). 색을 더 촘촘히 하려면 **서버 격자
  (`fetch_wind.py`의 LAT/LON_STEPS)를 올린다** — 서버는 배치로 나눠 받아 분당
  한도에 안 걸린다. 앱 직접호출 격자는 폴백이므로 504로 둔다.
- **서버 격자(`fetch_wind.py`)의 한 실행 총점은 5000 미만 유지**(현재
  64×66=4224): 서버는 배치·SLEEP로 분당 600콜은 피하지만 Open-Meteo엔
  **시간당 약 5000콜** 한도도 있어, 한 실행(≈15분)이 5000점을 넘으면 도중에
  429로 실패한다(0.5°/6399점으로 올렸다가 배치 5100 근처에서 겪음). 더 촘촘히
  하려면 실행을 시간 간격으로 쪼개야 하지, 한 실행 격자를 5000 넘기면 안 된다.
- **Ticker가 있는 화면(WeatherScreen)을 테스트할 때 `pumpAndSettle()` 쓰지
  말 것** — 계속 도는 애니메이션 때문에 멈추지 않는다. `pump()`로 프레임 수를
  지정해서 진행한다.
- **`app/app.dart`의 `IndexedStack`에 새 탭을 추가하면 `TickerMode(enabled:
  현재탭)`로 감싸야 한다** — 안 그러면 비활성 탭의 Ticker가 계속 돌아 다른
  탭 위젯 테스트가 멈춘다.
- 날씨 지도(`features/weather/presentation/`)의 `mapViewBounds`
  (`widgets/map_projection.dart`)와 **`OpenMeteoWindFieldRepository`의 격자
  범위(`minLat` 등)는 같은 bbox**(현재 위도 18~57, 경도 108~148 — 한국 중심에
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
- **강제 업데이트 게이트**(`core/remote_config/`): 공개 저장소
  `app_gate.json`의 **`minSupportedVersion`을 올리면**(앱 재배포 없이) 그보다
  낮은 버전을 쓰던 기기는 다음 실행부터 앱이 막히고 업데이트 안내 화면
  (`ForceUpgradeScreen`)만 뜬다. **새 버전이 Play에 실제로 노출된 뒤에**
  올린다 — 순서를 뒤집으면 업데이트할 것이 없는 상태로 모두가 잠긴다.
  `forceUpgrade: true`는 버전과 무관하게 전부 막는 비상 스위치다.
  - 버전 비교는 숫자 단위(`0.10.0 > 0.9.0`)로 하고, **형식이 이상하면 비교를
    건너뛰고 통과시킨다**(fail-open). 설정을 못 받아와도(오프라인 등) 항상
    정상 실행한다 — 이 두 폴백 규칙은 절대 건드리지 않는다.
  - **게이트는 첫 화면을 막지 않는다.** 지난 실행에서 캐시한 설정을 즉시
    적용하고(대기 0), 새 설정은 백그라운드로 받아 **캐시에만** 저장해 다음
    실행부터 반영한다. 그래서 `minSupportedVersion`을 올리면 구버전 기기는
    설정을 한 번 받아 간 **다음 실행부터** 막힌다. 캐시가 없는 첫 실행만
    앱을 먼저 띄우고 응답이 오면 판단한다. 확인 실패(`fetchOrNull`이 null)면
    **캐시를 덮어쓰지 않는다** — 오프라인이라고 차단이 풀리면 안 된다.
  - **`AppInfo.appVersion`은 pubspec의 version과 반드시 같아야 한다** — 게이트가
    이 값으로 자기 버전을 판단한다. `app_gate_test.dart`가 둘이 같은지, 그리고
    커밋된 `public_data/app_gate.json`이 현재 빌드를 막지 않는지 검사한다.
  - 배포 전 `Env.forceUpgradeConfigUrl` 기본값을 실제로 유지할 위치로 바꾸고,
    `app_gate.json`의 `storeUrl`도 실제 스토어 링크로 채운다.

- **광고는 부가 기능이라 절대 앱을 막지 않는다**(`core/widgets/ad_placeholder.dart`):
  배너 로드에 실패하거나 광고가 꺼져 있으면 같은 높이의 앱 소개 박스로 조용히
  대체된다 — 이 폴백을 없애면 광고가 없을 때 레이아웃에 빈 칸이 생긴다.
  배너 자리는 물때·설정 두 곳이고 `AdSlot`으로 구분해 **화면마다 다른 광고
  단위**를 쓸 수 있다(설정용을 안 주입하면 물때용으로 폴백한다).
  광고 ID는 `Env.admobBannerAdUnitId`·`admobSettingsBannerAdUnitId`
  (dart-define)와 Gradle 환경변수
  `ADMOB_APP_ID`(AndroidManifest 플레이스홀더)로 **빌드 때 주입**하고,
  둘 다 기본값이 구글 공식 **테스트 ID**라 설정 없이 빌드해도 실 수익 계정에
  무효 트래픽이 잡히지 않는다. 실 ID는 저장소에 커밋하지 않는다.
  **위젯 테스트가 광고 플랫폼 채널을 건드리면 안 되므로** `adsRuntimeEnabled`
  기본값은 false이고 `main()`에서만 켠다 — 테스트에서 이 값을 켜지 말 것.

- **대상 API 수준은 `android/app/build.gradle.kts`의 `playTargetSdk`로 못박는다**
  (현재 36 = Android 16). Flutter의 기본값(`flutter.targetSdkVersion`)을 그대로
  쓰면 안 된다 — Flutter 3.32.5의 기본은 35라서 Google Play가 요구하는
  "최신 Android 출시로부터 1년 이내"에 미달해 **앱 업데이트 자체가 막힌다**
  (2026-08-31부터). Play가 요구 수준을 올리면(매년 8월경) 이 값을 올리고,
  AGP가 그 API를 지원하는 버전인지 `settings.gradle.kts`에서 함께 확인한다.
  릴리스 워크플로 두 개는 `sdkmanager`로 해당 플랫폼을 미리 설치한다 —
  없으면 `failed to find target with hash string android-NN`으로 깨진다.

## 릴리스 빌드/전달

기기 확인용 APK와 스토어 제출용 AAB는 **워크플로가 다르다**:

| | `release-apk.yml` | `release-aab.yml` |
|---|---|---|
| 서명 | debug 키 | 업로드 키(Secret) |
| 광고 | 테스트 광고 | 실제 광고 ID(Secret) |
| 용도 | 기기에 설치해 확인 | Play Console 제출 |

실제 기기로 확인이 필요하면 로컬 Android SDK 없이도 GitHub Actions로 빌드한다:
`release-apk.yml`(workflow_dispatch)을 트리거 → 완료되면 GitHub Release
(`test-build-N` 태그)에서 `app-release.apk`를 받아 전달한다. Actions
아티팩트가 아니라 Release를 쓰는 이유는 문서에 있음.

릴리스 서명은 `android/key.properties`가 있을 때만 적용되고 없으면 debug 키로
폴백한다 — 이 폴백을 없애면 키가 없는 CI·새 클론에서 빌드가 깨진다.

**스토어 런칭 절차(계정 생성·ID 발급·Secret 등록·Play Console 등록)는
[docs/PLAY_STORE_LAUNCH.md](docs/PLAY_STORE_LAUNCH.md)에 정리돼 있다.**

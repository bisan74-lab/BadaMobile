# BadaMobile 아키텍처

## 설계 원칙

- **Feature-first 구조**: 화면·상태·데이터를 기능 단위(`tide`, `weather`, `locations`, `home`)로 묶어
  기능 추가/삭제가 다른 영역에 영향을 주지 않도록 한다.
- **Repository 패턴**: UI는 리포지토리 인터페이스에만 의존한다. 현재는 목(mock) 구현을 주입하며,
  실제 API 연동 시 구현체만 교체한다.
- **Riverpod**: Provider를 통해 리포지토리를 주입하고 화면 상태를 관리한다.
  테스트에서 `ProviderScope(overrides: ...)`로 목을 주입할 수 있다.

## 레이어 구성

```
presentation (screens, widgets, providers)
        │  Riverpod Provider로 주입
        ▼
domain-ish (models, repository 인터페이스)
        ▼
data (repository 구현: mock → 추후 KHOA / Open-Meteo API)
```

## 기능별 책임

### features/tide — 조석·물때 (바다타임 영역)
- `TideRepository`: 특정 지역·날짜의 만조/간조 이벤트와 시간별 조위 곡선 제공
- 물때(1물~15물, 조금/사리) 계산은 `core/utils/mul_ttae.dart` 에서 음력 기반 표준 공식으로 처리
- 화면: 일간 조석표, 조위 그래프(CustomPaint), 물때 배지

### features/weather — 바람·해양 날씨 (윈디 영역)
- `MarineWeatherRepository`: 시간별 풍향·풍속·돌풍·파고·수온 예보 제공
- 화면: 시간별 예보 리스트, 풍향 화살표, 요약 카드
- **바람 지도(파티클 애니메이션)** 는 2단계 과제 — `WindMapScreen` 에 자리만 잡아 둠.
  구현 시 후보: `flutter_map` + 커스텀 파티클 레이어, 또는 WebView + leaflet-velocity

### features/locations — 지역
- 해양 관측 지점(포인트) 목록·검색, 즐겨찾기(추후 `shared_preferences` 영속화)
- 선택된 지역은 앱 전역 상태(`selectedLocationProvider`)로 공유되어 tide/weather 화면이 반응

### features/home — 홈 대시보드
- 선택 지역의 "오늘": 물때, 다음 만조/간조, 현재 바람·파고 요약

## 데이터 소스 연동 계획

| 데이터 | 소스 | 비고 |
|---|---|---|
| 조석 예보(만조/간조), 조위 | KHOA 바다누리 Open API | 서비스 키 발급 필요, 무료 |
| 파고·수온·너울 | Open-Meteo Marine API | 키 불필요, 무료(비상업) |
| 바람·기온·강수 | Open-Meteo Forecast API | 키 불필요 |

API 키는 `--dart-define=KHOA_API_KEY=...` 로 주입한다 (`core/config/env.dart` 참고).
저장소에 키를 커밋하지 않는다.

## 상태 관리 규칙

- 전역 상태: 선택 지역, 즐겨찾기 → `locations/presentation/providers.dart`
- 화면 상태: `FutureProvider.family` 로 (지역, 날짜) 파라미터화된 비동기 데이터 로드
- 위젯은 가능한 한 `ConsumerWidget` 으로 얇게 유지

## 테스트 전략

- `core/utils` 순수 함수(물때 계산 등)는 단위 테스트 필수
- 리포지토리 목 구현은 그 자체로 테스트 픽스처 역할
- 화면은 스모크 위젯 테스트(렌더링 + 핵심 텍스트 존재) 수준으로 시작

## iOS 확장

Dart 코드는 플랫폼 독립적이다. iOS 추가 시:
1. `flutter create --platforms ios .` 로 `ios/` 생성
2. 서명·번들 ID 설정 (`com.badamobile.app`)
3. 알림 등 플랫폼 기능 사용 시 iOS 권한 설정 추가

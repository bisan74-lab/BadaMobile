import 'dart:io' show Platform;

/// 빌드 시 주입되는 환경 값.
///
/// 예: flutter run --dart-define=DATA_GO_KR_API_KEY=발급받은키
/// API 키는 절대 저장소에 커밋하지 않는다.
class Env {
  Env._();

  /// 공공데이터포털(data.go.kr) 일반 인증키.
  ///
  /// 계정 공통 키이므로 활용신청이 승인된 모든 API에 사용된다:
  /// - 바다낚시지수 조회 (승인됨)
  /// - 조석예보 조회 (추가 활용신청 필요)
  static const dataGoKrApiKey = String.fromEnvironment('DATA_GO_KR_API_KEY');

  /// (구) KHOA 바다누리 직접 발급 키. data.go.kr 키와 별도로 쓸 경우에만 주입.
  static const khoaApiKey = String.fromEnvironment(
    'KHOA_API_KEY',
    defaultValue: '',
  );

  /// 실제 API 대신 목 데이터를 사용할지 여부. 키가 없으면 자동으로 목 사용.
  static bool get useMockData => dataGoKrApiKey.isEmpty && khoaApiKey.isEmpty;

  /// 강제 업데이트 게이트 설정(JSON)을 받아오는 URL.
  ///
  /// 무료 버전 배포 후 광고 버전으로 전환할 때, 이 URL이 가리키는 JSON 파일의
  /// `forceUpgrade`를 true로 바꾸면(앱 재배포 없이) 이미 설치된 모든 기기에서
  /// 앱 실행이 막히고 업데이트 안내만 뜬다 — `core/remote_config/`를 참고.
  ///
  /// **공개 데이터 저장소**를 가리킨다. 코드 저장소는 비공개라 raw 파일을
  /// 앱이 익명으로 못 받는다. 설정을 못 받아오면 앱은 항상 정상 실행되므로
  /// (게이트만 조용히 꺼진다) URL이 틀려도 앱이 막히지는 않는다.
  /// `--dart-define=FORCE_UPGRADE_CONFIG_URL=...` 로 재정의 가능.
  static const forceUpgradeConfigUrl = String.fromEnvironment(
    'FORCE_UPGRADE_CONFIG_URL',
    defaultValue:
        'https://raw.githubusercontent.com/bisan74-lab/badawindy-data/'
        'main/app_gate.json',
  );

  /// 물때 화면 하단 배너의 AdMob 광고 단위 ID(플랫폼별).
  ///
  /// 기본값은 **구글이 공개한 테스트 광고 단위 ID**다. 그래서 아무 설정 없이
  /// 빌드해도 테스트 광고가 뜨고, 실제 수익 계정에 무효 트래픽이 잡히지 않는다.
  /// 스토어에 올릴 빌드는 반드시 실제 ID를 주입한다:
  /// `--dart-define=ADMOB_BANNER_AD_UNIT_ID=ca-app-pub-XXXX/YYYY`
  ///
  /// 빈 문자열을 주입하면 광고를 아예 로드하지 않고 앱 소개 박스만 보여준다
  /// (광고 없는 버전을 내보낼 때 쓴다).
  /// **AdMob 광고 단위는 플랫폼마다 다르다.** 같은 앱이라도 Android용과 iOS용
  /// 단위를 AdMob에서 따로 만들어야 하고, 서로 바꿔 넣으면 광고가 안 나온다.
  /// 그래서 주입 키도 `..._IOS`로 나누고, iOS에서 값을 안 주면 구글 iOS
  /// **테스트** 단위로 떨어진다(안드로이드 단위로 폴백하지 않는다 — 잘못된
  /// 플랫폼 단위를 쓰면 조용히 광고가 사라진다).
  static const _androidBannerAdUnitId = String.fromEnvironment(
    'ADMOB_BANNER_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );
  static const _iosBannerAdUnitId = String.fromEnvironment(
    'ADMOB_BANNER_AD_UNIT_ID_IOS',
    defaultValue: 'ca-app-pub-3940256099942544/2934735716',
  );

  static String get admobBannerAdUnitId =>
      Platform.isIOS ? _iosBannerAdUnitId : _androidBannerAdUnitId;

  static const _androidSettingsBannerAdUnitId = String.fromEnvironment(
    'ADMOB_SETTINGS_BANNER_AD_UNIT_ID',
  );
  static const _iosSettingsBannerAdUnitId = String.fromEnvironment(
    'ADMOB_SETTINGS_BANNER_AD_UNIT_ID_IOS',
  );

  static String get _settingsBannerAdUnitId => Platform.isIOS
      ? _iosSettingsBannerAdUnitId
      : _androidSettingsBannerAdUnitId;

  /// 설정 화면 하단 배너의 AdMob 광고 단위 ID.
  ///
  /// 화면별로 광고 단위를 나누면 AdMob 리포트에서 어느 자리가 얼마나 버는지
  /// 따로 볼 수 있다. 주입하지 않으면 [admobBannerAdUnitId]를 그대로 쓰므로,
  /// 단위를 하나만 만든 경우에도 설정이 필요 없다(광고를 끄려고 빈 값을
  /// 주입한 경우에도 함께 꺼진다).
  static String get admobSettingsBannerAdUnitId =>
      _settingsBannerAdUnitId.isEmpty
      ? admobBannerAdUnitId
      : _settingsBannerAdUnitId;

  /// 낚시지수 데이터(서버가 미리 모아 둔 정적 파일) URL.
  ///
  /// `.github/workflows/fishing-data.yml`이 하루 한 번 data.go.kr에서 전국
  /// 하루치를 모아 **공개 데이터 저장소**의 롤링 릴리스에 올린 파일이다.
  /// data.go.kr의 이 API는 numOfRows 상한이 300이라 앱이 직접 받으면 6쪽을
  /// 나눠 받아야 하고 6초쯤 걸린다 — 서버가 모아 두면 앱은 약 20KB 파일
  /// 하나로 끝난다. 못 받으면 앱이 data.go.kr 직접 호출로 폴백한다.
  /// `--dart-define=FISHING_DATA_URL=...` 로 재정의 가능(빈 값이면 직접 호출).
  static const fishingDataUrl = String.fromEnvironment(
    'FISHING_DATA_URL',
    defaultValue:
        'https://github.com/bisan74-lab/badawindy-data/releases/download/'
        'fishing-data/fishing_index.json.gz',
  );

  /// 홈 화면·낚시정보 카드용 지역별 예보 파일 URL.
  ///
  /// `.github/workflows/point-forecast.yml`이 3시간마다 Open-Meteo에서 전국
  /// 지역을 모아 올린다. 앱이 직접 받으면 지역 하나당 요청이 5번 나가
  /// 1~2초가 걸리는데, 이 파일은 한 번에 끝난다. 없으면 직접 호출로 폴백한다.
  /// `--dart-define=POINT_FORECAST_URL=...` 로 재정의 가능(빈 값이면 직접 호출).
  static const pointForecastUrl = String.fromEnvironment(
    'POINT_FORECAST_URL',
    defaultValue:
        'https://github.com/bisan74-lab/badawindy-data/releases/download/'
        'point-forecast/point_forecast.json.gz',
  );

  /// 지도용 바람장 격자 데이터(서버가 미리 뽑아 둔 정적 파일) URL.
  ///
  /// GitHub Actions 크론(`.github/workflows/wind-data.yml`)이 Open-Meteo에서
  /// 받아 **공개 데이터 저장소**의 롤링 릴리스(`wind-data`)에 올린
  /// `wind_field.json.gz`를 가리킨다. 코드 저장소는 비공개라 릴리스 자산을
  /// 앱이 익명으로 받을 수 없어(인증 필요) 기상 데이터만 공개 저장소에 둔다.
  /// 앱은 이 파일 하나만 내려받아 지도에 쓰므로 사용자 기기가 Open-Meteo를
  /// 직접 다지점 호출하지 않는다(분당 한도 회피·모든 사용자 동일 데이터).
  /// 받지 못하면 앱이 Open-Meteo 직접 호출로 폴백한다.
  /// `--dart-define=WIND_DATA_URL=...` 로 재정의 가능.
  static const windDataUrl = String.fromEnvironment(
    'WIND_DATA_URL',
    defaultValue:
        'https://github.com/bisan74-lab/badawindy-data/releases/download/'
        'wind-data/wind_field.json.gz',
  );
}

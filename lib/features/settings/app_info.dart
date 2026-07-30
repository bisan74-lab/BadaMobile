/// 설정 > 정보 화면에 표시하는 앱 메타데이터.
/// [appVersion]은 pubspec.yaml의 version과 수동으로 맞춰 둔다.
class AppInfo {
  const AppInfo._();

  static const appName = '바다 윈디';
  static const appVersion = '0.3.0';
  static const releaseDate = '2026-07-30';

  /// 오류신고 및 사업제휴 문의 이메일.
  static const contactEmail = 'bisan74@gmail.com';

  /// 개인정보처리방침 전문(웹) 주소. **Play Console에 등록하는 URL과 같아야
  /// 한다.** 저장소의 `docs/privacy-policy.html`을 GitHub Pages로 서빙한다
  /// (Settings → Pages → Source: 기본 브랜치 `/docs`).
  static const privacyPolicyUrl =
      'https://bisan74-lab.github.io/BadaMobile/privacy-policy.html';
}

/// 설정 > 정보 화면에 표시하는 앱 메타데이터.
/// [appVersion]은 pubspec.yaml의 version과 수동으로 맞춰 둔다.
class AppInfo {
  const AppInfo._();

  static const appName = '바다윈디';
  static const appVersion = '0.4.0';
  static const releaseDate = '2026-08-01';

  /// 오류신고 및 사업제휴 문의 이메일.
  static const contactEmail = 'bisan74@gmail.com';

  /// 개인정보처리방침 전문(웹) 주소. **Play Console에 등록하는 URL과 같아야
  /// 한다.**
  ///
  /// 코드 저장소는 비공개이고 비공개 저장소의 GitHub Pages는 유료 플랜에서만
  /// 되므로, **공개 데이터 저장소**(`badawindy-data`)에서 서빙한다.
  /// 원본은 이 저장소의 `public_data/privacy-policy.html`이다.
  static const privacyPolicyUrl =
      'https://bisan74-lab.github.io/badawindy-data/privacy-policy.html';
}

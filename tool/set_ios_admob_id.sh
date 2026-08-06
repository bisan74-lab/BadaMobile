#!/usr/bin/env bash
# iOS Info.plist의 AdMob 앱 ID를 실제 값으로 바꾼다.
#
# 안드로이드는 Gradle이 manifestPlaceholder로 주입하지만(build.gradle.kts),
# iOS는 Info.plist가 정적 파일이라 빌드 전에 갈아 끼워야 한다. 저장소에는
# **구글 공식 테스트 앱 ID**만 커밋돼 있고, 실제 ID는 CI Secret으로만 들어온다.
#
#   ADMOB_APP_ID_IOS=ca-app-pub-XXXX~YYYY tool/set_ios_admob_id.sh
#
# 값이 비어 있으면 아무것도 하지 않는다(테스트 광고 그대로 빌드).
set -euo pipefail

PLIST="${PLIST:-ios/Runner/Info.plist}"
ID="${ADMOB_APP_ID_IOS:-}"

if [ -z "$ID" ]; then
  echo "ADMOB_APP_ID_IOS 없음 — 테스트 앱 ID 그대로 빌드한다."
  exit 0
fi

# 형태 검사. iOS 앱 ID는 물결(~)이고 광고 단위 ID는 슬래시(/)라 바꿔 넣기 쉽다.
# 잘못 넣으면 빌드는 되고 광고만 안 나와서 원인을 찾기 어려우니 여기서 막는다.
case "$ID" in
  ca-app-pub-*~*) ;;
  *)
    echo "::error::ADMOB_APP_ID_IOS 형식이 이상하다(앱 ID는 ca-app-pub-...~... 형태)." >&2
    exit 1
    ;;
esac

# 값은 출력하지 않는다.
/usr/libexec/PlistBuddy -c "Set :GADApplicationIdentifier $ID" "$PLIST"
echo "GADApplicationIdentifier 교체 완료 ($PLIST)"

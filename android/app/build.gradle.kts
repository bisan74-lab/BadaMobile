import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 릴리스 서명 정보. `android/key.properties`(gitignore됨)가 있을 때만 읽어
// 실제 키로 서명하고, 없으면 아래에서 debug 키로 폴백한다 — 그래서 키가 없는
// CI(테스트 APK 빌드)나 새로 클론한 환경에서도 빌드가 그대로 된다.
// 파일 형식:
//   storeFile=/절대/경로/upload-keystore.jks
//   storePassword=...
//   keyAlias=upload
//   keyPassword=...
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.badamobile.bada_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.badamobile.bada_mobile"
        // Google Mobile Ads SDK가 API 23 이상을 요구한다.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // AndroidManifest의 AdMob 앱 ID. 기본값은 구글 공식 **테스트** 앱
        // ID이므로, 스토어 배포 빌드는 반드시 실제 값을 넘겨야 한다.
        // `flutter build`는 임의의 Gradle -P 인자를 넘겨주지 않으므로
        // 환경변수를 먼저 본다:  ADMOB_APP_ID=ca-app-pub-XXXX~YYYY flutter build appbundle
        manifestPlaceholders["admobAppId"] =
            System.getenv("ADMOB_APP_ID")
                ?: (project.findProperty("admob_app_id") as String?)
                ?: "ca-app-pub-3940256099942544~3347511713"
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 업로드 키가 준비된 환경에서만 실제 서명한다. 없으면 debug 키로
            // 서명해 `flutter build apk --release`(테스트 배포)가 계속 된다 —
            // 단, debug 키로 서명된 빌드는 Play Store에 올릴 수 없다.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

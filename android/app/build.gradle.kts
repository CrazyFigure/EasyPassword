import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 读取本地签名配置 android/key.properties（该文件不入版本库）。
// CI 环境没有此文件，改由环境变量提供，两者必须指向同一个密钥库，
// 否则不同渠道产出的 APK 签名不一致，用户将无法覆盖安装升级。
val keystoreProperties = Properties().apply {
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

// 优先取 key.properties，其次取环境变量（CI 通过 GitHub Secrets 注入）
fun signingValue(propKey: String, envKey: String): String? =
    keystoreProperties.getProperty(propKey) ?: System.getenv(envKey)

val releaseStoreFile = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseStorePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")

// 四项配置齐全且密钥库文件确实存在时，才启用正式签名
val hasReleaseSigning = releaseStoreFile != null &&
    releaseStorePassword != null &&
    releaseKeyAlias != null &&
    releaseKeyPassword != null &&
    file(releaseStoreFile).exists()

android {
    namespace = "com.easypassword.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.easypassword.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 仅打包 arm64-v8a，避免 fat APK 携带 4 个 ABI 的 Flutter 引擎（体积优化，
        // APK 从约 54MB 降至 15-20MB；不兼容 32 位旧设备）
        ndk {
            abiFilters.add("arm64-v8a")
        }
    }

    signingConfigs {
        // 正式发布签名。缺少密钥库配置时不注册，避免本地开发者拉取代码后构建失败
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                // 同时启用 v1/v2/v3 签名方案，兼顾旧设备与新版 Android 校验
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            // 有正式密钥库就用正式签名；否则回退 debug 签名仅供本地 `flutter run --release`。
            // 注意：debug 签名在 CI 上每次都会重新随机生成，绝不可用于对外发版。
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("警告：未找到 release 签名配置，回退使用 debug 签名，该产物不可用于发布！")
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

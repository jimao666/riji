import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val amapWebApiKey = localProperties.getProperty("amap.web.api.key", "")
val escapedAmapWebApiKey = amapWebApiKey
    .replace("\\", "\\\\")
    .replace("\"", "\\\"")

val qWeatherCredentialId = localProperties.getProperty("qweather.credential_id", "")
val escapedQWeatherCredentialId = qWeatherCredentialId
    .replace("\\", "\\\\")
    .replace("\"", "\\\"")

val qWeatherApiKey = localProperties.getProperty("qweather.api_key", "")
val escapedQWeatherApiKey = qWeatherApiKey
    .replace("\\", "\\\\")
    .replace("\"", "\\\"")

val qWeatherApiHost = localProperties.getProperty("qweather.api_host", "")
val escapedQWeatherApiHost = qWeatherApiHost
    .replace("\\", "\\\\")
    .replace("\"", "\\\"")

android {
    namespace = "com.jotsy.diary"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = "com.jotsy.diary"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        buildConfigField("String", "AMAP_WEB_API_KEY", "\"$escapedAmapWebApiKey\"")
        buildConfigField("String", "QWEATHER_CREDENTIAL_ID", "\"$escapedQWeatherCredentialId\"")
        buildConfigField("String", "QWEATHER_API_KEY", "\"$escapedQWeatherApiKey\"")
        buildConfigField("String", "QWEATHER_API_HOST", "\"$escapedQWeatherApiHost\"")
    }

    signingConfigs {
        create("release") {
            // 仅本地存在 key.properties 才加载签名，CI无此文件则跳过，不会报 null File 错误
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            // CI环境取消强制签名，输出未签名包，后续MT管理器签名
            // signingConfig = signingConfigs.getByName("release")
            proguardFiles("proguard-rules.pro")
        }
        getByName("profile") {
            // profile 同样取消绑定release签名
            // signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.media3:media3-transformer:1.9.2")
    implementation("androidx.media3:media3-effect:1.9.2")
    implementation("androidx.media3:media3-common:1.9.2")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16.1")
}

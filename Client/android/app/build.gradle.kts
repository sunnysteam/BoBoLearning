plugins {
    id("com.android.application")
    // Flutter Gradle 插件必须在 Android 插件之后应用。
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.bobo.learning.bobo_learning"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 应用唯一标识，正式发布后不得随意修改。
        applicationId = "com.bobo.learning.bobo_learning"
        // SDK 版本由当前 Flutter 工具链统一提供。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // 版本号与构建号统一取自 pubspec.yaml。
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // MVP 暂用调试签名验证发布构建，正式上架前必须替换为安全签名。
            signingConfig = signingConfigs.getByName("debug")
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

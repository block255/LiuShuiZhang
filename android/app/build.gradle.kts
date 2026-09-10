import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── 正式签名（2026-09-10）──
// 密钥与口令放在**项目之外**的 D:\Flutter_APP_Develop\签名密钥\ 目录：
// 物理上与源码分离，源码包/打包脚本不可能误带密钥。
// 注意：keystore 路径写在本文件（.kts 按 UTF-8 解析，中文目录名安全）；
//       key.properties 里只放口令与别名（纯 ASCII）——Java 的 Properties.load
//       按 ISO-8859-1 解码，中文路径放进去会乱码。
// 缺失密钥时回退 debug 签名（只为让调试构建不中断；发布脚本会强制校验并拦住）
val keystoreDir = rootProject.file("../../签名密钥")
val keystoreFile = File(keystoreDir, "liushuizhang-release.jks")
val keystorePropsFile = File(keystoreDir, "key.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) {
        FileInputStream(keystorePropsFile).use { load(it) }
    }
}
val hasReleaseKeystore = keystoreFile.exists() && keystorePropsFile.exists()

android {
    namespace = "com.liushuizhang.app"
    compileSdk = flutter.compileSdkVersion
    // 真 NDK（2026-09-10 装）：从**腾讯云镜像**手动安装 r28c = 28.2.13676358（与 Flutter 默认版本一致，
    // 见 FlutterExtension.kt）。作用：AGP 借它的 llvm-strip 裁掉 Flutter 引擎 .so 的调试符号
    // → release 包从 320MB 降到 ~25MB。
    // 历史坑：此前 dl.google.com 不可达，曾用「source.properties 标记 + llvm-strip 复制存根」绕过；
    // 存根只复制不裁剪 → 包虚胖，且空存根会把 .so 全 strip 没导致真机闪退（经验 #34/#36）。
    // 注意：装上真 NDK 后必须删一次 build/app/intermediates/stripped_native_libs，
    // 否则 gradle 判定 up-to-date 不重跑（构建脚本已代劳）。
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.liushuizhang.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 双 ABI：arm64-v8a（荣耀等新机）+ armeabi-v7a（老/32 位机型）→ 通用包，方便发给别人装
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    packaging {
        jniLibs {
            // debug 引擎自带的 Vulkan 校验层（约 237MB，仅调试用途），排除以瘦身
            excludes += "lib/arm64-v8a/libVkLayer_khronos_validation.so"
            excludes += "lib/armeabi-v7a/libVkLayer_khronos_validation.so"
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = keystoreFile
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 有正式密钥 → 用正式签名；没有 → 回退 debug（仅调试用途，发布脚本会拦住）
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
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

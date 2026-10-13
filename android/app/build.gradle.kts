import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The release key: android/key.properties, written by the release workflow
// from repository secrets. Builds without it are signed with the debug key.
val release = Properties().apply {
    rootProject.file("key.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}

android {
    namespace = "org.haneoka.haneoka"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "org.haneoka.haneoka"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (release.containsKey("storeFile")) {
            create("release") {
                storeFile = file(release.getProperty("storeFile"))
                storePassword = release.getProperty("storePassword")
                keyAlias = release.getProperty("keyAlias")
                keyPassword = release.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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

dependencies {
    // Shizuku lends the app the shell user's access to Android/data on Android 11+.
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
    implementation("dev.rikka.shizuku:aidl:13.1.5")
}

val rustOutput = layout.buildDirectory.dir("rust-jni")
android.sourceSets.getByName("main").jniLibs.srcDir(rustOutput)
val rustTriples = mapOf(
    "arm64-v8a" to ("aarch64-linux-android" to "aarch64-linux-android"),
    "armeabi-v7a" to ("armv7-linux-androideabi" to "armv7a-linux-androideabi"),
    "x86_64" to ("x86_64-linux-android" to "x86_64-linux-android"),
)
val rustTasks = rustTriples.map { (abi, triple) ->
    tasks.register<Exec>("buildTeamEngine_${abi.replace('-', '_')}") {
        val source = rootProject.file("../native/team_engine")
        val target = rootProject.file("../build/rust-android")
        inputs.dir(source.resolve("src"))
        inputs.files(source.resolve("Cargo.toml"), source.resolve("Cargo.lock"))
        val destination = rustOutput.map { it.file("$abi/libhaneoka_team_engine.so") }
        outputs.file(destination)
        doFirst {
            val local = Properties().apply {
                rootProject.file("local.properties").inputStream().use { load(it) }
            }
            val sdk = System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT") ?: local.getProperty("sdk.dir")
            val host = when {
                System.getProperty("os.name").startsWith("Mac") -> "darwin-x86_64"
                System.getProperty("os.name").startsWith("Windows") -> "windows-x86_64"
                else -> "linux-x86_64"
            }
            val suffix = if (host.startsWith("windows")) ".cmd" else ""
            val linker = file("$sdk/ndk/${android.ndkVersion}/toolchains/llvm/prebuilt/$host/bin/${triple.second}26-clang$suffix")
            check(linker.exists()) { "Rust team engine needs Android NDK ${android.ndkVersion}: $linker" }
            environment("CARGO_TARGET_${triple.first.uppercase().replace('-', '_')}_LINKER", linker.absolutePath)
            commandLine("cargo", "build", "--release", "--locked", "--manifest-path", source.resolve("Cargo.toml"), "--target", triple.first, "--target-dir", target)
        }
        doLast {
            copy {
                from(target.resolve("${triple.first}/release/libhaneoka_team_engine.so"))
                into(destination.get().asFile.parentFile)
            }
        }
    }
}
tasks.named("preBuild") { dependsOn(rustTasks) }

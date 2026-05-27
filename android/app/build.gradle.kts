plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sst.sstcam"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.sst.sstcam"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // flutter_vlc_player and ffmpeg_kit_flutter_new both ship libc++_shared.so.
            pickFirsts += "**/*.so"
        }
    }
}

flutter {
    source = "../.."
}

// Patch GeneratedPluginRegistrant.java to use catch (Throwable) instead of
// catch (Exception). Flutter generates the file with `catch (Exception e)`,
// which does NOT catch java.lang.Error subclasses such as UnsatisfiedLinkError.
// On Android 16 x86_64, FFmpegKit throws an UnsatisfiedLinkError (missing
// libc++ symbol in libavfilter.so). That Error escapes the try-catch, aborts
// registerWith(), and leaves every subsequent plugin unregistered (path_provider,
// shared_preferences, sqlite3, …). Catching Throwable isolates the failure to
// FFmpegKit so all other plugins still register. Remove this patch once upstream
// fixes the generated catch clause or FFmpegKit supports Android 16.
val patchGeneratedPluginRegistrant by tasks.registering {
    val generatedFile = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
    doLast {
        if (generatedFile.exists()) {
            val original = generatedFile.readText()
            val patched = original.replace("} catch (Exception e) {", "} catch (Throwable e) {")
            if (patched != original) {
                generatedFile.writeText(patched)
                logger.lifecycle("Patched GeneratedPluginRegistrant.java: catch (Throwable)")
            }
        }
    }
}

tasks.configureEach {
    if (name.startsWith("compile") && name.endsWith("JavaWithJavac")) {
        dependsOn(patchGeneratedPluginRegistrant)
    }
}

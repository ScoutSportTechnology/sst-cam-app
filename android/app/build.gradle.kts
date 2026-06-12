import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is driven by android/key.properties, which is gitignored and
// materialized in CI from secrets (see .github/workflows/release.yml). When the
// file is absent (typical local dev), release builds fall back to the debug key
// so `flutter run --release` and local smoke builds keep working without secrets.
// See android/key.properties.example for the expected keys.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
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

    signingConfigs {
        // Only declared when key.properties is present (CI / a configured local
        // machine). Reading absent properties would NPE on storeFile, so guard it.
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the real release signing config when key.properties exists,
            // otherwise fall back to the debug key so local release builds work
            // without secrets. CI always provides key.properties (from secrets).
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // TODO (open item, see plan U4 / Open Questions): the `developer`
            // (APP_ENV=stage) and `production` APKs currently share applicationId
            // "com.sst.sstcam", so they cannot be installed side-by-side on one
            // device. If side-by-side install is required, give the developer
            // build an `applicationIdSuffix = ".dev"`. Deferred — adding it here
            // unconditionally would also suffix the production build, and the
            // app has no Gradle product flavors to scope it to. Revisit when the
            // build variant strategy is finalized.
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

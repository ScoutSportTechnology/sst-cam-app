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
        // Default manifest label; product flavors override per variant. Keeps a
        // flavor-less build resolvable, though Flutter requires --flavor once
        // flavors exist (see justfile).
        manifestPlaceholders["appName"] = "SST Cam"
    }

    // Three variants — one per env — distinguished at the Android level so they
    // install side-by-side, are told apart at a glance (distinct icon + name),
    // and pair 1:1 with the single entry's compile-time APP_ENV (which selects
    // backend + tooling in Dart). The flavor here only controls applicationId,
    // app name, and launcher icon:
    //   dev   → com.sst.sstcam.dev     "SST Cam Dev"     (APP_ENV=dev,  mock backend)
    //   stage → com.sst.sstcam.stage   "SST Cam Stage"   (APP_ENV=stage, real + tools)
    //   prod  → com.sst.sstcam         "SST Cam"         (APP_ENV=prod, shipped)
    flavorDimensions += "variant"
    productFlavors {
        create("dev") {
            dimension = "variant"
            applicationIdSuffix = ".dev"
            manifestPlaceholders["appName"] = "SST Cam Dev"
        }
        create("stage") {
            dimension = "variant"
            applicationIdSuffix = ".stage"
            manifestPlaceholders["appName"] = "SST Cam Stage"
        }
        create("prod") {
            dimension = "variant"
            manifestPlaceholders["appName"] = "SST Cam"
        }
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
            // Variant identity (applicationId suffix, app name, icon) is handled
            // by the dev/prod product flavors above.
            //
            // R8 disabled on release so the shipped dex matches what `flutter run`
            // (debug, never minified) produces — no build-type divergence. R8's
            // tree-shaking removed JNI-only classes (libVLC's
            // org.videolan.libvlc.interfaces.IMedia$Track, referenced solely via
            // native FindClass) ONLY in release, so libVLC called System.exit(1)
            // and the app closed on Live Preview while debug worked. Keeping R8
            // off is the simplest guarantee of local==CI behaviour; the VLC libs
            // dominate APK size, so the dex shrink R8 offered is negligible here.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        jniLibs {
            // flutter_vlc_player and ffmpeg_kit_flutter_new both ship libc++_shared.so.
            pickFirsts += "**/*.so"
            // Store native libs uncompressed so AGP 16KB-zip-aligns them in the
            // APK (Android 15+ 16KB page-size support). This fixes the APK-level
            // alignment for every .so we control; the residual "LOAD segment not
            // aligned" on the prebuilt libVLC (.so from the pinned
            // flutter_vlc_player 7.4.3) is baked into those binaries and can only
            // be fixed by a newer plugin shipping 16KB-built libs, not from here.
            useLegacyPackaging = false
        }
    }
}

flutter {
    source = "../.."
}

// Patch the Flutter-generated GeneratedPluginRegistrant.java before javac. Two
// fixes, both because Flutter emits registrations that don't survive a RELEASE
// compile:
//
//  1. Strip the integration_test registration block. `integration_test` is a
//     dev_dependency, so its Android plugin class
//     (dev.flutter.plugins.integration_test.IntegrationTestPlugin) is on the
//     classpath only for debug/androidTest — NOT release. Flutter still writes its
//     registration into the registrant, so a release build fails to compile with
//     "package dev.flutter.plugins.integration_test does not exist". The plugin is
//     only needed by `flutter test integration_test/` (which runs its own debug
//     build), never in a shipped APK, so removing the block is safe.
//
//  2. catch (Exception) -> catch (Throwable). Exception does NOT catch
//     java.lang.Error subclasses (e.g. UnsatisfiedLinkError from a native lib that
//     fails to dlopen). Such an Error escaping registerWith() aborts registration
//     and leaves every SUBSEQUENT plugin unregistered (path_provider, sqlite3, …).
//     Throwable isolates a failing plugin so the rest still register.
//
// Applied as a doFirst on the Java compile task (not a separate dependsOn task) so
// it runs immediately before javac — after Flutter has generated/regenerated the
// file — leaving no window for a regeneration to clobber the patch.
fun patchGeneratedPluginRegistrant(logger: org.gradle.api.logging.Logger) {
    val generatedFile = file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")
    if (!generatedFile.exists()) return
    val original = generatedFile.readText()
    var patched = original.replace("} catch (Exception e) {", "} catch (Throwable e) {")
    // Remove the whole try/catch block that registers IntegrationTestPlugin.
    patched = patched.replace(
        Regex(
            """ *try \{\s*flutterEngine\.getPlugins\(\)\.add\(new dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin\(\)\);\s*\} catch \((?:Exception|Throwable) e\) \{\s*Log\.e\([^;]*\);\s*\}\R?"""
        ),
        ""
    )
    if (patched != original) {
        generatedFile.writeText(patched)
        logger.lifecycle("Patched GeneratedPluginRegistrant.java (strip integration_test + catch Throwable)")
    }
}

tasks.configureEach {
    if (name.startsWith("compile") && name.endsWith("JavaWithJavac")) {
        doFirst { patchGeneratedPluginRegistrant(logger) }
    }
}

import java.util.Properties
import java.io.FileInputStream
import com.android.build.api.dsl.ApplicationExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.schlick7.luteformobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin", "src/main/java")
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file("$it") }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    defaultConfig {
        applicationId = "com.schlick7.luteformobile"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}

flutter {
    source = "../.."
}

afterEvaluate {
    tasks.matching { it.name.startsWith("compile") && it.name.endsWith("JavaWithJavac") }.configureEach {
        val javaTask = this as JavaCompile
        val variantName = javaTask.name.removePrefix("compile").removeSuffix("JavaWithJavac")
        val varLower = variantName.lowercase()
        val varCap = varLower.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }

        rootProject.subprojects.filter { it.name != "app" }.forEach { sub ->
            javaTask.dependsOn(sub.tasks.matching { 
                it.name.contains("Kotlin") || it.name.startsWith("compile") || it.name.startsWith("bundle") || it.name.startsWith("sync") || it.name.startsWith("assemble")
            })
        }

        javaTask.doFirst {
            val subDirs = rootProject.subprojects.filter { it.name != "app" }.flatMap { sub ->
                val bDir = sub.layout.buildDirectory.asFile.get()
                listOf(
                    File(bDir, "tmp/kotlin-classes/$varLower"),
                    File(bDir, "tmp/kotlin-classes/debug"),
                    File(bDir, "tmp/kotlin-classes/release"),
                    File(bDir, "intermediates/kotlin-classes/$varLower"),
                    File(bDir, "intermediates/kotlin-classes/debug"),
                    File(bDir, "intermediates/kotlin-classes/release"),
                    File(bDir, "intermediates/compile_library_classes_jar/$varLower/bundleLibCompileToJar$varCap/classes.jar"),
                    File(bDir, "intermediates/compile_library_classes_jar/debug/bundleLibCompileToJarDebug/classes.jar"),
                    File(bDir, "intermediates/compile_library_classes_jar/release/bundleLibCompileToJarRelease/classes.jar")
                )
            }.filter { it.exists() }

            javaTask.classpath = javaTask.classpath + files(subDirs)
        }
    }
}

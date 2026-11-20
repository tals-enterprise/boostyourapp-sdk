import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.boostyourapp.sample"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.boostyourapp.sample"
        minSdk = 21
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // Serveur et clé de test, passés par -Psample.apiUrl=… -Psample.appKey=… (sinon ceux du SDK)
        buildConfigField("String", "API_URL", "\"${providers.gradleProperty("sample.apiUrl").orElse(providers.gradleProperty("boost.apiUrl")).get()}\"")
        buildConfigField("String", "API_KEY", "\"${providers.gradleProperty("sample.apiKey").orElse(providers.gradleProperty("boost.apiKey")).get()}\"")
        buildConfigField("String", "APP_KEY", "\"${providers.gradleProperty("sample.appKey").orElse("bya_REPLACE_ME").get()}\"")
        testInstrumentationRunnerArguments["appKey"] = providers.gradleProperty("sample.appKey").orElse("").get()
    }

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
    }
}

dependencies {
    implementation(project(":network"))

    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test:core:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
}

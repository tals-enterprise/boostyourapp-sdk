import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    `maven-publish`
}

android {
    namespace = "com.boostyourapp.network"
    compileSdk = 36

    defaultConfig {
        // Android 5.0 : couvre la quasi-totalité du parc
        minSdk = 21
        consumerProguardFiles("consumer-rules.pro")
        // URL, clé et version : Config.kt, généré depuis gradle.properties par sdk/scripts/sync.mjs
        // (les plugins Capacitor, Cordova et React Native embarquent les mêmes sources)
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    // Publication Maven (JitPack) : AAR de la variante release, avec ses sources
    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

// Coordonnées fournies par JitPack (voir sdk/jitpack.yml) ; à défaut, celles du dépôt public et la version
// de gradle.properties (./gradlew :network:publishToMavenLocal pour un essai local)
afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components["release"])
                groupId = providers.gradleProperty("boost.group").orNull ?: "com.github.tals-enterprise"
                artifactId = providers.gradleProperty("boost.artifact").orNull ?: "boostyourapp-sdk"
                version = providers.gradleProperty("boost.publishVersion").orNull
                    ?: providers.gradleProperty("boost.version").get()
                pom {
                    name.set("BoostYourApp SDK")
                    description.set("Bannière du réseau d'échange de pubs BoostYourApp")
                    url.set("https://github.com/tals-enterprise/boostyourapp-sdk")
                    licenses {
                        license {
                            name.set("MIT")
                            url.set("https://opensource.org/licenses/MIT")
                        }
                    }
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
    }
}

dependencies {
    // Aucune dépendance à l'exécution en dehors de la librairie standard Kotlin
    testImplementation("junit:junit:4.13.2")
    // org.json n'existe que sous forme de bouchons dans android.jar : vraie implémentation pour les tests JVM
    testImplementation("org.json:json:20240303")
}

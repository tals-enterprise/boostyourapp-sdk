pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "boostyourapp-android"

// network : la librairie (cœur du SDK) ; sample : app de démonstration et de test de bout en bout
include(":network", ":sample")

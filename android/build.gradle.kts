allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Every Android module - :app and each Flutter plugin, notably :opencv_core, which
// compiles OpenCV through CMake - must agree on one NDK. Plugins that leave
// ndkVersion unset otherwise fall back to flutter.ndkVersion (27.0.12077973) and
// trigger a fresh ~700MB download.
//
// Hooked on plugin application rather than afterEvaluate: the evaluationDependsOn(":app")
// block below forces evaluation, so afterEvaluate would be rejected as too late.
// Reflection is used because the AGP extension type is not on the root classpath.
val pinnedNdkVersion = "28.2.13676358"

subprojects {
    listOf("com.android.application", "com.android.library").forEach { pluginId ->
        plugins.withId(pluginId) {
            val androidExtension = extensions.findByName("android")
            if (androidExtension != null) {
                runCatching {
                    androidExtension.javaClass
                        .getMethod("setNdkVersion", String::class.java)
                        .invoke(androidExtension, pinnedNdkVersion)
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

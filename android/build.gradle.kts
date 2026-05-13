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
    
    // F-Droid: Completely exclude non-free Google Play Core modules
    configurations.all {
        exclude(group = "com.google.android.play")
        resolutionStrategy {
            eachDependency {
                if (requested.group == "com.google.android.play") {
                    useTarget("androidx.annotation:annotation:1.5.0")
                }
            }
            dependencySubstitution {
                substitute(module("com.google.android.play:core")).using(module("androidx.annotation:annotation:1.5.0"))
                substitute(module("com.google.android.play:core-common")).using(module("androidx.annotation:annotation:1.5.0"))
                substitute(module("com.google.android.play:review")).using(module("androidx.annotation:annotation:1.5.0"))
                substitute(module("com.google.android.play:app-update")).using(module("androidx.annotation:annotation:1.5.0"))
                substitute(module("com.google.android.play:feature-delivery")).using(module("androidx.annotation:annotation:1.5.0"))
                substitute(module("com.google.android.play:integrity")).using(module("androidx.annotation:annotation:1.5.0"))
                substitute(module("com.google.android.play:tasks")).using(module("androidx.annotation:annotation:1.5.0"))
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

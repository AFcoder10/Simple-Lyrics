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
    
    // F-Droid: Globally exclude non-free Google Play Core modules from all subprojects (plugins)
    configurations.all {
        exclude(group = "com.google.android.play")
        exclude(group = "com.google.android.play", module = "core")
        exclude(group = "com.google.android.play", module = "core-common")
        exclude(group = "com.google.android.play", module = "review")
        exclude(group = "com.google.android.play", module = "app-update")
        exclude(group = "com.google.android.play", module = "feature-delivery")
        exclude(group = "com.google.android.play", module = "integrity")
        exclude(group = "com.google.android.play", module = "tasks")
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

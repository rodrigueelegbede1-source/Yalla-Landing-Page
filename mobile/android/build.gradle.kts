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
// Contournement temporaire : le plugin file_picker (8.3.7, dernière version
// compatible avec notre contrainte ^8.1.7) déclare lui-même, dans son propre
// build.gradle, un compileSdk 34, alors que flutter_plugin_android_lifecycle
// 2.0.34 exige 36 ou plus. Sans ce bloc, Gradle refuse de construire avec
// « CheckAarMetadataWorkAction : must compile against version 36 ». On force
// donc le compileSdk de tous les modules Android des plugins à 36 après leur
// propre évaluation (`afterEvaluate`, pour gagner sur la valeur que le script
// du plugin fixe lui-même), sauf `:app` qui le déclare déjà correctement et
// est évalué en avance à cause de `evaluationDependsOn` plus bas.
// À retirer si file_picker publie une version déjà compilée contre 36+.
subprojects {
    if (project.name != "app") {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let {
                it.compileSdk = 36
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

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

// agora_rtc_engine gibi bazı eklenti modülleri compileSdk 34+ ister; Flutter'ın
// varsayılan değeri (31) bazılarına yetmiyor. Tüm Android alt modüllerini 36'ya
// çekerek "currently compiled against android-31" hatasını çözeriz.
// NOT: afterEvaluate, aşağıdaki evaluationDependsOn'DAN ÖNCE register edilmeli;
// aksi halde modül erken değerlendirilip "already evaluated" hatası verir.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            if (ext is com.android.build.gradle.BaseExtension) {
                ext.compileSdkVersion(36)
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

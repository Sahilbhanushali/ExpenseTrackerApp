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
subprojects {
    project.evaluationDependsOn(":app")
}

// Some plugins (e.g. receive_sharing_intent) declare an older Java target
// than the Kotlin target for their own compile tasks, which AGP now treats
// as a hard error ("Inconsistent JVM Target Compatibility"). Force every
// module — app and plugins alike — onto the same JVM 17 target the app
// itself already uses, rather than patching each offending plugin.
subprojects {
    // ":app" already declares JVM 17 itself and is evaluated early (see
    // evaluationDependsOn above), so it's skipped here — mutating its
    // compileOptions after evaluation throws. Plugin subprojects (e.g.
    // receive_sharing_intent) evaluate normally later, so afterEvaluate
    // here runs after AGP applies its own (often older) default and wins.
    if (name != "app") {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)
                ?.apply {
                    compileOptions {
                        sourceCompatibility = JavaVersion.VERSION_17
                        targetCompatibility = JavaVersion.VERSION_17
                    }
                }
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

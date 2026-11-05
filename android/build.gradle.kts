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

subprojects {
    if (project.name != "app") {
        afterEvaluate {
            val android = project.extensions.findByName("android") ?: return@afterEvaluate
            for (method in android.javaClass.methods) {
                if (method.name in listOf("setCompileSdk", "setCompileSdkVersion", "compileSdkVersion")) {
                    try {
                        if (method.parameterTypes.size == 1) {
                            val paramType = method.parameterTypes[0]
                            if (paramType == Int::class.javaPrimitiveType || paramType == java.lang.Integer::class.java) {
                                method.invoke(android, 36)
                            }
                        }
                    } catch (_: Exception) {}
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

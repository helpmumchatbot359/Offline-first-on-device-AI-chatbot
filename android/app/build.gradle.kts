import java.io.File

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Safely resolve the handoff package directory if passed via command line
val handoffDirVal: File? = if (project.hasProperty("handoffPackageDir")) {
    file(project.property("handoffPackageDir") as String)
} else {
    null
}

val toolContractAssetDir = layout.buildDirectory.dir("generated/tool-contract-assets")
val localPackageDir = file("../package")
val localToolContract = File(localPackageDir, "contracts/tool_contract.json")
val localSystemPrompt = File(localPackageDir, "prompts/system_prompt.txt")

val packagedToolContract = handoffDirVal?.let { File(it, "contracts/tool_contract.json") }
val packagedSystemPrompt = handoffDirVal?.let { File(it, "prompts/system_prompt.txt") }

val toolContractSource = when {
    localToolContract.isFile -> localToolContract
    packagedToolContract?.isFile == true -> packagedToolContract!!
    else -> localToolContract
}

val systemPromptSource = when {
    localSystemPrompt.isFile -> localSystemPrompt
    packagedSystemPrompt?.isFile == true -> packagedSystemPrompt!!
    else -> localSystemPrompt
}

val prepareToolContractAsset = tasks.register<Copy>("prepareToolContractAsset") {
    from(toolContractSource)
    from(systemPromptSource)
    into(toolContractAssetDir)
}

android {
    namespace = "com.example.mama_ai"
    compileSdk = 36
    buildToolsVersion = "35.0.0"
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.mama_ai"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    // CORRECTED PATHS pointing inside android/app/src/main/ where your files actually live
    sourceSets {
        getByName("main") {
            manifest.srcFile("src/main/AndroidManifest.xml")
            java.srcDir("src/main/java")
            assets.srcDir(toolContractAssetDir.get().asFile)
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(21))
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
    }
}

tasks.named("preBuild").configure {
    dependsOn(prepareToolContractAsset)
}

dependencies {
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.18.0")
    implementation("androidx.sqlite:sqlite-bundled:2.7.1")
    implementation("com.google.code.gson:gson:2.10.1")
    implementation("org.jetbrains.kotlin:kotlin-stdlib:2.1.20")
    implementation("com.tom-roush:pdfbox-android:2.0.27.0")
}
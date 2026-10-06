plugins {
    id("com.android.application")
}

android {
    namespace = "net.appbuilder.shell"
    compileSdk = {{COMPILE_SDK}}

    defaultConfig {
        applicationId = "{{APPLICATION_ID}}"
        minSdk = {{MIN_SDK}}
        targetSdk = {{TARGET_SDK}}
        versionCode = {{VERSION_CODE}}
        versionName = "{{VERSION_NAME}}"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    androidResources {
        // Keep folders such as _next/ and dotfiles that the default pattern drops.
        ignoreAssetsPattern = "!.svn:!.git:!.ds_store:!*.scc:!CVS:!thumbs.db:!picasa.ini:!*~"
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

dependencies {
    implementation("{{WEBKIT_DEPENDENCY}}")
    implementation("{{CORE_DEPENDENCY}}")
}

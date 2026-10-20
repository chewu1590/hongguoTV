import java.util.Properties

plugins { id("com.android.application"); kotlin("android") }
val signingProperties = Properties().apply { val config = rootProject.file("keystore.properties"); if (config.exists()) config.inputStream().use { load(it) } }
fun signingValue(env: String, key: String): String? = System.getenv(env) ?: signingProperties.getProperty(key)

android {
    namespace = "com.hongguotv.nativeapp"
    compileSdk = 36
    // 品牌信息：都可用环境变量覆盖，不必改代码
    //   HONGGUOTV_APP_LABEL     桌面/设置里显示的应用名
    //   HONGGUOTV_BRAND_SHORT   标题栏品牌短名
    //   HONGGUOTV_BRAND_ACCENT  强调色（#RRGGBB）
    val brandLabel = System.getenv("HONGGUOTV_APP_LABEL") ?: "红果TV 定制版"
    val brandShort = System.getenv("HONGGUOTV_BRAND_SHORT") ?: "红果"
    val brandAccent = System.getenv("HONGGUOTV_BRAND_ACCENT") ?: "#2FD3C0"
    defaultConfig {
        // 定制版：与官方 com.hongguotv.nativeapp 隔离，可同机共存，互不覆盖。
        // 需要别的包名时用 HONGGUOTV_APPLICATION_ID 覆盖，不必改代码。
        applicationId = System.getenv("HONGGUOTV_APPLICATION_ID") ?: "com.hongguotv.custom"
        minSdk = 26
        targetSdk = 36
        versionCode = System.getenv("HONGGUOTV_VERSION_CODE")?.toInt() ?: 9
        versionName = System.getenv("HONGGUOTV_VERSION_NAME") ?: "0.9.0-custom"
        // 定制版不追踪官方 release：置 true 才会恢复自动更新检查。
        buildConfigField("boolean", "CHECK_UPDATES", (System.getenv("HONGGUOTV_CHECK_UPDATES") ?: "false"))
        manifestPlaceholders["appLabel"] = brandLabel
        buildConfigField("String", "APP_LABEL", "\"$brandLabel\"")
        buildConfigField("String", "BRAND_SHORT", "\"$brandShort\"")
        buildConfigField("String", "BRAND_ACCENT", "\"$brandAccent\"")
    }
    buildFeatures { buildConfig = true }
    signingConfigs {
        create("delivery") {
            storeFile = signingValue("HONGGUOTV_KEYSTORE", "storeFile")?.let { file(it) }
            storePassword = signingValue("HONGGUOTV_STORE_PASSWORD", "storePassword")
            keyAlias = signingValue("HONGGUOTV_KEY_ALIAS", "keyAlias")
            keyPassword = signingValue("HONGGUOTV_KEY_PASSWORD", "keyPassword")
        }
    }
    buildTypes { getByName("release") { signingConfig = signingConfigs.getByName("delivery"); isMinifyEnabled = true; proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro") } }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17; isCoreLibraryDesugaringEnabled = true }
    kotlinOptions { jvmTarget = "17" }
    packaging { resources.excludes += setOf("META-INF/versions/**", "META-INF/*.kotlin_module") }
}
dependencies {
    implementation("androidx.core:core:1.8.0")
    implementation("com.google.zxing:core:3.5.3")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs_nio:2.1.5")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation(project(":core")) { exclude(group = "org.json") }
    implementation("androidx.media3:media3-exoplayer:1.8.0")
    implementation("androidx.media3:media3-ui:1.8.0")
}

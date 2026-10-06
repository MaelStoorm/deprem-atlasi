import javax.inject.Inject

plugins {
    id("com.android.application")
}

/*
 * Sitenin dosyaları (index.html, gizlilik.html, manifest, simgeler, yazı tipi ve ileride eklenecek
 * veri dosyaları) her derlemede depo kökünden uygulamanın içine (assets/site) kopyalanır.
 * Böylece uygulama her zaman sitenin son halini taşır; kopya elle güncellenmez.
 * sw.js bilerek alınmaz: uygulamada dosyalar zaten telefonda olduğu için önbellek katmanına gerek yok.
 */
abstract class SiteyiKopyala : DefaultTask() {
    @get:Internal
    abstract val siteKoku: DirectoryProperty

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    val siteDosyalari: FileTree
        get() = siteKoku.get().asFileTree.matching {
            include(
                "**/*.html", "**/*.webmanifest", "**/*.json", "**/*.geojson", "**/*.topojson",
                "**/*.js", "**/*.mjs", "**/*.css", "**/*.csv", "**/*.txt",
                "**/*.png", "**/*.jpg", "**/*.jpeg", "**/*.webp", "**/*.gif", "**/*.svg", "**/*.ico",
                "**/*.ttf", "**/*.otf", "**/*.woff", "**/*.woff2"
            )
            exclude("android/**", ".github/**", "**/node_modules/**", "sw.js")
        }

    @get:OutputDirectory
    abstract val hedef: DirectoryProperty

    @get:Inject
    abstract val dosyaIslemleri: FileSystemOperations

    @TaskAction
    fun kopyala() {
        dosyaIslemleri.sync {
            from(siteDosyalari) { into("site") }
            into(hedef)
        }
        check(hedef.get().file("site/index.html").asFile.isFile) {
            "index.html bulunamadı: site dosyaları uygulamaya kopyalanamadı"
        }
    }
}

android {
    namespace = "com.maelstorm.deprematlasi"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.maelstorm.deprematlasi"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            // İmza ayarı bilerek yok: AAB imzasız derlenir, imzalama sahibinin kendi anahtarıyla yapılır.
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

androidComponents {
    onVariants { variant ->
        val gorev = tasks.register<SiteyiKopyala>("${variant.name}SiteyiKopyala") {
            siteKoku.set(rootProject.layout.projectDirectory.dir(".."))
        }
        variant.sources.assets?.addGeneratedSourceDirectory(gorev, SiteyiKopyala::hedef)
    }
}

dependencies {
    implementation("androidx.activity:activity:1.10.1")
    implementation("androidx.core:core:1.15.0")
    implementation("androidx.webkit:webkit:1.12.1")
}

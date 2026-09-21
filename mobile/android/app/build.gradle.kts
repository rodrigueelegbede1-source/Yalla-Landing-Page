import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La clé de signature, lue dans `android/key.properties`, lui-même ignoré par
// Git et généré depuis le `.env` par `scripts/preparer-signature.sh`.
//
// POURQUOI ÇA COMPTE PLUS QU'IL N'Y PARAÎT. Android identifie une application
// par son couple (identifiant, signature). Deux APK du même identifiant signés
// par des clés différentes sont deux applications étrangères l'une à l'autre :
// la mise à jour échoue, et il faut désinstaller, ce qui efface les données du
// téléphone. Tant que l'APK était signé par la clé de débogage, générée
// localement et différente sur chaque machine, chaque reconstruction depuis un
// autre poste aurait obligé chaque boutiquier à désinstaller. Pendant un pilote
// qui dure des semaines et se met à jour souvent, c'est rédhibitoire.
//
// Le fichier .jks vit hors du dépôt. Le perdre interdit définitivement toute
// mise à jour des installations existantes : à sauvegarder comme un acte
// notarié, pas comme un fichier de build.
val proprietesSignature = Properties().apply {
    val fichier = rootProject.file("key.properties")
    if (fichier.exists()) fichier.inputStream().use { load(it) }
}
val signatureDisponible = proprietesSignature.getProperty("storeFile") != null

android {
    namespace = "ci.yalla.yalla_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // `ci.yalla.app` et non le `ci.yalla.yalla_mobile` généré par défaut :
        // c'est l'identité de l'application sur le téléphone, et elle ne se
        // change plus une fois distribuée sans imposer une désinstallation à
        // chaque boutiquier. Rien n'étant encore installé nulle part, c'est le
        // seul moment où le corriger est gratuit.
        applicationId = "ci.yalla.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Deux architectures, pas trois.
        //
        // Un APK universel embarque le moteur Flutter compilé pour chaque
        // architecture, soit environ 18 Mo par jeu. En incluant x86_64, le
        // fichier atteint 57 Mo, ce qui dépasse la limite d'hébergement et
        // surtout fait payer au boutiquier 20 Mo de données pour du code
        // qu'aucun téléphone n'exécutera : x86_64 ne sert qu'aux émulateurs de
        // développement.
        //
        // `arm64-v8a` couvre tous les téléphones récents, `armeabi-v7a` les
        // appareils d'entrée de gamme plus anciens, encore très présents à
        // Abidjan. Les deux réunis couvrent le parc réel.
        //
        // Pour installer sur un émulateur pendant le développement, compiler
        // avec `--target-platform android-x64`, qui outrepasse ce filtre.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    signingConfigs {
        if (signatureDisponible) {
            create("production") {
                storeFile = file(proprietesSignature.getProperty("storeFile"))
                storePassword = proprietesSignature.getProperty("storePassword")
                keyAlias = proprietesSignature.getProperty("keyAlias")
                keyPassword = proprietesSignature.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Sans `key.properties`, on retombe sur la clé de débogage plutôt que
            // d'échouer : un développeur qui clone le dépôt doit pouvoir compiler
            // sans détenir la clé de production. L'APK produit est alors utilisable
            // pour essayer, jamais pour distribuer, et la ligne affichée à la
            // compilation le dit.
            signingConfig = if (signatureDisponible) {
                signingConfigs.getByName("production")
            } else {
                logger.warn(
                    "\n  ATTENTION : key.properties absent, APK signé avec la clé de " +
                    "débogage.\n  Ne pas distribuer : la mise à jour échouerait chez " +
                    "l'utilisateur.\n  Pour signer correctement : bash scripts/preparer-signature.sh\n"
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

# Maintenance du SDK

Ce dossier est développé dans le dépôt privé de BoostYourApp (dossier `sdk/`) et publié tel quel, sans
historique, dans le dépôt public https://github.com/tals-enterprise/boostyourapp-sdk.

Toute la logique vit dans deux cœurs natifs (`android/network`, `ios/Sources/BoostNetwork`) ; les plugins ne
font que transmettre les appels.

| Dossier | Contenu | Vérifié |
|---|---|---|
| `android` | Cœur Android (Kotlin, sans dépendance) et app de démonstration | Tests JVM, émulateur de bout en bout |
| `ios` + `Package.swift` | Cœur iOS (Swift Package) | Non compilé ici (pas de Mac) : à compiler sur Mac ou Appflow |
| `capacitor` | Plugin Capacitor 8 | Android : app Capacitor sur émulateur, de bout en bout |
| `cordova` | Plugin Cordova | Android : app Cordova (cordova-android 14) sur émulateur |
| `react-native` | Module React Native et config plugin Expo | Android : compilé contre React Native 0.88 ; pas d'app de test |

## Synchronisation

`android/gradle.properties` est la seule source de l'URL et de la clé publique de l'API du réseau, et de la
version du SDK (`boost.version`). Le script `scripts/sync.mjs` :

1. génère `Config.kt` (Android) et `Config.swift` (iOS) à partir de ces valeurs, et aligne la version des
   paquets npm ;
2. copie les cœurs dans les plugins : sources Kotlin et Swift pour Capacitor et React Native, AAR Android
   et sources Swift pour Cordova (la liste des fichiers de `plugin.xml` est régénérée).

```bash
node scripts/sync.mjs                 # tout
node scripts/sync.mjs capacitor       # un plugin
node scripts/sync.mjs --config        # configuration seule
```

Les copies ne sont pas versionnées. `npm pack` et `npm publish` lancent la synchronisation (script `prepack`).

Les plugins embarquent les sources Swift du cœur plutôt qu'un XCFramework : aucun binaire à construire et
signer sur Mac, et le même code sert à Swift Package Manager et à CocoaPods.

## Publier une version

Les versions sont des tags sans préfixe (`0.1.0`, `0.2.0`…), identiques à `boost.version`.

1. Augmenter `boost.version` dans `android/gradle.properties`, puis `node scripts/sync.mjs --config`.
2. Commiter dans le dépôt privé.
3. Depuis la racine du dépôt privé : `deploy/sdk/release.sh`. Le script copie `sdk/` dans le dépôt public,
   commite, pose le tag et pousse après confirmation.

Le tag déclenche :

| Canal | Mécanisme |
|---|---|
| npm (`@tals-enterprise/boostyourapp-capacitor`, `@tals-enterprise/boostyourapp-cordova`, `@tals-enterprise/boostyourapp-react-native`) | GitHub Action `.github/workflows/publish.yml` (secret `NPM_TOKEN`) |
| Android natif | JitPack construit la librairie à la première demande du tag (`jitpack.yml`) |
| iOS natif | Swift Package Manager lit directement le tag (`Package.swift` à la racine) |

Une fois publiée, une version npm ne peut plus être republiée : en cas d'erreur, publier la version suivante.

Essai local de la publication Android : `cd android && ./gradlew :network:publishToMavenLocal`
(`~/.m2/repository/com/github/tals-enterprise/boostyourapp-sdk/<version>`).

## Tests

```bash
cd android && ./gradlew :network:testDebugUnitTest     # tests JVM : contrat de l'API, file, visibilité
swift test                                            # sur Mac, à la racine : logique et contrat de l'API
```

Test de bout en bout : le serveur `supabase/tests/sdk-test-server.mjs` du dépôt privé imite l'API REST du
réseau sur PGlite, avec les vraies migrations. Depuis l'émulateur Android : `http://10.0.2.2:8787`, clé
`test-key`, appKey `bya_e2etesthost`. Côté plugin :

```js
await BoostNetwork.setEndpoint('http://10.0.2.2:8787', 'test-key');
await BoostNetwork.init('bya_e2etesthost');
await BoostNetwork.showBanner('bottom');
```

Le serveur est en HTTP : l'app de test doit autoriser le trafic en clair (`android:usesCleartextTraffic`).

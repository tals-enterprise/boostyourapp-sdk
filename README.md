# SDK BoostYourApp

Affichez la bannière du réseau BoostYourApp dans votre app : en échange, la pub de votre propre app est
diffusée dans les autres apps du réseau. Le SDK pose une bannière native en haut ou en bas de l'écran et
réduit d'autant le contenu de votre app : rien n'est masqué.

- Android 5.0+ et iOS 13+ (Capacitor : Android 7+, iOS 15+).
- Aucune dépendance, aucun identifiant publicitaire : ni fenêtre ATT sur iOS, ni permission `AD_ID` sur Android.
- La même API sur toutes les technos.

**Avant de commencer** : ajoutez votre app sur [boostyourapp.tals.app](https://boostyourapp.tals.app). Sa clé
(`bya_…`) se trouve dans l'onglet Intégration de la fiche de l'app.

## Installation

### Android (Kotlin, Java)

Dans `settings.gradle.kts`, ajoutez le dépôt JitPack :

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io")
    }
}
```

Puis la dépendance, dans le `build.gradle.kts` de l'app :

```kotlin
implementation("com.github.tals-enterprise:boostyourapp-sdk:0.1.0")
```

Guide complet : [android/README.md](android/README.md).

### iOS (Swift, Objective-C)

Xcode › **File › Add Package Dependencies…**, URL `https://github.com/tals-enterprise/boostyourapp-sdk`,
produit **BoostNetwork**. Ou dans un `Package.swift` :

```swift
.package(url: "https://github.com/tals-enterprise/boostyourapp-sdk.git", from: "0.1.0")
// cible : .product(name: "BoostNetwork", package: "boostyourapp-sdk")
```

Guide complet : [ios/README.md](ios/README.md).

### Capacitor / Ionic

```bash
npm install @tals-enterprise/boostyourapp-capacitor
npx cap sync
```

Guide complet : [capacitor/README.md](capacitor/README.md).

### Cordova

```bash
cordova plugin add @tals-enterprise/boostyourapp-cordova
```

Guide complet : [cordova/README.md](cordova/README.md).

### React Native / Expo

```bash
npm install @tals-enterprise/boostyourapp-react-native
cd ios && pod install            # React Native sans Expo
```

Avec Expo, ajoutez le config plugin puis `npx expo prebuild` (Expo Go ne charge pas les modules natifs).
Guide complet : [react-native/README.md](react-native/README.md).

## Utilisation

Les mêmes appels partout :

```
init("bya_…")           // une fois, au démarrage (Swift : BoostNetwork.initialize(appKey:))
setStyle("dynamic", "neon") // facultatif : style ("standard" par défaut) et palette des pubs
showBanner("bottom")    // ou "top"
hideBanner()
loadInterstitial()      // facultatif : prépare un interstitiel dès le lancement
showInterstitial(…)     // facultatif : pub plein écran, entre deux niveaux par exemple
onEvent(callback)       // facultatif : { type, adId?, code?, message? }
```

Une pub compte quand la bannière est visible à 50 % au moins pendant 1 seconde. Laissez-la affichée sur les
écrans où l'utilisateur passe du temps : c'est ce qui vous fait gagner de la visibilité dans le réseau.

Événements (`type`) : `loaded` (une pub est affichée dans la bannière), `clicked` (le store va s'ouvrir),
`interstitialShown` et `interstitialClosed` (mettez l'app en pause puis reprenez-la), `error` (`code` :
`unknown_app`, `suspended`, `network`, `not_initialized`…).

## Interstitiels

Une pub plein écran, affichée quand vous l'appelez, à un moment naturel de pause : fin de niveau, retour à
l'accueil. Elle reprend le style et la palette choisis avec `setStyle`.

- `showInterstitial` rend la main avec `false` aussitôt s'il n'y a pas de pub prête, ou si le précédent date de
  moins de 3 minutes (réglage du réseau), et avec `true` quand l'utilisateur ferme l'interstitiel. Dans les deux
  cas, reprenez le cours de l'app. Kotlin : `showInterstitial { shown -> … }` ; Swift :
  `showInterstitial { shown in … }` ; plugins : Promise de booléen.
- Le bouton de fermeture apparaît après un compte à rebours de 5 secondes.
- Le SDK garde un interstitiel prêt. Au tout premier appel, il n'y en a pas encore : appelez
  `loadInterstitial()` au lancement pour que le premier soit prêt. Ensuite, le SDK en prépare un à chaque
  lancement. `isInterstitialReady()` indique si `showInterstitial` en affichera un.
- Un interstitiel vu (1 seconde à l'écran) compte comme 5 bannières pour la visibilité de votre app dans le
  réseau. Il consomme aussi 5 fois plus la diffusion de l'annonceur montré.

## Style des pubs

Vous choisissez le rendu de toutes les pubs affichées dans votre app, en un appel facultatif (avant ou après
`init`) :

- `standard` (par défaut) : carte claire et sobre, bouton de couleur ;
- `dynamic` : vitrine, avec fond travaillé, mot clé surligné, captures de l'app en éventail et animations.

La palette de couleurs est désignée par sa clé, visible dans le tableau de bord (page d'intégration de votre
app, avec un aperçu). Sans palette, ou avec une clé inconnue, c'est la première du style qui s'applique.

Palettes du style `dynamic` : `stade` (Stade de nuit), `retro` (Rétro crème), `neon` (Néon arcade),
`minimal` (Minimal blanc), `ocean`, `coucher` (Coucher de soleil), `bonbon`, `foret`. Palettes du style
`standard` : `marine`, `bleu`, `violet`, `vert`, `orange`, `rose`, `sombre`.

Les deux styles ont la même hauteur : 13 % de la hauteur de l'écran, entre 64 et 100 dp/pt. La place de la
bannière est réservée : le contenu de votre app est réduit d'autant et rien n'est masqué. Sur Android, c'est le
contenu de l'activité qui est réduit. Sur iOS, c'est la zone sûre du contrôleur racine qui est agrandie : vos vues
doivent la respecter, et en hybride le CSS doit utiliser `env(safe-area-inset-bottom)`.

## Déclarations sur les stores

Données collectées par le SDK, non liées à l'identité de l'utilisateur et sans suivi publicitaire :

- **identifiant d'installation** : UUID aléatoire propre au SDK, ni IDFA ni identifiant publicitaire Android,
  donc pas de fenêtre ATT ni de permission `AD_ID` ;
- **interactions** : affichages et clics des pubs (bannière et interstitiel) ;
- **adresse IP** : réduite au réseau (/24 ou /64) et mélangée dans une empreinte de 1 024 bits. Elle n'est
  jamais stockée.

| Store | Déclaration |
|---|---|
| Google Play | « Contient des annonces » : oui. Data Safety : identifiants d'appareil ou autres, interactions avec l'app ; chiffrées en transit ; non partagées |
| App Store | Étiquettes de confidentialité : Identifiants > ID d'appareil ; Données d'utilisation > Interactions avec le produit ; finalité « Publicité tierce » ; non liées à l'utilisateur ; pas de suivi |

Le cœur iOS fournit un manifeste de confidentialité (`PrivacyInfo.xcprivacy`) : identifiant et interactions
collectés, accès à UserDefaults (raison CA92.1). Capacitor et React Native l'embarquent dans un bundle de
ressources. Avec Cordova, reportez ces entrées dans le manifeste de l'app.

## Licence

MIT, voir [LICENSE](LICENSE).

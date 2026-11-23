# @tals-enterprise/boostyourapp-capacitor

Bannière du réseau d'échange de pubs BoostYourApp pour Capacitor 8 (Android et iOS). Le plugin embarque les
cœurs natifs du SDK ; il ne fait que leur transmettre les appels.

## Installation

```bash
npm install @tals-enterprise/boostyourapp-capacitor
npx cap sync
```

Avant publication sur npm, installer le paquet construit localement (voir plus bas) :

```bash
npm install ./vendor/boostyourapp-capacitor-0.2.0.tgz
npx cap sync
```

## Utilisation

```ts
import { Capacitor } from '@capacitor/core';
import { BoostNetwork } from '@tals-enterprise/boostyourapp-capacitor';

// Une clé par store (tableau de bord BoostYourApp, page d'intégration de l'app)
await BoostNetwork.init(Capacitor.getPlatform() === 'ios' ? 'bya_ios…' : 'bya_android…');
await BoostNetwork.showBanner('bottom');   // ou 'top'
await BoostNetwork.hideBanner();

// Facultatif : interstitiel (pub plein écran), entre deux niveaux par exemple
await BoostNetwork.loadInterstitial();     // au lancement, pour que le premier soit prêt
const shown = await BoostNetwork.showInterstitial(); // false aussitôt si rien n'est prêt, true à la fermeture

const listener = await BoostNetwork.onEvent((event) => {
  // event.type : 'loaded' | 'clicked' | 'interstitialShown' | 'interstitialClosed' | 'error'
  // event.adId, event.code, event.message
});
listener.remove();
```

La bannière est une vue native placée en haut ou en bas de l'écran. Sur Android, la WebView est réduite
d'autant. Sur iOS, la zone sûre est agrandie : utilisez `env(safe-area-inset-bottom)` (ou `-top`) dans le CSS
pour que rien ne passe sous la bannière. Dans le navigateur (`ionic serve`), les appels réussissent sans rien afficher.

Prérequis : Capacitor 8, Android 7 (API 24) et plus, iOS 15 et plus. Le build Android utilise Kotlin (plugin
Gradle ajouté par le plugin lui-même) et le JDK 21, comme Capacitor 8.

## Construire le paquet

```bash
cd sdk/capacitor
npm install
npm pack            # synchronise les cœurs (prepack), compile le JS, produit boostyourapp-capacitor-<version>.tgz
```

Vérifier d'abord l'URL et la clé du réseau dans `sdk/android/gradle.properties` : elles sont intégrées au
paquet.

## Tester sur Ionic Appflow (iOS)

Le build iOS n'a pas pu être fait sur la machine de développement (Windows). Appflow sert de premier build iOS.

1. **Backend** : sur l'API du réseau (VPS, voir `deploy/vps/README.md`), inscrire
   l'app hôte et au moins une autre app iOS, les activer et approuver leurs pubs (back-office), puis mettre
   `min_impressions_7d` à 0 le temps du test.
2. **Paquet** : renseigner `boost.apiUrl` et `boost.apiKey` dans `sdk/android/gradle.properties`, lancer
   `npm pack` ici, copier le `.tgz` dans le dépôt de l'app (par exemple `vendor/`) et le **committer** :
   Appflow construit à partir du dépôt git.
3. **App** : `npm install ./vendor/boostyourapp-capacitor-0.2.0.tgz`, puis appeler `BoostNetwork.init(…)` et
   `showBanner(…)` après le chargement. Ensuite `npx cap sync ios`, commit et push.
4. **Build** : lancer un build iOS sur Appflow. Swift Package Manager et CocoaPods sont tous deux pris en
   charge (`Package.swift` et `BoostyourappCapacitor.podspec`).
5. **Vérifications** :
   - la bannière apparaît ;
   - les accroches alternent toutes les quelques secondes ;
   - un toucher ouvre l'App Store ;
   - les compteurs augmentent dans le back-office.

   L'onglet Réseau de l'app montre les affichages réalisés.

En cas d'échec de compilation Swift, le journal d'Appflow donne le fichier et la ligne : les sources du cœur
sont dans `ios/Sources/BoostNetworkPlugin/Core` (copie de `sdk/ios/Sources/BoostNetwork`).

## Fichiers

| Chemin | Rôle |
|---|---|
| `src/` | API JavaScript (`init`, `showBanner`, `hideBanner`, `onEvent`) |
| `android/src/main/java/com/boostyourapp/capacitor` | Pont Android |
| `ios/Sources/BoostNetworkPlugin/BoostNetworkPlugin.swift` | Pont iOS |
| `android/…/network`, `ios/…/Core` | Cœurs natifs, copiés par `npm run sync` (non versionnés) |

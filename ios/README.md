# SDK iOS BoostYourApp

Cœur natif iOS du réseau d'échange de bannières : Swift Package sans dépendance, iOS 13 et plus. Même
logique et même rendu que le cœur Android ; les plugins Capacitor, Cordova et React Native en embarquent
les sources.

## Installation

Swift Package Manager : Xcode › **File › Add Package Dependencies…**, URL
`https://github.com/tals-enterprise/boostyourapp-sdk`, produit **BoostNetwork**.

## Intégration

```swift
import BoostNetwork

// application(_:didFinishLaunchingWithOptions:) ou init de l'App SwiftUI
BoostNetwork.initialize(appKey: "bya_…")   // init étant réservé en Swift
BoostNetwork.setStyle("dynamic", palette: "neon") // facultatif : style ("standard" par défaut) et palette

// Là où la bannière doit apparaître
BoostNetwork.showBanner("bottom")           // ou "top", ou showBanner(position: .top)
BoostNetwork.hideBanner()

// Facultatif : interstitiel (pub plein écran), entre deux niveaux par exemple
BoostNetwork.loadInterstitial()             // au lancement, pour que le premier soit prêt
BoostNetwork.showInterstitial { shown in nextLevel() } // false aussitôt si rien n'est prêt, true à la fermeture

// Facultatif
BoostNetwork.onEvent { event in
    switch event.type {
    case "loaded": …                        // event.adId
    case "clicked": …                       // le store va s'ouvrir
    case "interstitialShown": …             // mettre l'app en pause
    case "interstitialClosed": …            // reprendre
    default: …                              // "error" : event.code (unknown_app, suspended, network…)
    }
}
```

En Objective-C : `[BoostNetwork initializeWithAppKey:@"bya_…"]`, `[BoostNetwork showBanner:@"bottom"]`,
`[BoostNetwork showInterstitial:^(BOOL shown) { … }]`.

- La bannière est ajoutée à la fenêtre principale, juste au-dessus de la vue du contrôleur racine, dont la
  zone sûre est agrandie de la place de la bannière (`additionalSafeAreaInsets`) : les vues qui respectent la
  zone sûre ne sont pas masquées. Les contrôleurs présentés en modale passent par-dessus : elle n'est alors pas
  comptée comme visible. Elle reste dans la zone sûre de l'appareil (encoche, barre d'accueil).
- Style et palettes : voir le [README du SDK](../README.md#style-des-pubs) ; interstitiels :
  [Interstitiels](../README.md#interstitiels).
- L'interstitiel est présenté en plein écran au-dessus du contrôleur le plus haut de la fenêtre (modales
  comprises) ; le glissement vers le bas ne le ferme pas.
- Toutes les méthodes peuvent être appelées depuis n'importe quel thread.
- Pas d'IDFA, pas de fenêtre ATT. Manifeste de confidentialité inclus.

## Fonctionnement

Identique à Android (voir [../android/README.md](../android/README.md)). Particularités iOS :

- **Mesure de visibilité, toutes les 100 ms** :
  - la vue est dans une fenêtre, et ni elle ni ses parents ne sont masqués (`isHidden`) ;
  - l'opacité est pleine, y compris pendant les animations (couche de présentation) ;
  - le cadre converti en coordonnées de l'écran est visible à 50 % au moins, une fois retirés le clavier et
    les vues ajoutées par-dessus dans la fenêtre ;
  - la taille est celle prévue ;
  - l'app est active (`applicationState == .active`, ce qui exclut l'écran éteint).
- **Passage en arrière-plan** : les affichages en attente sont envoyés dans une tâche d'arrière-plan.
- **Clic** : le lien App Store s'ouvre directement dans l'app App Store.

## Projet

```bash
swift test          # sur Mac, à la racine du dépôt : logique (file, affichages en attente, visibilité) et contrat de l'API
```

Les tests tournent sur macOS (la partie UIKit est isolée par `#if os(iOS)`). Le paquet n'a pas pu être compilé
sur la machine de développement (Windows) : le premier build se fera sur Mac ou sur Ionic Appflow via le
plugin Capacitor.

**Distribution** : `Package.swift` est à la racine du dépôt public, comme l'exige Swift Package Manager ; les
versions sont ses tags. `Sources/BoostNetwork/Config.swift` est généré par `scripts/sync.mjs`
(voir [../MAINTAINING.md](../MAINTAINING.md)).

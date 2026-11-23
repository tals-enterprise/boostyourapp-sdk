# SDK Android BoostYourApp

Cœur natif Android du réseau d'échange de bannières : librairie Kotlin sans dépendance (76 Ko), Android 5.0
(API 21) et plus. Les plugins Capacitor, Cordova et React Native s'appuieront dessus.

## Installation

Dépôt JitPack dans `settings.gradle.kts` (`maven("https://jitpack.io")` dans `dependencyResolutionManagement`),
puis dans le `build.gradle.kts` de l'app :

```kotlin
implementation("com.github.tals-enterprise:boostyourapp-sdk:0.2.0")
```

## Intégration

```kotlin
// Application.onCreate() (ou la première activité)
BoostNetwork.init(this, "bya_…")       // clé de l'app, dans le tableau de bord BoostYourApp

// Là où la bannière doit apparaître
BoostNetwork.showBanner("bottom")      // ou "top"
BoostNetwork.hideBanner()

// Facultatif : interstitiel (pub plein écran), entre deux niveaux par exemple
BoostNetwork.loadInterstitial()        // au lancement, pour que le premier soit prêt
BoostNetwork.showInterstitial { shown -> nextLevel() } // false aussitôt si rien n'est prêt, true à la fermeture

// Facultatif
BoostNetwork.onEvent { event ->
    when (event) {
        is BoostEvent.Loaded -> …          // une pub est affichée
        is BoostEvent.Clicked -> …         // le store va s'ouvrir
        is BoostEvent.InterstitialShown -> … // mettre l'app en pause
        is BoostEvent.InterstitialClosed -> … // reprendre
        is BoostEvent.Error -> …           // event.code : unknown_app, suspended, network…
    }
}
```

En Java : `BoostNetwork.init(this, "bya_…")`, `BoostNetwork.showBanner("bottom")`,
`BoostNetwork.showInterstitial(shown -> { … })`, `BoostNetwork.onEvent(event -> { … })`.

- La bannière se place en haut ou en bas, et le contenu de l'activité (`android.R.id.content`) est réduit
  d'autant par une marge intérieure : rien n'est masqué, rien à changer dans vos layouts. Elle suit l'activité
  au premier plan et évite les barres système des apps en plein écran (edge-to-edge).
- Style et palettes : voir le [README du SDK](../README.md#style-des-pubs) ; interstitiels :
  [Interstitiels](../README.md#interstitiels).
- L'interstitiel s'affiche dans une fenêtre plein écran (`Dialog`) au-dessus de l'activité au premier plan ; le
  retour arrière ne le ferme qu'après le compte à rebours. Il se ferme avec son activité (rotation comprise).
- Toutes les méthodes peuvent être appelées depuis n'importe quel thread.
- Une seule permission, `INTERNET`. Pas d'identifiant publicitaire (pas de permission `AD_ID`).

## Fonctionnement

1. `network_next` renvoie 5 pubs (paramètre serveur) ; chacune reste affichée `refreshSeconds` secondes
   (60 par défaut), ses accroches alternant toutes les `rotationSeconds` secondes.
2. La visibilité est mesurée toutes les 100 ms. Une pub compte quand, pendant **1 seconde continue** :
   au moins 50 % de ses pixels sont à l'écran (barres système, clavier et vues de l'app par-dessus déduits),
   l'opacité est pleine, la taille est celle prévue, la fenêtre a le focus (pas de dialogue par-dessus),
   l'app est au premier plan et l'écran allumé.
3. Les jetons des pubs vues partent avec la demande suivante, et à la mise en arrière-plan (sans recevoir de
   nouvelles pubs). Ils sont conservés sur le disque si l'app s'arrête (30 minutes au plus).
   Le contenu des 50 dernières pubs reçues est gardé sur le disque : le serveur ne renvoie plus que leur id,
   leur version et un jeton, tant que leur contenu ne change pas.
4. Un toucher appelle `network_click`, puis ouvre la fiche dans le Play Store (ou le navigateur).
5. Interstitiel : une pub demandée à part (`p_format = interstitial`), gardée prête 20 minutes au plus. Il compte
   quand il reste 1 seconde à l'écran (fenêtre au premier plan, animation d'entrée terminée) ; son jeton part avec
   la demande suivante, comme ceux des bannières.
6. En cas d'erreur réseau, nouvel essai après 30 s, puis jusqu'à 5 min. App suspendue : nouvel essai
   toutes les heures. Clé inconnue : la bannière s'arrête (erreur `unknown_app`).

## Déclarations sur Google Play

- **Contient des annonces** : oui.
- **Sécurité des données** : identifiants d'appareil ou autres (identifiant d'installation aléatoire, propre
  au SDK, non lié à l'appareil), interactions avec l'app (affichages et clics de la bannière), avec la langue
  et la version du système de l'appareil, agrégées pour les statistiques (finalité : analyse). Données chiffrées en transit, non partagées à des fins de suivi publicitaire.

## Projet

| Module | Rôle |
|---|---|
| `network` | La librairie |
| `sample` | App de démonstration (bannière en haut, en bas, changement d'écran) |

Le projet Supabase du réseau est défini dans `gradle.properties` (`boost.apiUrl`, `boost.apiKey` : URL et clé
publique ; `boost.version`). Après modification, lancer `node scripts/sync.mjs` : il régénère `Config.kt`
(intégré au SDK publié) et la configuration iOS, et met à jour les plugins.

```bash
./gradlew :network:testDebugUnitTest     # tests JVM : contrat de l'API, file, visibilité
./gradlew :network:assembleRelease       # network/build/outputs/aar/network-release.aar
```

### Test de bout en bout sur émulateur

Le serveur de test imite l'API REST de Supabase sur PGlite, avec les vraies migrations :

```bash
node supabase/tests/sdk-test-server.mjs 8787           # à la racine du dépôt
./gradlew :sample:installDebug -Psample.apiUrl=http://10.0.2.2:8787 -Psample.apiKey=test-key -Psample.appKey=bya_e2etesthost
```

Puis lancer l'app sur l'émulateur et suivre les compteurs sur `http://localhost:8787/debug/state`.

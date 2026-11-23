# @tals-enterprise/boostyourapp-cordova

Bannière du réseau d'échange de pubs BoostYourApp pour Cordova (cordova-android 12+, cordova-ios 7+).

## Installation

```bash
cordova plugin add @tals-enterprise/boostyourapp-cordova
# avant publication : dossier du paquet décompressé (cordova n'accepte pas les .tgz)
cordova plugin add ./vendor/boostyourapp-cordova
```

## Utilisation

```js
document.addEventListener('deviceready', async () => {
  // Une clé par store (tableau de bord BoostYourApp, page d'intégration de l'app)
  await BoostNetwork.init(cordova.platformId === 'ios' ? 'bya_ios…' : 'bya_android…');
  await BoostNetwork.showBanner('bottom');   // ou 'top'
  await BoostNetwork.loadInterstitial();     // facultatif : interstitiel prêt dès le lancement
  const shown = await BoostNetwork.showInterstitial(); // pub plein écran : false si rien n'est prêt, true à la fermeture
  const subscription = BoostNetwork.onEvent((event) => {
    /* loaded, clicked, interstitialShown, interstitialClosed, error */
  });
});
```

Types TypeScript : `@tals-enterprise/boostyourapp-cordova/types`.

- **Android** : le cœur est livré en AAR (`app/libs`). Sa bibliothèque Kotlin standard est ajoutée par le
  plugin, sans réglage Kotlin dans `config.xml`. Le pont est en Java.
- **iOS** : sources Swift (pont et cœur). Reportez dans le manifeste de confidentialité de l'app les entrées de
  `src/ios/PrivacyInfo.xcprivacy` (voir [../README.md](../README.md)).

## Construire le paquet

```bash
cd sdk/cordova
npm pack     # prepack : construit l'AAR (Gradle) et copie les sources Swift, liste mise à jour dans plugin.xml
```

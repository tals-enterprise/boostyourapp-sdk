# @tals-enterprise/boostyourapp-react-native

Bannière du réseau d'échange de pubs BoostYourApp pour React Native 0.73+ et Expo (prebuild / EAS).

## Installation

```bash
npm install @tals-enterprise/boostyourapp-react-native
cd ios && pod install            # React Native sans Expo
```

Expo : ajouter le config plugin, puis `npx expo prebuild` (Expo Go ne charge pas les modules natifs) :

```json
{ "expo": { "plugins": [["@tals-enterprise/boostyourapp-react-native", {
  "androidAppKey": "bya_android…",
  "iosAppKey": "bya_ios…"
}]] } }
```

Une clé par store : `androidAppKey` (fiche Google Play) et `iosAppKey` (fiche App Store). `appKey` reste accepté pour
une app présente sur un seul store. Avec les clés dans le config plugin, `init()` peut être appelé sans argument.

## Utilisation

```ts
import { Platform } from 'react-native';
import { BoostNetwork } from '@tals-enterprise/boostyourapp-react-native';

// Une clé par store (tableau de bord BoostYourApp, page d'intégration de l'app)
await BoostNetwork.init(Platform.OS === 'ios' ? 'bya_ios…' : 'bya_android…');
await BoostNetwork.showBanner('bottom');   // ou 'top'
await BoostNetwork.loadInterstitial();     // facultatif : interstitiel prêt dès le lancement
const shown = await BoostNetwork.showInterstitial(); // pub plein écran : false si rien n'est prêt, true à la fermeture
const subscription = BoostNetwork.onEvent((event) => {
  /* loaded, clicked, interstitialShown, interstitialClosed, error */
});
subscription.remove();
```

Module classique, pris en charge par la couche de compatibilité de la nouvelle architecture. Android : le
pont et le cœur sont en Kotlin (plugin Kotlin déjà présent dans les apps React Native). iOS : pont Swift,
déclaré en Objective-C, et cœur Swift, avec manifeste de confidentialité.

État : le code Android compile contre React Native 0.88. Il n'a pas encore tourné dans une app React Native
complète. Le code iOS n'a pas été compilé (pas de Mac).

## Construire le paquet

```bash
cd sdk/react-native
npm pack     # prepack : copie les cœurs Android et iOS
```

/**
 * Bannière du réseau BoostYourApp (React Native et Expo). API identique à celle des autres plateformes :
 *
 *   import { BoostNetwork } from '@tals-enterprise/boostyourapp-react-native';
 *
 *   await BoostNetwork.init('bya_…');      // ou init() avec la clé du config plugin Expo
 *   await BoostNetwork.setStyle('dynamic', 'neon'); // facultatif : style et couleurs des pubs
 *   await BoostNetwork.showBanner('bottom'); // ou 'top'
 *   const shown = await BoostNetwork.showInterstitial(); // facultatif : pub plein écran, entre deux niveaux
 *   const subscription = BoostNetwork.onEvent((event) => …); // subscription.remove() pour arrêter
 */
'use strict';

const { NativeEventEmitter, NativeModules, Platform } = require('react-native');

const LINKING_ERROR =
  "Le module natif BoostNetwork est introuvable. Lancez 'pod install' (iOS) ou 'npx expo prebuild', " +
  "puis reconstruisez l'app (Expo Go ne charge pas les modules natifs).";

const Native = NativeModules.BoostNetwork
  ? NativeModules.BoostNetwork
  : new Proxy({}, { get() { throw new Error(LINKING_ERROR); } });

const EVENT = 'BoostNetworkEvent';
let emitter = null;

function getEmitter() {
  if (!emitter) emitter = new NativeEventEmitter(Platform.OS === 'ios' ? Native : undefined);
  return emitter;
}

const BoostNetwork = {
  /** Initialise le SDK avec la clé de l'app (tableau de bord BoostYourApp). */
  init(appKey) {
    return Native.start(appKey == null ? null : String(appKey));
  },

  /** Affiche la bannière en haut ('top') ou en bas ('bottom', par défaut) de l'écran, par-dessus l'app. */
  showBanner(position) {
    return Native.showBanner(position === 'top' ? 'top' : 'bottom');
  },

  hideBanner() {
    return Native.hideBanner();
  },

  /** Style des pubs : 'standard' (carte claire, par défaut) ou 'dynamic' (vitrine), et clé de palette (tableau de bord, page d'intégration). Avant ou après init. */
  setStyle(style, palette) {
    return Native.setStyle(style === 'dynamic' ? 'dynamic' : 'standard', palette == null ? null : String(palette));
  },

  /** Facultatif : prépare un interstitiel dès le lancement (ensuite, le SDK en garde un prêt). */
  loadInterstitial() {
    return Native.loadInterstitial();
  },

  /** Un interstitiel est prêt et le précédent date d'au moins 3 minutes (Promise<boolean>). */
  isInterstitialReady() {
    return Native.isInterstitialReady();
  },

  /**
   * Affiche un interstitiel plein écran (Promise<boolean>) : false aussitôt s'il n'y en a pas de prêt, true quand
   * l'utilisateur le ferme ; reprenez alors l'app.
   */
  showInterstitial() {
    return Native.showInterstitial();
  },

  /** Écoute les événements de la bannière ; renvoie un abonnement ({ remove() }). */
  onEvent(callback) {
    return getEmitter().addListener(EVENT, callback);
  },

  /** Tests uniquement : autre serveur du réseau. À appeler avant init. */
  setEndpoint(apiUrl, apiKey) {
    return Native.setEndpoint(apiUrl, apiKey);
  },
};

module.exports = { BoostNetwork, default: BoostNetwork };

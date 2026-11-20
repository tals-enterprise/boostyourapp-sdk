import type { PluginListenerHandle } from '@capacitor/core';

/** Position de la bannière, en haut ou en bas de l'écran ; le contenu de l'app est réduit d'autant. */
export type BannerPosition = 'top' | 'bottom';

/** Style des pubs : carte claire (standard) ou vitrine (dynamic : fond travaillé, mot surligné, captures). */
export type BannerStyle = 'standard' | 'dynamic';

/**
 * Événement de la bannière :
 * - `loaded` : une pub est affichée (`adId`) ;
 * - `clicked` : l'utilisateur a touché la bannière ou l'interstitiel, le store va s'ouvrir (`adId`) ;
 * - `interstitialShown` : un interstitiel couvre l'écran, mettez l'app en pause (`adId`) ;
 * - `interstitialClosed` : l'interstitiel est fermé, l'app peut reprendre (`adId`) ;
 * - `error` : `unknown_app` (appKey inconnue), `suspended`, `network`, `not_initialized`... (`code`, `message`).
 *   La bannière réessaie d'elle-même sauf pour `unknown_app`.
 */
export interface BoostNetworkEvent {
  type: 'loaded' | 'clicked' | 'interstitialShown' | 'interstitialClosed' | 'error';
  adId?: string;
  code?: string;
  message?: string;
}

/** API publique, identique sur toutes les plateformes. */
export interface BoostNetworkApi {
  /** Initialise le SDK avec la clé de l'app (tableau de bord BoostYourApp). À appeler une fois. */
  init(appKey: string): Promise<void>;
  /** Affiche la bannière en haut ou en bas de l'écran (bas par défaut). */
  showBanner(position?: BannerPosition): Promise<void>;
  hideBanner(): Promise<void>;
  /** Style des pubs : 'standard' (carte claire, par défaut) ou 'dynamic' (vitrine), et clé de palette (tableau de bord, page d'intégration). Avant ou après init. */
  setStyle(style: BannerStyle, palette?: string): Promise<void>;
  /** Facultatif : prépare un interstitiel dès le lancement (ensuite, le SDK en garde un prêt). */
  loadInterstitial(): Promise<void>;
  /** Un interstitiel est prêt et le précédent date d'au moins 3 minutes. */
  isInterstitialReady(): Promise<boolean>;
  /**
   * Affiche un interstitiel plein écran dans le style choisi. Se résout à `false` aussitôt s'il n'y en a pas de prêt
   * (ou si le précédent date de moins de 3 minutes), à `true` quand l'utilisateur le ferme : reprenez alors l'app.
   */
  showInterstitial(): Promise<boolean>;
  /** Écoute les événements de la bannière ; `remove()` sur le résultat pour arrêter. */
  onEvent(callback: (event: BoostNetworkEvent) => void): Promise<PluginListenerHandle>;
  /** Tests uniquement : autre serveur du réseau. À appeler avant `init`. */
  setEndpoint(apiUrl: string, apiKey: string): Promise<void>;
}

/** Pont natif (noms des méthodes Android et iOS). */
export interface BoostNetworkPlugin {
  initialize(options: { appKey: string }): Promise<void>;
  showBanner(options: { position: BannerPosition }): Promise<void>;
  hideBanner(): Promise<void>;
  setStyle(options: { style: BannerStyle; palette?: string }): Promise<void>;
  loadInterstitial(): Promise<void>;
  isInterstitialReady(): Promise<{ ready: boolean }>;
  showInterstitial(): Promise<{ shown: boolean }>;
  setEndpoint(options: { apiUrl: string; apiKey: string }): Promise<void>;
  addListener(eventName: 'bannerEvent', listener: (event: BoostNetworkEvent) => void): Promise<PluginListenerHandle>;
  removeAllListeners(): Promise<void>;
}

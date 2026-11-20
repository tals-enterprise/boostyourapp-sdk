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
 */
export interface BoostNetworkEvent {
  type: 'loaded' | 'clicked' | 'interstitialShown' | 'interstitialClosed' | 'error';
  adId?: string;
  code?: string;
  message?: string;
}

export interface BoostNetworkSubscription {
  remove(): void;
}

export interface BoostNetworkApi {
  /** Clé facultative si elle est fournie par le config plugin Expo. */
  init(appKey?: string): Promise<void>;
  showBanner(position?: BannerPosition): Promise<void>;
  hideBanner(): Promise<void>;
  /** Style des pubs : 'standard' (carte claire, par défaut) ou 'dynamic' (vitrine), et clé de palette (tableau de bord, page d'intégration). Avant ou après init. */
  setStyle(style: BannerStyle, palette?: string): Promise<void>;
  /** Facultatif : prépare un interstitiel dès le lancement (ensuite, le SDK en garde un prêt). */
  loadInterstitial(): Promise<void>;
  /** Un interstitiel est prêt et le précédent date d'au moins 3 minutes. */
  isInterstitialReady(): Promise<boolean>;
  /** Interstitiel plein écran : false aussitôt s'il n'y en a pas de prêt, true quand l'utilisateur le ferme. */
  showInterstitial(): Promise<boolean>;
  onEvent(callback: (event: BoostNetworkEvent) => void): BoostNetworkSubscription;
  /** Tests uniquement : autre serveur du réseau. À appeler avant init. */
  setEndpoint(apiUrl: string, apiKey: string): Promise<void>;
}

export declare const BoostNetwork: BoostNetworkApi;
export default BoostNetwork;

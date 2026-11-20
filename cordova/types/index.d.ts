/** Bannière du réseau BoostYourApp (Cordova), disponible après l'événement deviceready. */
export type BannerPosition = 'top' | 'bottom';

export interface BoostNetworkEvent {
  type: 'loaded' | 'clicked' | 'interstitialShown' | 'interstitialClosed' | 'error';
  adId?: string;
  code?: string;
  message?: string;
}

export interface BoostNetworkApi {
  init(appKey: string): Promise<void>;
  showBanner(position?: BannerPosition): Promise<void>;
  hideBanner(): Promise<void>;
  /** Style des pubs : 'standard' (carte claire, par défaut) ou 'dynamic' (vitrine), et clé de palette (tableau de bord, page d'intégration). Avant ou après init. */
  setStyle(style: 'standard' | 'dynamic', palette?: string): Promise<void>;
  /** Facultatif : prépare un interstitiel dès le lancement (ensuite, le SDK en garde un prêt). */
  loadInterstitial(): Promise<void>;
  /** Un interstitiel est prêt et le précédent date d'au moins 3 minutes. */
  isInterstitialReady(): Promise<boolean>;
  /** Interstitiel plein écran : false aussitôt s'il n'y en a pas de prêt, true quand l'utilisateur le ferme. */
  showInterstitial(): Promise<boolean>;
  onEvent(callback: (event: BoostNetworkEvent) => void): { remove(): void };
  /** Tests uniquement : autre serveur du réseau. À appeler avant init. */
  setEndpoint(apiUrl: string, apiKey: string): Promise<void>;
}

declare global {
  const BoostNetwork: BoostNetworkApi;
}

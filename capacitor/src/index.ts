import { registerPlugin } from '@capacitor/core';

import type { BannerPosition, BoostNetworkApi, BoostNetworkPlugin } from './definitions';

const Native = registerPlugin<BoostNetworkPlugin>('BoostNetwork', {
  web: () => import('./web').then((m) => new m.BoostNetworkWeb()),
});

/**
 * Bannière du réseau BoostYourApp.
 *
 * ```ts
 * import { BoostNetwork } from '@tals-enterprise/boostyourapp-capacitor';
 *
 * await BoostNetwork.init('bya_…');
 * await BoostNetwork.setStyle('dynamic', 'neon'); // facultatif
 * await BoostNetwork.showBanner('bottom');
 * const shown = await BoostNetwork.showInterstitial(); // facultatif : entre deux niveaux, par exemple
 * BoostNetwork.onEvent((event) => console.log(event.type));
 * ```
 */
export const BoostNetwork: BoostNetworkApi = {
  init: (appKey: string) => Native.initialize({ appKey }),
  showBanner: (position: BannerPosition = 'bottom') => Native.showBanner({ position }),
  hideBanner: () => Native.hideBanner(),
  setStyle: (style, palette) => Native.setStyle({ style, palette }),
  loadInterstitial: () => Native.loadInterstitial(),
  isInterstitialReady: () => Native.isInterstitialReady().then((result) => result.ready),
  showInterstitial: () => Native.showInterstitial().then((result) => result.shown),
  onEvent: (callback) => Native.addListener('bannerEvent', callback),
  setEndpoint: (apiUrl: string, apiKey: string) => Native.setEndpoint({ apiUrl, apiKey }),
};

export * from './definitions';

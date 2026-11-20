import { WebPlugin } from '@capacitor/core';

import type { BoostNetworkPlugin } from './definitions';

/**
 * Navigateur (ionic serve, PWA) : pas de bannière, le réseau ne concerne que les apps natives.
 * Les appels réussissent sans rien faire pour que le même code tourne partout.
 */
export class BoostNetworkWeb extends WebPlugin implements BoostNetworkPlugin {
  async initialize(): Promise<void> {
    console.info('[BoostNetwork] Bannière disponible uniquement sur Android et iOS');
  }

  async showBanner(): Promise<void> {
    return;
  }

  async hideBanner(): Promise<void> {
    return;
  }

  async setStyle(): Promise<void> {
    return;
  }

  async loadInterstitial(): Promise<void> {
    return;
  }

  async isInterstitialReady(): Promise<{ ready: boolean }> {
    return { ready: false };
  }

  async showInterstitial(): Promise<{ shown: boolean }> {
    return { shown: false };
  }

  async setEndpoint(): Promise<void> {
    return;
  }
}

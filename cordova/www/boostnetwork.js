/**
 * Bannière du réseau BoostYourApp (Cordova). API identique à celle des autres plateformes :
 *
 *   document.addEventListener('deviceready', function () {
 *     BoostNetwork.init('bya_…');
 *     BoostNetwork.setStyle('dynamic', 'neon');    // facultatif : style et couleurs des pubs
 *     BoostNetwork.showBanner('bottom');            // ou 'top'
 *     BoostNetwork.showInterstitial().then(function (shown) { … }); // facultatif : pub plein écran
 *     BoostNetwork.onEvent(function (event) { … }); // { type, adId, code, message }
 *     // type : 'loaded' | 'clicked' | 'interstitialShown' | 'interstitialClosed' | 'error'
 *   });
 *
 * Chaque méthode renvoie une Promise.
 */
var exec = require('cordova/exec');

var SERVICE = 'BoostNetwork';
var listeners = [];
var subscribed = false;

function call(action, args) {
    return new Promise(function (resolve, reject) {
        exec(resolve, reject, SERVICE, action, args || []);
    });
}

function dispatch(event) {
    listeners.slice().forEach(function (listener) {
        try {
            listener(event);
        } catch (error) {
            console.error('[BoostNetwork] Erreur dans onEvent', error);
        }
    });
}

module.exports = {
    /** Initialise le SDK avec la clé de l'app (tableau de bord BoostYourApp). */
    init: function (appKey) {
        return call('initialize', [appKey]);
    },

    /** Affiche la bannière en haut ('top') ou en bas ('bottom', par défaut) de l'écran. */
    showBanner: function (position) {
        return call('showBanner', [position === 'top' ? 'top' : 'bottom']);
    },

    hideBanner: function () {
        return call('hideBanner');
    },

    /** Style des pubs : 'standard' (carte claire, par défaut) ou 'dynamic' (vitrine), et clé de palette (tableau de bord, page d'intégration). Avant ou après init. */
    setStyle: function (style, palette) {
        return call('setStyle', [style === 'dynamic' ? 'dynamic' : 'standard', palette == null ? null : String(palette)]);
    },

    /** Facultatif : prépare un interstitiel dès le lancement (ensuite, le SDK en garde un prêt). */
    loadInterstitial: function () {
        return call('loadInterstitial');
    },

    /** Un interstitiel est prêt et le précédent date d'au moins 3 minutes (Promise<boolean>). */
    isInterstitialReady: function () {
        return call('isInterstitialReady').then(function (ready) { return ready === true || ready === 1; });
    },

    /**
     * Affiche un interstitiel plein écran (Promise<boolean>) : false aussitôt s'il n'y en a pas de prêt, true quand
     * l'utilisateur le ferme ; reprenez alors l'app.
     */
    showInterstitial: function () {
        return call('showInterstitial').then(function (shown) { return shown === true || shown === 1; });
    },

    /** Écoute les événements de la bannière ; renvoie { remove() } pour arrêter. */
    onEvent: function (callback) {
        listeners.push(callback);
        if (!subscribed) {
            subscribed = true;
            // Rappel conservé côté natif : un appel par événement
            exec(dispatch, function () { subscribed = false; }, SERVICE, 'onEvent', []);
        }
        return {
            remove: function () {
                listeners = listeners.filter(function (listener) { return listener !== callback; });
            }
        };
    },

    /** Tests uniquement : autre serveur du réseau. À appeler avant init. */
    setEndpoint: function (apiUrl, apiKey) {
        return call('setEndpoint', [apiUrl, apiKey]);
    }
};

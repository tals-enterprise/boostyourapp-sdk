import Foundation
import React

/// Pont React Native : transmet les appels au cœur iOS du SDK (dossier core, copié depuis sdk/ios), sans logique propre.
@objc(BoostNetworkModule)
class BoostNetworkModule: RCTEventEmitter {
    static let eventName = "BoostNetworkEvent"
    /// Clé lue dans Info.plist à défaut d'appKey (config plugin Expo)
    static let appKeyInfoKey = "BoostNetworkAppKey"

    private var hasListeners = false

    override init() {
        super.init()
        BoostNetwork.onEvent { [weak self] event in
            guard let self = self, self.hasListeners else { return }
            self.sendEvent(withName: BoostNetworkModule.eventName, body: event.dictionary)
        }
    }

    override static func requiresMainQueueSetup() -> Bool {
        return false
    }

    override func supportedEvents() -> [String]! {
        return [BoostNetworkModule.eventName]
    }

    override func startObserving() {
        hasListeners = true
    }

    override func stopObserving() {
        hasListeners = false
    }

    @objc(start:resolver:rejecter:)
    func start(_ appKey: String?, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        let configured = Bundle.main.object(forInfoDictionaryKey: BoostNetworkModule.appKeyInfoKey) as? String
        guard let key = [appKey, configured].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            reject("invalid_argument", "appKey manquante", nil)
            return
        }
        BoostNetwork.initialize(appKey: key)
        resolve(nil)
    }

    @objc(showBanner:resolver:rejecter:)
    func showBanner(_ position: String?, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        BoostNetwork.showBanner(position ?? "bottom")
        resolve(nil)
    }

    @objc(setStyle:palette:resolver:rejecter:)
    func setStyle(_ style: String, palette: String?, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        BoostNetwork.setStyle(style, palette: palette)
        resolve(nil)
    }

    @objc(loadInterstitial:rejecter:)
    func loadInterstitial(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        BoostNetwork.loadInterstitial()
        resolve(nil)
    }

    @objc(isInterstitialReady:rejecter:)
    func isInterstitialReady(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.main.async {
            resolve(BoostNetwork.isInterstitialReady)
        }
    }

    /// Résolu à la fermeture de l'interstitiel (true), ou aussitôt s'il n'y en a pas de prêt (false)
    @objc(showInterstitial:rejecter:)
    func showInterstitial(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        BoostNetwork.showInterstitial { shown in
            resolve(shown)
        }
    }

    @objc(hideBanner:rejecter:)
    func hideBanner(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        BoostNetwork.hideBanner()
        resolve(nil)
    }

    @objc(setEndpoint:apiKey:resolver:rejecter:)
    func setEndpoint(_ apiUrl: String, apiKey: String, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        BoostNetwork.setEndpoint(apiUrl: apiUrl, apiKey: apiKey)
        resolve(nil)
    }
}

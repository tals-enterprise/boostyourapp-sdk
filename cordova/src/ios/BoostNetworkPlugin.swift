#if canImport(Cordova)
import Cordova
#endif
import Foundation

/// Pont Cordova : transmet les appels au cœur iOS du SDK (dossier core, copié depuis sdk/ios), sans logique propre.
@objc(BoostNetworkPlugin)
class BoostNetworkPlugin: CDVPlugin {
    private var eventCallbackId: String?

    @objc(initialize:)
    func initialize(_ command: CDVInvokedUrlCommand) {
        guard let appKey = command.argument(at: 0) as? String,
              !appKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            send(CDVPluginResult(status: .error, messageAs: "appKey manquante"), to: command.callbackId)
            return
        }
        BoostNetwork.initialize(appKey: appKey)
        send(CDVPluginResult(status: .ok), to: command.callbackId)
    }

    @objc(showBanner:)
    func showBanner(_ command: CDVInvokedUrlCommand) {
        BoostNetwork.showBanner(command.argument(at: 0) as? String ?? "bottom")
        send(CDVPluginResult(status: .ok), to: command.callbackId)
    }

    @objc(setStyle:)
    func setStyle(_ command: CDVInvokedUrlCommand) {
        let style = command.argument(at: 0) as? String ?? "standard"
        BoostNetwork.setStyle(style, palette: command.argument(at: 1) as? String)
        send(CDVPluginResult(status: .ok), to: command.callbackId)
    }

    @objc(loadInterstitial:)
    func loadInterstitial(_ command: CDVInvokedUrlCommand) {
        BoostNetwork.loadInterstitial()
        send(CDVPluginResult(status: .ok), to: command.callbackId)
    }

    @objc(isInterstitialReady:)
    func isInterstitialReady(_ command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async {
            self.send(CDVPluginResult(status: .ok, messageAs: BoostNetwork.isInterstitialReady), to: command.callbackId)
        }
    }

    /// Résolu à la fermeture de l'interstitiel (true), ou aussitôt s'il n'y en a pas de prêt (false)
    @objc(showInterstitial:)
    func showInterstitial(_ command: CDVInvokedUrlCommand) {
        BoostNetwork.showInterstitial { [weak self] shown in
            self?.send(CDVPluginResult(status: .ok, messageAs: shown), to: command.callbackId)
        }
    }

    @objc(hideBanner:)
    func hideBanner(_ command: CDVInvokedUrlCommand) {
        BoostNetwork.hideBanner()
        send(CDVPluginResult(status: .ok), to: command.callbackId)
    }

    @objc(setEndpoint:)
    func setEndpoint(_ command: CDVInvokedUrlCommand) {
        guard let apiUrl = command.argument(at: 0) as? String, let apiKey = command.argument(at: 1) as? String else {
            send(CDVPluginResult(status: .error, messageAs: "apiUrl et apiKey sont obligatoires"), to: command.callbackId)
            return
        }
        BoostNetwork.setEndpoint(apiUrl: apiUrl, apiKey: apiKey)
        send(CDVPluginResult(status: .ok), to: command.callbackId)
    }

    /// Rappel conservé : un résultat par événement de la bannière.
    @objc(onEvent:)
    func onEvent(_ command: CDVInvokedUrlCommand) {
        eventCallbackId = command.callbackId
        BoostNetwork.onEvent { [weak self] event in
            guard let self = self, let callbackId = self.eventCallbackId else { return }
            let result = CDVPluginResult(status: .ok, messageAs: event.dictionary)
            result.setKeepCallbackAs(true)
            self.send(result, to: callbackId)
        }
        let result = CDVPluginResult(status: .noResult)
        result.setKeepCallbackAs(true)
        send(result, to: command.callbackId)
    }

    private func send(_ result: CDVPluginResult, to callbackId: String) {
        commandDelegate.send(result, callbackId: callbackId)
    }
}

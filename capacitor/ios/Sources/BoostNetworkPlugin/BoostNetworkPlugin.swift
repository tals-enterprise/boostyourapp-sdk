import Capacitor
import Foundation

/// Pont Capacitor : transmet les appels au cœur iOS du SDK (dossier Core, copié depuis sdk/ios), sans logique propre.
@objc(BoostNetworkPlugin)
public class BoostNetworkPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "BoostNetworkPlugin"
    public let jsName = "BoostNetwork"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "initialize", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "showBanner", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hideBanner", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setStyle", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "loadInterstitial", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isInterstitialReady", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "showInterstitial", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setEndpoint", returnType: CAPPluginReturnPromise)
    ]

    override public func load() {
        BoostNetwork.onEvent { [weak self] event in
            self?.notifyListeners("bannerEvent", data: event.dictionary)
        }
    }

    @objc func initialize(_ call: CAPPluginCall) {
        guard let appKey = call.getString("appKey"), !appKey.isEmpty else {
            call.reject("appKey manquante", "invalid_argument")
            return
        }
        BoostNetwork.initialize(appKey: appKey)
        call.resolve()
    }

    @objc func showBanner(_ call: CAPPluginCall) {
        BoostNetwork.showBanner(call.getString("position") ?? "bottom")
        call.resolve()
    }

    @objc func setStyle(_ call: CAPPluginCall) {
        BoostNetwork.setStyle(call.getString("style") ?? "standard", palette: call.getString("palette"))
        call.resolve()
    }

    @objc func loadInterstitial(_ call: CAPPluginCall) {
        BoostNetwork.loadInterstitial()
        call.resolve()
    }

    @objc func isInterstitialReady(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            call.resolve(["ready": BoostNetwork.isInterstitialReady])
        }
    }

    /// Résolu à la fermeture de l'interstitiel (true), ou aussitôt s'il n'y en a pas de prêt (false)
    @objc func showInterstitial(_ call: CAPPluginCall) {
        BoostNetwork.showInterstitial { shown in
            call.resolve(["shown": shown])
        }
    }

    @objc func hideBanner(_ call: CAPPluginCall) {
        BoostNetwork.hideBanner()
        call.resolve()
    }

    @objc func setEndpoint(_ call: CAPPluginCall) {
        guard let apiUrl = call.getString("apiUrl"), let apiKey = call.getString("apiKey") else {
            call.reject("apiUrl et apiKey sont obligatoires", "invalid_argument")
            return
        }
        BoostNetwork.setEndpoint(apiUrl: apiUrl, apiKey: apiKey)
        call.resolve()
    }
}

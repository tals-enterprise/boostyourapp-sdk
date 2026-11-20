package com.boostyourapp.capacitor

import com.boostyourapp.network.BoostEvent
import com.boostyourapp.network.BoostNetwork
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin

/** Pont Capacitor : transmet les appels au cœur Android du SDK, sans logique propre. */
@CapacitorPlugin(name = "BoostNetwork")
class BoostNetworkPlugin : Plugin() {

    override fun load() {
        BoostNetwork.onEvent { event -> notifyListeners(EVENT, toJSObject(event)) }
    }

    @PluginMethod
    fun initialize(call: PluginCall) {
        val appKey = call.getString("appKey")
        if (appKey.isNullOrBlank()) {
            call.reject("appKey manquante", "invalid_argument")
            return
        }
        // L'activité de Capacitor est déjà affichée : le SDK s'y attache directement
        BoostNetwork.init(activity ?: context, appKey)
        call.resolve()
    }

    @PluginMethod
    fun showBanner(call: PluginCall) {
        BoostNetwork.showBanner(call.getString("position") ?: "bottom")
        call.resolve()
    }

    @PluginMethod
    fun setStyle(call: PluginCall) {
        BoostNetwork.setStyle(call.getString("style") ?: "standard", call.getString("palette"))
        call.resolve()
    }

    @PluginMethod
    fun loadInterstitial(call: PluginCall) {
        BoostNetwork.loadInterstitial()
        call.resolve()
    }

    @PluginMethod
    fun isInterstitialReady(call: PluginCall) {
        call.resolve(JSObject().put("ready", BoostNetwork.isInterstitialReady()))
    }

    /** Résolu à la fermeture de l'interstitiel (true), ou aussitôt s'il n'y en a pas de prêt (false) */
    @PluginMethod
    fun showInterstitial(call: PluginCall) {
        BoostNetwork.showInterstitial { shown -> call.resolve(JSObject().put("shown", shown)) }
    }

    @PluginMethod
    fun hideBanner(call: PluginCall) {
        BoostNetwork.hideBanner()
        call.resolve()
    }

    @PluginMethod
    fun setEndpoint(call: PluginCall) {
        val apiUrl = call.getString("apiUrl")
        val apiKey = call.getString("apiKey")
        if (apiUrl.isNullOrBlank() || apiKey.isNullOrBlank()) {
            call.reject("apiUrl et apiKey sont obligatoires", "invalid_argument")
            return
        }
        BoostNetwork.setEndpoint(apiUrl, apiKey)
        call.resolve()
    }

    /** Même forme que sur iOS : { type, adId } ou { type, code, message } */
    private fun toJSObject(event: BoostEvent): JSObject {
        val data = JSObject()
        data.put("type", event.type)
        event.adIdOrNull?.let { data.put("adId", it) }
        if (event is BoostEvent.Error) {
            data.put("code", event.code)
            data.put("message", event.message)
        }
        return data
    }

    private companion object {
        const val EVENT = "bannerEvent"
    }
}

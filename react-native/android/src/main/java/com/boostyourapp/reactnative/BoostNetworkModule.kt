package com.boostyourapp.reactnative

import android.content.pm.PackageManager
import com.boostyourapp.network.BoostEvent
import com.boostyourapp.network.BoostNetwork
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.WritableMap
import com.facebook.react.modules.core.DeviceEventManagerModule

/** Pont React Native : transmet les appels au cœur Android du SDK, sans logique propre. */
class BoostNetworkModule(context: ReactApplicationContext) : ReactContextBaseJavaModule(context) {

    init {
        BoostNetwork.onEvent { event -> emit(event) }
    }

    override fun getName(): String = NAME

    override fun invalidate() {
        BoostNetwork.onEvent(null)
        super.invalidate()
    }

    /** appKey facultative : à défaut, celle du manifeste (config plugin Expo, meta-data com.boostyourapp.APP_KEY). */
    @ReactMethod
    fun start(appKey: String?, promise: Promise) {
        val key = appKey?.takeIf { it.isNotBlank() } ?: manifestAppKey()
        if (key.isNullOrBlank()) {
            promise.reject("invalid_argument", "appKey manquante")
            return
        }
        // L'activité de React Native est déjà affichée : le SDK s'y attache directement
        BoostNetwork.init(reactApplicationContext.currentActivity ?: reactApplicationContext, key)
        promise.resolve(null)
    }

    @ReactMethod
    fun showBanner(position: String?, promise: Promise) {
        BoostNetwork.showBanner(position ?: "bottom")
        promise.resolve(null)
    }

    @ReactMethod
    fun setStyle(style: String, palette: String?, promise: Promise) {
        BoostNetwork.setStyle(style, palette)
        promise.resolve(null)
    }

    @ReactMethod
    fun loadInterstitial(promise: Promise) {
        BoostNetwork.loadInterstitial()
        promise.resolve(null)
    }

    @ReactMethod
    fun isInterstitialReady(promise: Promise) {
        promise.resolve(BoostNetwork.isInterstitialReady())
    }

    /** Résolu à la fermeture de l'interstitiel (true), ou aussitôt s'il n'y en a pas de prêt (false) */
    @ReactMethod
    fun showInterstitial(promise: Promise) {
        BoostNetwork.showInterstitial { shown -> promise.resolve(shown) }
    }

    @ReactMethod
    fun hideBanner(promise: Promise) {
        BoostNetwork.hideBanner()
        promise.resolve(null)
    }

    @ReactMethod
    fun setEndpoint(apiUrl: String, apiKey: String, promise: Promise) {
        BoostNetwork.setEndpoint(apiUrl, apiKey)
        promise.resolve(null)
    }

    // Requis par NativeEventEmitter
    @ReactMethod
    fun addListener(eventName: String) = Unit

    @ReactMethod
    fun removeListeners(count: Double) = Unit

    /** Même forme que sur iOS : { type, adId } ou { type, code, message } */
    private fun emit(event: BoostEvent) {
        if (!reactApplicationContext.hasActiveReactInstance()) return
        val data: WritableMap = Arguments.createMap()
        data.putString("type", event.type)
        event.adIdOrNull?.let { data.putString("adId", it) }
        if (event is BoostEvent.Error) {
            data.putString("code", event.code)
            data.putString("message", event.message)
        }
        reactApplicationContext
            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit(EVENT, data)
    }

    private fun manifestAppKey(): String? = try {
        val context = reactApplicationContext
        @Suppress("DEPRECATION")
        context.packageManager.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
            .metaData?.getString(APP_KEY_META_DATA)
    } catch (e: PackageManager.NameNotFoundException) {
        null
    }

    companion object {
        const val NAME = "BoostNetwork"
        const val EVENT = "BoostNetworkEvent"
        const val APP_KEY_META_DATA = "com.boostyourapp.APP_KEY"
    }
}

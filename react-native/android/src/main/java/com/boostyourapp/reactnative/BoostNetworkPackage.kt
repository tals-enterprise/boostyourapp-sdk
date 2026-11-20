package com.boostyourapp.reactnative

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager

/**
 * Module classique (pas de TurboModule) : pris en charge par la couche de compatibilité de la nouvelle
 * architecture, de React Native 0.73 aux versions actuelles.
 */
class BoostNetworkPackage : ReactPackage {
    @Suppress("OVERRIDE_DEPRECATION")
    override fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> =
        listOf(BoostNetworkModule(reactContext))

    override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> = emptyList()
}

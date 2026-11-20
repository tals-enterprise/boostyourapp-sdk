package com.boostyourapp.sample

import android.app.Application
import android.util.Log
import com.boostyourapp.network.BoostNetwork

class SampleApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        // Une app normale n'appelle que init() : setEndpoint() sert ici à viser un serveur de test
        BoostNetwork.setEndpoint(BuildConfig.API_URL, BuildConfig.API_KEY)
        BoostNetwork.init(this, BuildConfig.APP_KEY)
        // Facultatif : style et couleurs des pubs (standard par défaut)
        BoostNetwork.setStyle("dynamic", "ocean")
        // Facultatif : un interstitiel prêt dès le lancement
        BoostNetwork.loadInterstitial()
        BoostNetwork.onEvent { event -> Log.i("BoostSample", "Événement : $event") }
    }
}

package com.boostyourapp.network

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.UUID

/**
 * Point d'entrée du SDK BoostYourApp.
 *
 * ```kotlin
 * BoostNetwork.init(context, "bya_…")   // une fois, idéalement dans Application.onCreate()
 * BoostNetwork.setStyle("dynamic", "neon") // facultatif : style et couleurs des pubs (standard par défaut)
 * BoostNetwork.showBanner("bottom")      // ou "top"
 * BoostNetwork.hideBanner()
 * BoostNetwork.loadInterstitial()        // facultatif : prépare un interstitiel dès le lancement
 * BoostNetwork.showInterstitial { shown -> nextLevel() } // pub plein écran, entre deux niveaux par exemple
 * BoostNetwork.onEvent { event -> … }    // facultatif : loaded, clicked, interstitialShown/Closed, error
 * ```
 *
 * Les méthodes peuvent être appelées depuis n'importe quel thread (ponts des plugins) :
 * elles s'exécutent sur le thread principal.
 */
object BoostNetwork {

    private const val TAG = "BoostNetwork"
    private const val PREFERENCES = "com.boostyourapp.network"
    private const val KEY_INSTALLATION_ID = "installation_id"

    private val main = Handler(Looper.getMainLooper())
    @Volatile
    private var controller: BannerController? = null
    private var listener: BoostEventListener? = null
    private var apiUrl: String = BoostConfig.API_URL
    private var apiKey: String = BoostConfig.API_KEY
    private var style: String? = null
    private var palette: String? = null

    /** Version du SDK. */
    @JvmStatic
    val version: String
        get() = BoostConfig.SDK_VERSION

    /**
     * Initialise le SDK avec la clé de l'app (tableau de bord BoostYourApp). Les appels suivants sont ignorés.
     * Si [context] est une activité déjà affichée, la bannière pourra s'y afficher immédiatement.
     */
    @JvmStatic
    fun init(context: Context, appKey: String) = onMain {
        if (controller != null) {
            Log.w(TAG, "BoostNetwork.init() déjà appelé")
            return@onMain
        }
        val application = context.applicationContext as Application
        val store = PreferencesStore(application.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE))
        // Identifiant d'installation : UUID aléatoire, sans lien avec l'appareil ni l'identifiant publicitaire
        val installationId = store.getString(KEY_INSTALLATION_ID)
            ?: UUID.randomUUID().toString().also { store.putString(KEY_INSTALLATION_ID, it) }

        val created = BannerController(
            app = application,
            appKey = appKey.trim(),
            api = ApiClient(apiUrl, apiKey, BoostConfig.SDK_VERSION),
            store = store,
            installationId = installationId,
            emit = ::dispatch
        )
        application.registerActivityLifecycleCallbacks(created)
        (context as? Activity)?.let(created::adoptActivity)
        created.setStyle(style, palette)
        controller = created
        created.interstitials.preloadIfUsed()
    }

    /**
     * Rendu des pubs dans votre app : [style] "standard" (carte claire) ou "dynamic" (vitrine : fond travaillé, mot
     * surligné, captures en éventail), et [palette], clé d'une couleur de ce style (tableau de bord BoostYourApp,
     * page d'intégration). Sans palette, ou palette inconnue : la première du style. Sans appel : standard.
     * Peut être appelé avant ou après [init].
     */
    @JvmStatic
    @JvmOverloads
    fun setStyle(style: String, palette: String? = null) = onMain {
        this.style = style.trim().lowercase()
        this.palette = palette?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
        controller?.setStyle(this.style, this.palette)
    }

    /** Affiche la bannière en haut ("top") ou en bas ("bottom") de l'écran, au-dessus du contenu de l'app, réduit d'autant. */
    @JvmStatic
    fun showBanner(position: String) = showBanner(BannerPosition.from(position))

    @JvmStatic
    @JvmOverloads
    fun showBanner(position: BannerPosition = BannerPosition.BOTTOM) = onMain {
        val current = controller
        if (current == null) {
            dispatch(BoostEvent.Error("not_initialized", "Appelez BoostNetwork.init() avant showBanner()"))
            return@onMain
        }
        current.show(position)
    }

    @JvmStatic
    fun hideBanner() = onMain { controller?.hide() }

    /**
     * Prépare un interstitiel (facultatif) : appelez-le au lancement si l'app en affiche, pour qu'il soit prêt au
     * premier [showInterstitial]. Ensuite, le SDK en garde un prêt, et en prépare un à chaque lancement.
     */
    @JvmStatic
    fun loadInterstitial() = onMain {
        val current = controller
        if (current == null) {
            dispatch(BoostEvent.Error("not_initialized", "Appelez BoostNetwork.init() avant loadInterstitial()"))
            return@onMain
        }
        current.interstitials.load()
    }

    /** Un interstitiel est prêt et le délai depuis le précédent est écoulé (3 minutes par défaut). */
    @JvmStatic
    fun isInterstitialReady(): Boolean = controller?.interstitials?.isReady() ?: false

    /**
     * Affiche un interstitiel plein écran, dans le style choisi avec [setStyle]. [onFinished] reçoit false aussitôt
     * s'il n'y en a pas de prêt (le SDK en prépare un pour la prochaine fois) ou si le précédent date de moins de
     * 3 minutes, et true quand l'utilisateur le ferme : reprenez alors le cours de l'app. Un interstitiel vu compte
     * davantage qu'une bannière pour la visibilité de votre app.
     */
    @JvmStatic
    @JvmOverloads
    fun showInterstitial(onFinished: InterstitialCallback? = null) = onMain {
        val current = controller
        if (current == null) {
            dispatch(BoostEvent.Error("not_initialized", "Appelez BoostNetwork.init() avant showInterstitial()"))
            onFinished?.onFinished(false)
            return@onMain
        }
        current.interstitials.show(onFinished?.let { callback -> { shown: Boolean -> callback.onFinished(shown) } })
    }

    /** Écoute les événements de la bannière (null pour arrêter). Appelé sur le thread principal. */
    @JvmStatic
    fun onEvent(listener: BoostEventListener?) = onMain { this.listener = listener }

    /**
     * Change le serveur du réseau (tests, environnement de préproduction). À appeler avant [init].
     */
    @JvmStatic
    fun setEndpoint(apiUrl: String, apiKey: String) = onMain {
        if (controller != null) Log.w(TAG, "setEndpoint() doit être appelé avant init()")
        this.apiUrl = apiUrl
        this.apiKey = apiKey
    }

    private fun dispatch(event: BoostEvent) {
        if (event is BoostEvent.Error) Log.w(TAG, "${event.code} : ${event.message}")
        try {
            listener?.onEvent(event)
        } catch (e: Exception) {
            Log.e(TAG, "Erreur dans l'écouteur onEvent", e)
        }
    }

    private inline fun onMain(crossinline block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else main.post { block() }
    }
}

private class PreferencesStore(private val preferences: SharedPreferences) : KeyValueStore {
    override fun getString(key: String): String? = preferences.getString(key, null)

    override fun putString(key: String, value: String?) {
        preferences.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    }
}

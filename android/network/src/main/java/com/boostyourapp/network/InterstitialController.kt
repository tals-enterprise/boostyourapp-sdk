package com.boostyourapp.network

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.ViewGroup

/**
 * Interstitiels : une pub plein écran, affichée quand l'app le demande ([BoostNetwork.showInterstitial]), par exemple
 * entre deux niveaux. Sur le thread principal.
 *
 * - Une pub est gardée prête (demandée au serveur avec p_format = interstitial), au plus 20 minutes : son jeton
 *   expire au bout de 30. Après le premier usage, le SDK en prépare une à chaque lancement.
 * - Au moins `intervalSeconds` (réglage du serveur, 3 minutes par défaut) entre deux interstitiels sur l'appareil ;
 *   avant, la demande est refusée.
 * - Bouton de fermeture au bout de `closeSeconds` (5 s par défaut) ; le retour arrière ferme ensuite.
 * - Vu 1 s en continu (fenêtre au premier plan, animation d'entrée terminée) : son jeton rejoint les affichages en
 *   attente. Un interstitiel vu compte davantage qu'une bannière pour la visibilité de l'app.
 */
internal class InterstitialController(
    private val host: BannerController,
    private val store: KeyValueStore,
    private val images: IconLoader,
    private val clock: () -> Long,
    private val emit: (BoostEvent) -> Unit
) {
    private val main = Handler(Looper.getMainLooper())

    // Lus par isReady() depuis n'importe quel thread
    @Volatile private var ad: Ad? = null
    @Volatile private var loadedAt = 0L
    @Volatile private var config: InterstitialConfig = loadConfig()
    @Volatile private var lastShownAt = store.getString(KEY_SHOWN_AT)?.toLongOrNull() ?: 0L
    @Volatile private var showing: Showing? = null

    private var loading = false
    /** Pas de nouvelle demande avant (échec ou aucune pub disponible) */
    private var nextLoadAt = 0L

    private class Showing(
        val ad: Ad,
        val activity: Activity,
        val dialog: Dialog,
        val view: InterstitialView,
        val onFinished: ((Boolean) -> Unit)?
    ) {
        var visibleSince = 0L
        var counted = false
    }

    private val tick = object : Runnable {
        override fun run() {
            val session = showing ?: return
            if (session.counted) return
            val visible = session.dialog.isShowing && host.foreground && session.view.fullyShown &&
                session.dialog.window?.decorView?.hasWindowFocus() == true
            val now = SystemClock.uptimeMillis()
            when {
                !visible -> session.visibleSince = 0L
                session.visibleSince == 0L -> session.visibleSince = now
                now - session.visibleSince >= VISIBLE_MS -> {
                    session.counted = true
                    host.recordImpression(session.ad.token)
                    return
                }
            }
            main.postDelayed(this, TICK_MS)
        }
    }

    // --- API ---------------------------------------------------------------------------------------------

    /** Une pub est prête et l'intervalle depuis le dernier interstitiel est écoulé. */
    fun isReady(): Boolean = showing == null && freshAd() != null && intervalElapsed()

    /** L'app utilise les interstitiels : en préparer un, et en préparer un à chaque lancement. */
    fun load() {
        markUsed()
        fetchIfNeeded()
    }

    /** Lancement : prépare un interstitiel si l'app en a déjà affiché. */
    fun preloadIfUsed() {
        if (store.getString(KEY_USED) != null) fetchIfNeeded()
    }

    /**
     * Affiche l'interstitiel s'il est prêt. [onFinished] reçoit false aussitôt sinon (aucune pub prête, intervalle
     * pas écoulé, app en arrière-plan), ou true à sa fermeture.
     */
    fun show(onFinished: ((Boolean) -> Unit)?) {
        markUsed()
        val current = freshAd()
        val activity = host.activity
        if (showing != null || current == null || !intervalElapsed() || activity == null || !host.foreground || host.stopped) {
            fetchIfNeeded()
            onFinished?.invoke(false)
            return
        }

        ad = null
        lastShownAt = clock()
        store.putString(KEY_SHOWN_AT, lastShownAt.toString())

        val view = InterstitialView(activity, images, current, current.look ?: host.currentLook, config.closeSeconds)
        val dialog = Dialog(activity, android.R.style.Theme_DeviceDefault_NoActionBar_Fullscreen)
        val session = Showing(current, activity, dialog, view, onFinished)
        view.onClose = { close(session) }
        view.onClosable = { dialog.setCancelable(true) }
        view.onAdClick = {
            host.click(current)
            close(session)
        }
        dialog.setCancelable(false)
        dialog.setOnCancelListener { close(session) }
        dialog.setContentView(view, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        dialog.window?.apply {
            setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        }
        try {
            dialog.show()
        } catch (e: Exception) {
            // Activité en cours de fermeture : la pub reste disponible
            ad = current
            onFinished?.invoke(false)
            return
        }
        showing = session
        emit(BoostEvent.InterstitialShown(current.id))
        main.post(tick)
    }

    /** L'activité de l'interstitiel est détruite (rotation, fermeture) : il se ferme avec elle. */
    fun onActivityDestroyed(activity: Activity) {
        showing?.takeIf { it.activity === activity }?.let(::close)
    }

    // --- Interne -------------------------------------------------------------------------------------------

    private fun close(session: Showing) {
        if (showing !== session) return
        showing = null
        main.removeCallbacks(tick)
        session.view.stop()
        try {
            if (session.dialog.isShowing) session.dialog.dismiss()
        } catch (e: Exception) {
            // Fenêtre déjà retirée avec l'activité
        }
        emit(BoostEvent.InterstitialClosed(session.ad.id))
        session.onFinished?.invoke(true)
        // Le suivant, prêt pour la prochaine demande (et envoi de l'affichage qui vient d'être compté)
        fetchIfNeeded()
    }

    private fun fetchIfNeeded() {
        if (loading || host.stopped || freshAd() != null) return
        if (SystemClock.elapsedRealtime() < nextLoadAt) return
        loading = true
        host.requestInterstitial { response ->
            loading = false
            response?.interstitial?.let {
                config = it
                store.putString(KEY_CONFIG, ApiJson.interstitialJson(it).toString())
            }
            val received = response?.ads?.firstOrNull()
            if (received != null) {
                ad = received
                loadedAt = clock()
                nextLoadAt = 0L
            } else {
                nextLoadAt = SystemClock.elapsedRealtime() + RETRY_MS
            }
        }
    }

    private fun freshAd(): Ad? = ad?.takeIf { clock() - loadedAt in 0 until MAX_AGE_MS }

    /** Horloge reculée (changement d'heure manuel) : l'intervalle est considéré écoulé */
    private fun intervalElapsed(): Boolean {
        val elapsed = clock() - lastShownAt
        return elapsed < 0 || elapsed >= config.intervalSeconds * 1000L
    }

    private fun markUsed() {
        if (store.getString(KEY_USED) == null) store.putString(KEY_USED, "1")
    }

    private fun loadConfig(): InterstitialConfig = try {
        store.getString(KEY_CONFIG)?.let { ApiJson.parseInterstitial(org.json.JSONObject(it)) } ?: InterstitialConfig()
    } catch (e: Exception) {
        InterstitialConfig()
    }

    private companion object {
        const val TICK_MS = 100L
        const val VISIBLE_MS = 1_000L
        /** Jeton valable 30 minutes côté serveur */
        const val MAX_AGE_MS = 20 * 60_000L
        const val RETRY_MS = 60_000L
        const val KEY_USED = "interstitial_used"
        const val KEY_SHOWN_AT = "interstitial_shown_at"
        const val KEY_CONFIG = "interstitial_config"
    }
}

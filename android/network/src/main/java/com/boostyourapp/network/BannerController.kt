package com.boostyourapp.network

import android.app.Activity
import android.app.Application
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.widget.FrameLayout
import java.lang.ref.WeakReference
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.min

/**
 * Cœur du SDK, entièrement sur le thread principal (les appels réseau passent par [executor]).
 *
 * - Suit l'activité au premier plan et y superpose la bannière (overlay dans android.R.id.content).
 * - Affiche chaque pub pendant refreshSeconds, puis la suivante ; redemande des pubs quand la file se vide.
 * - Mesure la visibilité toutes les 100 ms ; une pub visible 1 s continue rejoint les affichages en attente.
 * - Envoie les affichages avec la demande de pubs suivante, et à la mise en arrière-plan.
 * - Réserve la place de la bannière : le contenu de l'app est réduit d'autant (marge intérieure de
 *   android.R.id.content), la bannière ne masque donc rien.
 * - Affiche les pubs dans le rendu choisi par l'app ([setStyle]), résolu par le serveur et gardé pour le lancement suivant.
 * - Partage avec les interstitiels ([InterstitialController]) l'activité suivie, le rendu, les affichages en attente
 *   et les clics.
 */
internal class BannerController(
    private val app: Application,
    private val appKey: String,
    private val api: ApiClient,
    private val store: KeyValueStore,
    private val installationId: String,
    private val emit: (BoostEvent) -> Unit
) : Application.ActivityLifecycleCallbacks {

    private val main = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val icons = IconLoader()
    private val wallClock = { System.currentTimeMillis() }
    private val queue = AdQueue(wallClock)
    private val pending = PendingImpressions(store, wallClock)
    private val creatives = CreativeCache(store)
    private val tracker = ViewabilityTracker()
    /** Pubs plein écran, affichées à la demande de l'app */
    val interstitials = InterstitialController(this, store, icons, wallClock, emit)

    private var position = BannerPosition.BOTTOM
    private var wantShown = false
    private var activityRef: WeakReference<Activity>? = null
    private var startedActivities = 0
    private var banner: BannerView? = null
    private var currentAd: Ad? = null
    private var refreshSeconds = 60

    /** Rendu demandé par l'app (setStyle) et rendu résolu par le serveur, gardé d'un lancement à l'autre */
    private var requestedStyle: String? = null
    private var requestedPalette: String? = null
    private var look: Look = loadLook()

    /** Contenu de l'activité réduit pour la bannière, et sa marge intérieure d'origine */
    private var reservedContent: WeakReference<FrameLayout>? = null
    private var originalPadding = IntArray(4)
    private var originalClipToPadding = true
    private var reservedSpace = 0

    private var fetching = false
    /** appKey inconnue : plus aucun appel */
    var stopped = false
        private set
    private var retryAt = 0L
    private var backoffMs = 0L

    val foreground get() = startedActivities > 0

    /** Activité au premier plan, pour les interstitiels */
    val activity: Activity? get() = activityRef?.get()?.takeUnless { it.isFinishing }

    /** Rendu courant des pubs (bannière et interstitiel) */
    val currentLook: Look get() = look

    private val rotate = Runnable { advance() }
    // Pas de nouvel essai en arrière-plan : la demande partira au retour au premier plan
    private val retry = Runnable { if (wantShown && currentAd == null && foreground) fetch(force = true) }
    private val tick = object : Runnable {
        override fun run() {
            measureViewability()
            main.postDelayed(this, TICK_MS)
        }
    }

    // --- API ---------------------------------------------------------------------------------

    fun show(newPosition: BannerPosition) {
        if (stopped) return
        val moved = newPosition != position
        position = newPosition
        wantShown = true
        attach(relayout = moved)
        if (currentAd == null) advance()
    }

    /**
     * Style (standard, dynamic) et palette des pubs. Appliqué aussitôt avec les couleurs par défaut du style, puis
     * avec celles de la palette dès la réponse du serveur.
     */
    fun setStyle(style: String?, palette: String?) {
        if (style == requestedStyle && palette == requestedPalette) return
        requestedStyle = style
        requestedPalette = palette
        val key = lookKey()
        if (store.getString(KEY_LOOK_REQUEST) != key) {
            look = Look(style = style ?: "standard")
            currentAd?.let { ad -> banner?.bind(ad, look) }
        }
        if (!stopped && !fetching) fetch(force = true, reportOnly = true)
    }

    fun hide() {
        wantShown = false
        main.removeCallbacks(rotate)
        main.removeCallbacks(retry)
        detach()
        currentAd = null
    }

    /** init() appelé depuis une activité déjà démarrée : elle ne repassera pas par onActivityStarted. */
    fun adoptActivity(activity: Activity) {
        activityRef = WeakReference(activity)
        if (startedActivities == 0) startedActivities = 1
    }

    // --- Rotation et chargement ----------------------------------------------------------------

    private fun advance() {
        main.removeCallbacks(rotate)
        if (!wantShown || !foreground || stopped) {
            currentAd = null
            return
        }

        val ad = queue.poll()
        currentAd = ad
        tracker.reset()

        val view = banner
        if (ad == null) {
            view?.visibility = View.GONE
            fetch()
            return
        }

        if (view != null) {
            val wasHidden = view.visibility != View.VISIBLE
            view.visibility = View.VISIBLE
            // Le style dynamique est plus haut : la bannière suit la hauteur du style de la pub
            view.bind(ad, look)
            if (wasHidden) view.playEnterAnimation(fromTop = position == BannerPosition.TOP)
        }
        emit(BoostEvent.Loaded(ad.id))
        main.postDelayed(rotate, refreshSeconds * 1000L)

        // Dernière pub de la file : on prépare la suite (et on envoie les affichages en attente)
        if (queue.size == 0) fetch()
    }

    /** [reportOnly] : seulement envoyer les affichages en attente, sans recevoir de pubs (mise en arrière-plan) */
    private fun fetch(force: Boolean = false, reportOnly: Boolean = false) {
        if (fetching || stopped) return
        if (!force && SystemClock.elapsedRealtime() < retryAt) return
        fetching = true

        val impressions = pending.take(MAX_IMPRESSIONS_PER_CALL)
        val request = NextRequest(
            appKey, installationId, deviceInfo(), queue.recentIds(), impressions,
            count = if (reportOnly) 0 else null,
            cached = if (reportOnly) null else creatives.versions(),
            style = requestedStyle,
            palette = requestedPalette
        )
        executor.execute {
            val result = runCatching { api.next(request, creatives::get) }
            main.post { onFetched(result, impressions, reportOnly) }
        }
    }

    private fun onFetched(result: Result<NextResponse>, sent: List<String>, reportOnly: Boolean) {
        fetching = false

        result.onSuccess { response ->
            pending.confirm(sent)
            backoffMs = 0
            retryAt = 0
            refreshSeconds = response.refreshSeconds
            response.look?.let(::updateLook)
            creatives.putAll(response.ads)
            queue.addAll(response.ads)
            if (response.ads.isEmpty() && !reportOnly) scheduleRetry(refreshSeconds * 1000L)
            if (wantShown && currentAd == null) advance()
        }

        result.onFailure { error ->
            val code = handleFailure(error, sent)
            when (code) {
                "unknown_app" -> hide()
                "suspended" -> {
                    banner?.visibility = View.GONE
                    currentAd = null
                    scheduleRetry(SUSPENDED_RETRY_MS)
                }
                else -> {
                    backoffMs = (backoffMs * 2).coerceIn(MIN_BACKOFF_MS, MAX_BACKOFF_MS)
                    scheduleRetry(backoffMs)
                }
            }
        }
    }

    /** Erreur d'une demande (bannières ou interstitiel) : jetons à garder ou non, arrêt si appKey inconnue */
    private fun handleFailure(error: Throwable, sent: List<String>): String {
        val code = (error as? ApiException)?.code ?: "network"
        when (code) {
            "unknown_app" -> {
                stopped = true
                Log.e(TAG, "appKey inconnue : vérifiez la clé passée à BoostNetwork.init()")
            }
            // Les affichages d'une app suspendue ne comptent plus : inutile de les garder
            "suspended" -> pending.confirm(sent)
            else -> pending.release(sent)
        }
        Log.w(TAG, "Échec de network_next : $code")
        emit(BoostEvent.Error(code, error.message ?: code))
        return code
    }

    /**
     * Demande un interstitiel (une pub, sans cache du contenu), avec les affichages en attente. [onResult] reçoit la
     * réponse, ou null en cas d'échec (erreur déjà signalée), sur le thread principal.
     */
    fun requestInterstitial(onResult: (NextResponse?) -> Unit) {
        if (stopped) return onResult(null)
        val impressions = pending.take(MAX_IMPRESSIONS_PER_CALL)
        val request = NextRequest(
            appKey, installationId, deviceInfo(), queue.recentIds(), impressions,
            count = 1, style = requestedStyle, palette = requestedPalette, format = "interstitial"
        )
        executor.execute {
            val result = runCatching { api.next(request) }
            main.post {
                result.onSuccess { response ->
                    pending.confirm(impressions)
                    response.look?.let(::updateLook)
                    onResult(response)
                }.onFailure { error ->
                    if (handleFailure(error, impressions) == "unknown_app") hide()
                    onResult(null)
                }
            }
        }
    }

    /** Pub (bannière ou interstitiel) réellement vue : son jeton partira avec la demande suivante */
    fun recordImpression(token: String) = pending.add(token)

    private fun scheduleRetry(delayMs: Long) {
        retryAt = SystemClock.elapsedRealtime() + delayMs
        main.removeCallbacks(retry)
        main.postDelayed(retry, delayMs)
    }

    /** Mise en arrière-plan : on envoie les affichages en attente sans attendre la prochaine demande. */
    private fun flush() {
        if (!stopped && !fetching && pending.available > 0) fetch(force = true, reportOnly = true)
    }

    // --- Visibilité ------------------------------------------------------------------------------

    private fun measureViewability() {
        val ad = currentAd ?: return
        val view = banner ?: return
        val params = view.layoutParams ?: return
        val sample = ViewabilityProbe.sample(view, params.width, params.height, foreground)
        if (tracker.onSample(sample, SystemClock.uptimeMillis())) {
            recordImpression(ad.token)
        }
    }

    // --- Overlay ---------------------------------------------------------------------------------

    private fun attach(relayout: Boolean = false) {
        if (!wantShown || stopped) return
        val activity = activityRef?.get() ?: return
        if (activity.isFinishing) return
        val content = activity.findViewById<ViewGroup>(android.R.id.content) as? FrameLayout ?: return

        var view = banner
        if (view == null || view.context !== activity) {
            view?.let { removeFromParent(it); it.clear() }
            view = BannerView(activity, icons).apply {
                visibility = View.GONE
                setOnClickListener { onClick() }
                setOnApplyWindowInsetsListener { v, insets ->
                    applyInsets(v, insets)
                    insets
                }
            }
            banner = view
            currentAd?.let {
                view.visibility = View.VISIBLE
                view.bind(it, look)
            }
        }

        if (view.parent !== content || relayout) reserveSpace(content)
        if (view.parent !== content) {
            removeFromParent(view)
            content.addView(view, layoutParams(activity))
        } else if (relayout) {
            view.layoutParams = layoutParams(activity)
        }
        view.bringToFront()
        view.requestApplyInsets()

        main.removeCallbacks(tick)
        main.post(tick)
    }

    private fun detach() {
        main.removeCallbacks(tick)
        banner?.let(::removeFromParent)
        releaseSpace()
    }

    /**
     * Réduit le contenu de l'activité de la place de la bannière (hauteur et marges) par sa marge intérieure : les
     * vues de l'app (et les fragments ajoutés plus tard) s'arrêtent au-dessus de la bannière. La bannière, elle,
     * se place dans cette marge (marge négative, clipToPadding désactivé). Les barres système restent gérées par
     * l'app (edge-to-edge) : seule la place de la bannière est ajoutée.
     */
    private fun reserveSpace(content: FrameLayout) {
        releaseSpace()
        val density = content.resources.displayMetrics.density
        reservedSpace = BannerView.heightPx(content.context) + 2 * (BannerView.MARGIN_DP * density).toInt()
        originalPadding = intArrayOf(content.paddingLeft, content.paddingTop, content.paddingRight, content.paddingBottom)
        originalClipToPadding = content.clipToPadding
        val (left, top, right, bottom) = originalPadding.toList()
        if (position == BannerPosition.TOP) {
            content.setPadding(left, top + reservedSpace, right, bottom)
        } else {
            content.setPadding(left, top, right, bottom + reservedSpace)
        }
        content.clipToPadding = false
        reservedContent = WeakReference(content)
    }

    private fun releaseSpace() {
        val content = reservedContent?.get()
        reservedContent = null
        if (content != null) {
            val (left, top, right, bottom) = originalPadding.toList()
            content.setPadding(left, top, right, bottom)
            content.clipToPadding = originalClipToPadding
        }
        reservedSpace = 0
    }

    // --- Rendu ---------------------------------------------------------------------------------------

    private fun lookKey() = "${requestedStyle.orEmpty()}|${requestedPalette.orEmpty()}"

    private fun loadLook(): Look = try {
        store.getString(KEY_LOOK)?.let { ApiJson.parseLook(org.json.JSONObject(it)) } ?: Look()
    } catch (e: Exception) {
        Look()
    }

    /** Rendu résolu par le serveur : appliqué à la pub affichée et gardé pour le lancement suivant */
    private fun updateLook(newLook: Look) {
        store.putString(KEY_LOOK, ApiJson.lookJson(newLook).toString())
        store.putString(KEY_LOOK_REQUEST, lookKey())
        if (newLook == look) return
        look = newLook
        currentAd?.let { ad -> banner?.bind(ad, look) }
    }

    private fun layoutParams(context: Context): FrameLayout.LayoutParams {
        val density = context.resources.displayMetrics.density
        val margin = (BannerView.MARGIN_DP * density).toInt()
        val width = min(context.resources.displayMetrics.widthPixels - 2 * margin, (BannerView.MAX_WIDTH_DP * density).toInt())
        val gravity = Gravity.CENTER_HORIZONTAL or if (position == BannerPosition.TOP) Gravity.TOP else Gravity.BOTTOM
        // Dans la place réservée (marge intérieure du contenu) : marge négative
        return FrameLayout.LayoutParams(width, BannerView.heightPx(context), gravity).apply {
            topMargin = margin - if (position == BannerPosition.TOP) reservedSpace else 0
            bottomMargin = margin - if (position == BannerPosition.BOTTOM) reservedSpace else 0
        }
    }

    /** Apps en plein écran (edge-to-edge) : la bannière reste au-dessus des barres système. */
    @Suppress("DEPRECATION")
    private fun applyInsets(view: View, insets: WindowInsets) {
        val params = view.layoutParams as? FrameLayout.LayoutParams ?: return
        val top = position == BannerPosition.TOP
        val inset = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            if (top) bars.top else bars.bottom
        } else {
            if (top) insets.systemWindowInsetTop else insets.systemWindowInsetBottom
        }
        val margin = (BannerView.MARGIN_DP * view.resources.displayMetrics.density).toInt() + inset - reservedSpace
        val changed = if (top) params.topMargin != margin else params.bottomMargin != margin
        if (changed) {
            if (top) params.topMargin = margin else params.bottomMargin = margin
            view.layoutParams = params
        }
    }

    private fun removeFromParent(view: View) {
        (view.parent as? ViewGroup)?.removeView(view)
    }

    /** Langue et version majeure du système : langue des textes et statistiques d'audience de l'annonceur. */
    private fun deviceInfo(): DeviceInfo = DeviceInfo(
        lang = Locale.getDefault().toLanguageTag(),
        os = "Android " + Build.VERSION.RELEASE.orEmpty().substringBefore('.')
    )

    // --- Clics ---------------------------------------------------------------------------------------

    private fun onClick() {
        click(currentAd ?: return)
    }

    /** Clic sur une pub (bannière ou interstitiel) : compté par le serveur, qui renvoie l'URL du store à ouvrir */
    fun click(ad: Ad) {
        emit(BoostEvent.Clicked(ad.id))
        executor.execute {
            val result = runCatching { api.click(ad.token, deviceInfo()) }
            main.post {
                result.onSuccess(::openStore).onFailure { error ->
                    val code = (error as? ApiException)?.code ?: "network"
                    emit(BoostEvent.Error(code, error.message ?: code))
                }
            }
        }
    }

    /** Ouvre la fiche : directement dans le Play Store s'il est installé, sinon dans le navigateur. */
    private fun openStore(url: String) {
        val context: Context = activityRef?.get() ?: app
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
        if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (url.startsWith("https://play.google.com/")) {
            try {
                context.startActivity(Intent(intent).setPackage("com.android.vending"))
                return
            } catch (e: ActivityNotFoundException) {
                // Pas de Play Store : navigateur
            }
        }
        try {
            context.startActivity(intent)
        } catch (e: ActivityNotFoundException) {
            Log.w(TAG, "Aucune application pour ouvrir $url")
        }
    }

    // --- Cycle de vie des activités -------------------------------------------------------------------

    override fun onActivityStarted(activity: Activity) {
        startedActivities++
        if (startedActivities == 1 && wantShown) {
            main.post { if (currentAd == null) advance() }
        }
    }

    override fun onActivityResumed(activity: Activity) {
        activityRef = WeakReference(activity)
        if (wantShown) {
            attach()
            if (currentAd == null) advance()
        }
    }

    override fun onActivityPaused(activity: Activity) {
        if (activityRef?.get() === activity) main.removeCallbacks(tick)
    }

    override fun onActivityStopped(activity: Activity) {
        startedActivities = (startedActivities - 1).coerceAtLeast(0)
        if (startedActivities == 0) {
            // La rotation reprendra sur une nouvelle pub au retour au premier plan
            main.removeCallbacks(rotate)
            currentAd = null
            flush()
        }
    }

    override fun onActivityDestroyed(activity: Activity) {
        interstitials.onActivityDestroyed(activity)
        if (banner?.context === activity) {
            banner?.let { removeFromParent(it); it.clear() }
            banner = null
        }
        if (activityRef?.get() === activity) activityRef = null
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit

    private companion object {
        const val TAG = "BoostNetwork"
        const val TICK_MS = 100L
        const val MAX_IMPRESSIONS_PER_CALL = 50
        const val MIN_BACKOFF_MS = 30_000L
        const val MAX_BACKOFF_MS = 5 * 60_000L
        const val SUSPENDED_RETRY_MS = 60 * 60_000L
        const val KEY_LOOK = "look"
        /** Style et palette demandés quand le rendu gardé a été reçu */
        const val KEY_LOOK_REQUEST = "look_request"
    }
}

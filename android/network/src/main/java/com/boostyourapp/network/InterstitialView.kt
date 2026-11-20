package com.boostyourapp.network

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.LightingColorFilter
import android.graphics.Outline
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewOutlineProvider
import android.view.WindowInsets
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

/**
 * Interstitiel : pub plein écran, dans le rendu de l'app (même style et mêmes couleurs que la bannière), sur le
 * modèle de l'aperçu du back-office (BoostFullscreen.vue).
 *
 * - standard : fond uni, grande icône, nom, note, description qui alterne, captures qui défilent, bouton plein ;
 * - dynamic : fond travaillé (dégradé, motif, halo), icône avec onde, nom en majuscules, accroche très grasse au mot
 *   surligné, éventail de 3 grandes captures qui tourne, bouton avec reflet ; un pas toutes les 2,6 s.
 *
 * Bouton de fermeture après [closeSeconds] (compte à rebours). Les captures sont masquées sur un écran bas (paysage).
 * Animations désactivées sur le téléphone : rien ne bouge, les descriptions alternent sans transition.
 */
@SuppressLint("ViewConstructor")
internal class InterstitialView(
    context: Context,
    private val images: IconLoader,
    private val ad: Ad,
    look: Look,
    private val closeSeconds: Int
) : FrameLayout(context) {

    /** Fermeture demandée (bouton ✕) */
    var onClose: (() -> Unit)? = null
    /** Clic sur la pub : bouton, icône, textes ou captures */
    var onAdClick: (() -> Unit)? = null
    /** Le bouton de fermeture vient d'apparaître : le retour arrière peut fermer */
    var onClosable: (() -> Unit)? = null

    /** Animation d'entrée terminée : l'affichage peut commencer à compter */
    var fullyShown = false
        private set

    private val theme = BannerView.Theme.of(look)
    private val dynamic = theme.style == "dynamic"
    private val motion = animationsEnabled()

    /** Défile sur un écran bas (paysage) ; sinon la zone des captures prend la hauteur restante */
    private val scroll = ScrollView(context)
    private val column = LinearLayout(context)
    private val closeButton = TextView(context)
    private val iconBox = FrameLayout(context)
    private val wave = View(context)
    private val icon = ImageView(context)
    private val name = TextView(context)
    private val rating = TextView(context)
    private val plainHook = TextView(context)
    private val hook = HookTextView(context)
    private val media = FrameLayout(context)
    /** Sans captures : le contenu est centré verticalement entre ces deux espaces */
    private val topSpacer = View(context)
    private val bottomSpacer = View(context)
    private val shots = List(min(3, ad.screenshots.size)) { ImageView(context) }
    private val strip = LinearLayout(context)
    private val cta: TextView = if (dynamic) ShineButton(context) else TextView(context)
    private val halo = View(context)

    private var step = 0
    private var remaining = closeSeconds
    private var drift: ValueAnimator? = null
    private var fanAnimator: ValueAnimator? = null
    private var marquee: ValueAnimator? = null
    private var stopped = false

    private val stepper = object : Runnable {
        override fun run() {
            nextStep()
            postDelayed(this, if (dynamic) ShowcaseView.STEP_MS else ad.rotationSeconds * 1000L)
        }
    }

    private val countdown = object : Runnable {
        override fun run() {
            remaining--
            updateCloseButton()
            if (remaining > 0) postDelayed(this, 1000) else onClosable?.invoke()
        }
    }

    init {
        isClickable = true // les touches ne traversent pas vers l'app
        if (dynamic) {
            background = BackdropDrawable().apply {
                set(theme.background, theme.background2, theme.pattern, theme.patternColor)
            }
            halo.alpha = 0.35f
            halo.background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                gradientType = GradientDrawable.RADIAL_GRADIENT
                gradientRadius = dp(150).toFloat()
                colors = intArrayOf(theme.button, Color.TRANSPARENT)
            }
            addView(halo, LayoutParams(dp(300), dp(300)))
        } else {
            setBackgroundColor(theme.background)
        }

        column.orientation = LinearLayout.VERTICAL
        column.gravity = Gravity.CENTER_HORIZONTAL
        column.clipChildren = false
        column.clipToPadding = false
        column.setPadding(dp(24), dp(8), dp(24), dp(24))
        scroll.isFillViewport = true
        scroll.isVerticalScrollBarEnabled = false
        scroll.clipChildren = false
        scroll.addView(column, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT, Gravity.CENTER_HORIZONTAL))
        addView(scroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        column.addView(topBar(), LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, dp(48)))
        column.addView(topSpacer, LinearLayout.LayoutParams(0, 0, 0f))
        buildHeader()
        column.addView(bottomSpacer, LinearLayout.LayoutParams(0, 0, 0f))
        buildMedia()
        buildCta()

        setOnApplyWindowInsetsListener { _, insets -> applyInsets(insets) }

        showHook(animated = false)
        updateCloseButton()
        loadImages()
    }

    /** Contenu hors des barres système et de l'encoche */
    @Suppress("DEPRECATION")
    private fun applyInsets(insets: WindowInsets): WindowInsets {
        val (top, bottom, left, right) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            listOf(bars.top, bars.bottom, bars.left, bars.right)
        } else {
            listOf(insets.systemWindowInsetTop, insets.systemWindowInsetBottom, insets.systemWindowInsetLeft, insets.systemWindowInsetRight)
        }
        setPadding(left, top, right, bottom)
        return insets
    }

    // --- Construction ------------------------------------------------------------------------------

    private fun topBar(): FrameLayout {
        val bar = FrameLayout(context)
        val adLabel = TextView(context).apply {
            text = "Ad"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            setTextColor(withAlpha(theme.text, 0.8f))
            setPadding(dp(8), dp(2), dp(8), dp(2))
            background = GradientDrawable().apply {
                cornerRadius = dp(6).toFloat()
                setColor(withAlpha(theme.text, 0.12f))
            }
        }
        bar.addView(adLabel, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER_VERTICAL or Gravity.START))

        closeButton.gravity = Gravity.CENTER
        closeButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
        closeButton.typeface = Typeface.DEFAULT_BOLD
        closeButton.setTextColor(theme.text)
        closeButton.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(withAlpha(theme.text, 0.12f))
        }
        closeButton.setOnClickListener { if (remaining <= 0) onClose?.invoke() }
        bar.addView(closeButton, LayoutParams(dp(36), dp(36), Gravity.CENTER_VERTICAL or Gravity.END))
        return bar
    }

    private fun buildHeader() {
        val iconSize = dp(96)
        icon.scaleType = ImageView.ScaleType.CENTER_CROP
        icon.outlineProvider = roundOutline { it * 0.22f }
        icon.clipToOutline = true
        icon.elevation = dp(6).toFloat()
        icon.background = GradientDrawable().apply { setColor(withAlpha(theme.text, 0.1f)) }
        iconBox.clipChildren = false
        if (dynamic) {
            wave.alpha = 0f
            wave.background = GradientDrawable().apply {
                cornerRadius = iconSize * 0.22f
                setStroke(dp(3), theme.button)
            }
            iconBox.addView(wave, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        }
        iconBox.addView(icon, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        iconBox.setOnClickListener { onAdClick?.invoke() }
        column.addView(iconBox, LinearLayout.LayoutParams(iconSize, iconSize).apply { topMargin = dp(8) })

        name.gravity = Gravity.CENTER
        name.maxLines = 2
        name.ellipsize = TextUtils.TruncateAt.END
        name.setTextColor(theme.title)
        if (dynamic) {
            name.text = ad.name.uppercase(Locale.forLanguageTag(ad.languageCode))
            name.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            name.typeface = Typeface.DEFAULT_BOLD
            name.letterSpacing = 0.12f
            name.alpha = 0.8f
        } else {
            name.text = ad.name
            name.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            name.typeface = Typeface.DEFAULT_BOLD
        }
        column.addView(name, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = dp(16) })

        if (ad.rating != null && ad.rating > 0) {
            rating.text = String.format(Locale.US, "★ %.1f", ad.rating)
            rating.gravity = Gravity.CENTER
            rating.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            rating.setTextColor(withAlpha(theme.text, 0.85f))
            column.addView(rating, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = dp(4) })
        }

        // Description : accroche surlignée (dynamique) ou texte simple ; hauteur fixe pour que rien ne saute
        val hookView: TextView = if (dynamic) hook else plainHook
        hookView.gravity = Gravity.CENTER
        hookView.ellipsize = TextUtils.TruncateAt.END
        hookView.maxLines = 4
        hookView.setTextColor(theme.text)
        if (dynamic) {
            hook.markColor = theme.button
            hook.markTextColor = theme.buttonText
            hook.typeface = ShowcaseView.heavy(if (theme.font == "serif") Typeface.SERIF else Typeface.DEFAULT)
            hook.setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
            hook.setLineSpacing(dp(2).toFloat(), 1.05f)
        } else {
            plainHook.setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            plainHook.setLineSpacing(dp(2).toFloat(), 1f)
        }
        hookView.setOnClickListener { onAdClick?.invoke() }
        val lines = 4
        val lineHeight = hookView.paint.fontMetricsInt.let { it.descent - it.ascent } + dp(2)
        column.addView(hookView, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, lines * lineHeight + dp(4)).apply {
            topMargin = dp(16)
        })
    }

    private fun buildMedia() {
        media.clipChildren = false
        media.setOnClickListener { onAdClick?.invoke() }
        column.addView(media, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f).apply {
            topMargin = dp(16)
            bottomMargin = dp(16)
        })
        if (shots.isEmpty()) return
        for (shot in shots) {
            shot.scaleType = ImageView.ScaleType.CENTER_CROP
            shot.outlineProvider = roundOutline { dp(if (dynamic) 14 else 12).toFloat() }
            shot.clipToOutline = true
            shot.setBackgroundColor(withAlpha(theme.text, 0.08f))
            shot.elevation = dp(if (dynamic) 8 else 2).toFloat()
        }
        if (dynamic) {
            shots.forEach { media.addView(it) }
        } else {
            // Défilement continu : captures doublées
            strip.orientation = LinearLayout.HORIZONTAL
            strip.clipChildren = false
            media.clipChildren = true
            media.addView(strip, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT, Gravity.CENTER_VERTICAL))
        }
    }

    private fun buildCta() {
        cta.text = ad.cta
        cta.gravity = Gravity.CENTER
        cta.maxLines = 1
        cta.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
        cta.typeface = if (dynamic) ShowcaseView.heavy(Typeface.DEFAULT) else Typeface.DEFAULT_BOLD
        cta.setTextColor(theme.buttonText)
        cta.background = GradientDrawable().apply {
            setColor(theme.button)
            cornerRadius = dp(999).toFloat()
        }
        cta.elevation = dp(4).toFloat()
        cta.setOnClickListener { onAdClick?.invoke() }
        column.addView(cta, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, dp(56)))
    }

    private fun loadImages() {
        ad.iconUrl?.let { url -> images.load(url, dp(96)) { bitmap -> if (!stopped) icon.setImageBitmap(bitmap) } }
        ad.screenshots.take(shots.size).forEachIndexed { i, url ->
            images.load(url, dp(180)) { bitmap -> if (!stopped) shots[i].setImageBitmap(bitmap) }
        }
    }

    // --- Mise en page des captures ---------------------------------------------------------------------

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        post { layoutColumn(w) }
    }

    /** Colonne limitée à 520 dp de large ; captures masquées sur un écran bas */
    private fun layoutColumn(w: Int) {
        val maxWidth = dp(520)
        (column.layoutParams as LayoutParams).let {
            val width = min(w - paddingLeft - paddingRight, maxWidth)
            if (it.width != width) {
                it.width = width
                column.layoutParams = it
            }
        }
        (halo.layoutParams as? LayoutParams)?.let {
            it.leftMargin = (w * 0.1f).toInt()
            it.topMargin = dp(40)
            halo.layoutParams = it
        }
        val heightDp = height / resources.displayMetrics.density
        val showMedia = shots.isNotEmpty() && heightDp >= 560
        media.visibility = if (showMedia) View.VISIBLE else View.GONE
        for (spacer in listOf(topSpacer, bottomSpacer)) {
            val params = spacer.layoutParams as LinearLayout.LayoutParams
            val weight = if (showMedia) 0f else 1f
            if (params.weight != weight) {
                params.weight = weight
                spacer.layoutParams = params
            }
        }
        media.post { placeShots() }
    }

    private fun placeShots() {
        val areaH = media.height
        val areaW = media.width
        if (shots.isEmpty() || areaH <= 0 || areaW <= 0) return
        if (dynamic) {
            val shotH = (areaH * 0.92f).toInt()
            val shotW = min((shotH * 0.48f).toInt(), (areaW * 0.46f).toInt())
            for (shot in shots) {
                shot.layoutParams = LayoutParams(shotW, shotH, Gravity.CENTER)
                shot.pivotX = shotW / 2f
                shot.pivotY = shotH.toFloat()
            }
            zOrderFan()
            placeFan(1f)
        } else {
            val shotH = areaH
            val shotW = (shotH * 0.48f).toInt()
            if (strip.childCount == 0) {
                val perSet = shots.size * (shotW + dp(12))
                // Tout tient à l'écran : captures centrées, immobiles. Sinon assez de copies pour couvrir deux fois la
                // largeur : le défilement boucle sans trou
                val fits = perSet - dp(12) <= areaW
                val sets = if (fits || !motion) 1 else max(2, 2 * ((areaW + perSet - 1) / perSet))
                for (s in 0 until sets) {
                    shots.forEachIndexed { i, original ->
                        val view = if (s == 0) original else ImageView(context).apply {
                            scaleType = ImageView.ScaleType.CENTER_CROP
                            outlineProvider = original.outlineProvider
                            clipToOutline = true
                            setBackgroundColor(withAlpha(theme.text, 0.08f))
                            ad.screenshots.getOrNull(i)?.let { url ->
                                images.load(url, dp(180)) { bitmap -> if (!stopped) setImageBitmap(bitmap) }
                            }
                        }
                        strip.addView(view, LinearLayout.LayoutParams(shotW, shotH).apply {
                            marginEnd = if (fits && i == shots.lastIndex) 0 else dp(12)
                        })
                    }
                }
                // Largeur exacte de la bande, plus large que l'écran quand elle défile
                strip.layoutParams = LayoutParams(
                    if (fits) perSet - dp(12) else perSet * sets, LayoutParams.MATCH_PARENT,
                    if (fits) Gravity.CENTER else Gravity.CENTER_VERTICAL or Gravity.START
                )
                if (!fits) startMarquee(perSet)
            }
        }
    }

    private fun startMarquee(perSet: Int) {
        marquee?.cancel()
        if (!motion) return
        marquee = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = shots.size * 6000L
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener { strip.translationX = -perSet * (it.animatedValue as Float) }
            start()
        }
    }

    // --- Éventail (dynamique) -------------------------------------------------------------------------

    private fun rotateFan() {
        fanAnimator?.cancel()
        zOrderFan()
        fanAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 600
            interpolator = OvershootInterpolator(1.3f)
            addUpdateListener { placeFan(it.animatedValue as Float) }
            start()
        }
    }

    private fun placeFan(t: Float) {
        val count = shots.size
        val width = shots.firstOrNull()?.layoutParams?.width ?: return
        for (i in 0 until count) {
            val from = FAN_SLOTS[slotOf(i, step - 1, count)]
            val to = FAN_SLOTS[slotOf(i, step, count)]
            val shot = shots[i]
            shot.rotation = lerp(from.rotation, to.rotation, t)
            shot.translationX = width * lerp(from.x, to.x, t)
            val scale = lerp(from.scale, to.scale, t)
            shot.scaleX = scale
            shot.scaleY = scale
            shot.colorFilter = dim(lerp(from.brightness, to.brightness, t.coerceIn(0f, 1f)))
        }
    }

    private fun zOrderFan() {
        for (i in shots.indices) shots[i].translationZ = dp(2) * (3 - slotOf(i, step, shots.size)).toFloat()
    }

    private fun slotOf(i: Int, step: Int, count: Int) = ((i - step) % count + count) % count

    private fun dim(brightness: Float): ColorFilter? {
        if (brightness >= 0.999f) return null
        val v = (brightness * 255).toInt().coerceIn(0, 255)
        return LightingColorFilter(Color.rgb(v, v, v), 0)
    }

    // --- Rythme -------------------------------------------------------------------------------------

    private fun nextStep() {
        step++
        if (ad.descriptions.size > 1) showHook(animated = true)
        if (!dynamic || !motion) return
        playWave()
        if (shots.size > 1 && media.visibility == View.VISIBLE) rotateFan()
        (cta as? ShineButton)?.pulseAndShine()
    }

    private fun showHook(animated: Boolean) {
        val text = ad.descriptions.getOrNull(step % max(1, ad.descriptions.size)) ?: ""
        val view: TextView = if (dynamic) hook else plainHook
        val apply = {
            if (dynamic) hook.setMarked(Hooks.parse(text), animate = motion) else plainHook.text = Hooks.plain(text)
        }
        if (!animated || !motion) {
            apply()
            return
        }
        val distance = dp(16).toFloat()
        view.animate().translationY(-distance).alpha(0f).setDuration(220).withEndAction {
            apply()
            view.translationY = distance
            view.animate().translationY(0f).alpha(1f).setDuration(280).setInterpolator(DecelerateInterpolator()).start()
        }.start()
    }

    private fun playWave() {
        wave.animate().cancel()
        wave.scaleX = 1f
        wave.scaleY = 1f
        wave.alpha = 0.8f
        wave.animate().scaleX(1.35f).scaleY(1.35f).alpha(0f).setDuration(1200).setInterpolator(DecelerateInterpolator()).start()
    }

    private fun updateCloseButton() {
        closeButton.text = if (remaining > 0) remaining.toString() else "✕"
        closeButton.alpha = if (remaining > 0) 0.6f else 1f
        closeButton.contentDescription = if (remaining > 0) null else "Close"
    }

    /** Entrée : zoom léger ; l'affichage compte une fois l'animation terminée */
    private fun playEnter() {
        if (!motion) {
            fullyShown = true
            return
        }
        column.scaleX = 0.92f
        column.scaleY = 0.92f
        column.alpha = 0f
        column.animate().scaleX(1f).scaleY(1f).alpha(1f).setDuration(350).setInterpolator(DecelerateInterpolator())
            .withEndAction { fullyShown = true }.start()
        for (view in listOf(iconBox, cta)) {
            view.scaleX = 0.4f
            view.scaleY = 0.4f
            view.animate().scaleX(1f).scaleY(1f).setStartDelay(150).setDuration(600).setInterpolator(OvershootInterpolator(2f)).start()
        }
    }

    private fun startDrift() {
        if (!dynamic || !motion || drift != null) return
        drift = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 9000
            repeatMode = ValueAnimator.REVERSE
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener {
                val t = it.animatedValue as Float
                halo.translationX = width * 0.5f * t
                halo.translationY = height * 0.35f * t
            }
            start()
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (stopped) return
        playEnter()
        startDrift()
        postDelayed(stepper, if (dynamic) ShowcaseView.STEP_MS else ad.rotationSeconds * 1000L)
        if (remaining > 0) postDelayed(countdown, 1000) else onClosable?.invoke()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stop()
    }

    fun stop() {
        stopped = true
        removeCallbacks(stepper)
        removeCallbacks(countdown)
        drift?.cancel()
        fanAnimator?.cancel()
        marquee?.cancel()
        hook.stopMark()
    }

    // --- Outils -------------------------------------------------------------------------------------

    private fun animationsEnabled(): Boolean = try {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f
    } catch (e: Exception) {
        true
    }

    private fun roundOutline(radius: (Float) -> Float) = object : ViewOutlineProvider() {
        override fun getOutline(view: View, outline: Outline) {
            outline.setRoundRect(0, 0, view.width, view.height, radius(min(view.width, view.height).toFloat()))
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun withAlpha(color: Int, alpha: Float): Int =
        Color.argb((alpha * 255).toInt(), Color.red(color), Color.green(color), Color.blue(color))

    private data class FanSlot(val rotation: Float, val x: Float, val scale: Float, val brightness: Float)

    private companion object {
        /** 0 : devant, au centre ; 1 : à gauche ; 2 : à droite, inclinées, réduites et assombries (x en largeurs) */
        val FAN_SLOTS = listOf(
            FanSlot(0f, 0f, 1f, 1f),
            FanSlot(-8f, -0.52f, 0.82f, 0.72f),
            FanSlot(8f, 0.52f, 0.82f, 0.72f)
        )

        fun lerp(a: Float, b: Float, t: Float) = a + (b - a) * t
    }
}

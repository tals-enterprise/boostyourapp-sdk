package com.boostyourapp.network

import android.animation.ArgbEvaluator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.LightingColorFilter
import android.graphics.LinearGradient
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.text.SpannableString
import android.text.Spanned
import android.text.TextPaint
import android.text.TextUtils
import android.text.style.CharacterStyle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewOutlineProvider
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.util.Locale
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * Style dynamique (« vitrine ») de la bannière, sur le modèle de l'aperçu du back-office (BoostStrip.vue) :
 *
 * - fond : dégradé vertical, motif éventuel (rayures, grille, points) et halo flou de la couleur d'accent qui dérive ;
 * - icône aux coins arrondis à 22 %, nom en petites majuscules, accroche très grasse (3 lignes au plus) dont le mot
 *   entre étoiles est surligné par une bande de la couleur d'accent tracée de gauche à droite ;
 * - éventail de 3 captures au plus (masqué sous 330 dp de large ou 80 dp de haut), bouton pilule avec reflet.
 *
 * Un pas toutes les 2,6 s : accroche suivante, onde autour de l'icône, éventail qui tourne d'un cran, bouton qui
 * pulse et reflet. Animations désactivées sur le téléphone : tout est figé, les mots restent surlignés.
 */
@SuppressLint("ViewConstructor")
internal class ShowcaseView(context: Context, private val images: IconLoader) : FrameLayout(context) {

    private val backdrop = BackdropDrawable()
    private val halo = View(context)
    private val iconBox = FrameLayout(context)
    private val wave = View(context)
    private val icon = ImageView(context)
    private val texts = LinearLayout(context)
    private val name = TextView(context)
    private val hook = HookTextView(context)
    private val fan = FrameLayout(context)
    private val shots = List(3) { ImageView(context) }
    private val cta = ShineButton(context)
    private val adLabel = TextView(context)

    private var ad: Ad? = null
    private var theme: BannerView.Theme? = null
    private var step = 0
    private var compact = false
    private var fanAllowed = true
    private var drift: ValueAnimator? = null
    private var fanAnimator: ValueAnimator? = null

    private val stepper = object : Runnable {
        override fun run() {
            nextStep()
            postDelayed(this, STEP_MS)
        }
    }

    init {
        background = backdrop
        clipChildren = true

        halo.alpha = 0.35f
        addView(halo, LayoutParams(dp(110), dp(110)))

        wave.alpha = 0f
        icon.scaleType = ImageView.ScaleType.CENTER_CROP
        icon.outlineProvider = roundOutline { it * 0.22f }
        icon.clipToOutline = true
        icon.elevation = dp(4).toFloat()
        iconBox.clipChildren = false
        iconBox.clipToPadding = false
        iconBox.addView(wave, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        iconBox.addView(icon, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        name.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        name.typeface = Typeface.DEFAULT_BOLD
        name.letterSpacing = 0.08f
        name.alpha = 0.75f
        name.maxLines = 1
        name.isSingleLine = true
        name.ellipsize = TextUtils.TruncateAt.END

        hook.ellipsize = TextUtils.TruncateAt.END
        hook.setLineSpacing(0f, 1.05f)

        texts.orientation = LinearLayout.VERTICAL
        texts.gravity = Gravity.CENTER_VERTICAL
        texts.addView(name)
        texts.addView(hook, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(2)
        })

        fan.clipChildren = false
        for (shot in shots) {
            shot.scaleType = ImageView.ScaleType.CENTER_CROP
            shot.outlineProvider = roundOutline { dp(5).toFloat() }
            shot.clipToOutline = true
            shot.setBackgroundColor(Color.argb(40, 0, 0, 0))
            fan.addView(shot)
        }

        cta.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        cta.typeface = heavy(Typeface.DEFAULT)
        cta.setPadding(dp(16), dp(8), dp(16), dp(8))
        cta.maxLines = 1
        cta.isSingleLine = true
        cta.elevation = dp(4).toFloat()

        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            clipChildren = false
            setPadding(dp(14), 0, dp(12), 0)
            addView(iconBox, LinearLayout.LayoutParams(dp(56), dp(56)))
            addView(texts, LinearLayout.LayoutParams(0, LayoutParams.MATCH_PARENT, 1f).apply {
                marginStart = dp(12)
                marginEnd = dp(8)
            })
            addView(fan, LinearLayout.LayoutParams(dp(58), LayoutParams.MATCH_PARENT).apply { marginEnd = dp(8) })
            addView(cta, LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        }
        addView(row, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))

        adLabel.text = "Ad"
        adLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 9f)
        addView(adLabel, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.TOP or Gravity.END).apply {
            // À l'écart du bord et de l'arrondi de la carte
            topMargin = dp(4)
            marginEnd = dp(12)
        })
    }

    fun bind(newAd: Ad, newTheme: BannerView.Theme) {
        val changed = ad?.id != newAd.id
        ad = newAd
        if (newTheme != theme) applyTheme(newTheme)
        step = 0

        // Majuscules dans la langue de la pub (setAllCaps est annulé par isSingleLine)
        name.text = newAd.name.uppercase(Locale.forLanguageTag(newAd.languageCode))
        cta.text = newAd.cta
        showHook(animated = false)

        if (changed) {
            icon.setImageDrawable(null)
            newAd.iconUrl?.let { url ->
                images.load(url, dp(56)) { bitmap -> if (ad?.id == newAd.id) icon.setImageBitmap(bitmap) }
            }
            shots.forEachIndexed { i, shot ->
                shot.setImageDrawable(null)
                val url = newAd.screenshots.getOrNull(i)
                shot.visibility = if (url == null) View.GONE else View.VISIBLE
                url?.let { images.load(it, dp(36)) { bitmap -> if (ad?.id == newAd.id) shot.setImageBitmap(bitmap) } }
            }
            updateFanVisibility()
            fanAnimator?.cancel()
            zOrderFan(visibleShots())
            placeFan(1f, visibleShots())
            playAppearance()
        }
        restartStepper()
    }

    fun stop() {
        ad = null
        removeCallbacks(stepper)
        stopDrift()
        fanAnimator?.cancel()
        hook.stopMark()
    }

    // --- Thème ---------------------------------------------------------------------------------------

    private fun applyTheme(newTheme: BannerView.Theme) {
        theme = newTheme
        backdrop.set(newTheme.background, newTheme.background2, newTheme.pattern, newTheme.patternColor)

        halo.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            gradientType = GradientDrawable.RADIAL_GRADIENT
            gradientRadius = dp(55).toFloat()
            colors = intArrayOf(newTheme.button, Color.TRANSPARENT)
        }
        wave.background = GradientDrawable().apply {
            cornerRadius = dp(56) * 0.22f
            setStroke(dp(2), newTheme.button)
        }
        name.setTextColor(newTheme.title)
        hook.setTextColor(newTheme.text)
        hook.markColor = newTheme.button
        hook.markTextColor = newTheme.buttonText
        hook.typeface = heavy(if (newTheme.font == "serif") Typeface.SERIF else Typeface.DEFAULT)
        cta.setTextColor(newTheme.buttonText)
        cta.background = GradientDrawable().apply {
            setColor(newTheme.button)
            cornerRadius = dp(999).toFloat()
        }
        adLabel.setTextColor(withAlpha(newTheme.text, 0.6f))
    }

    /** Hauteur réduite (moins de 80 dp) : icône et accroche plus petites, pas d'éventail. Étroite : pas d'éventail. */
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val density = resources.displayMetrics.density
        post {
            compact = h / density < 80
            fanAllowed = !compact && w / density >= 330
            val iconSize = dp(if (compact) 44 else 56)
            iconBox.layoutParams = (iconBox.layoutParams as LinearLayout.LayoutParams).apply {
                width = iconSize
                height = iconSize
            }
            (wave.background as? GradientDrawable)?.cornerRadius = iconSize * 0.22f
            hook.setTextSize(TypedValue.COMPLEX_UNIT_SP, if (compact) 13f else 15f)
            hook.maxLines = if (compact) 2 else 3
            (halo.layoutParams as LayoutParams).apply {
                leftMargin = (w * 0.12f).toInt()
                topMargin = -dp(30)
                halo.layoutParams = this
            }
            // Captures en 9:16, aussi hautes que la bannière le permet
            val shotHeight = min(dp(58), h - dp(20))
            val shotWidth = (shotHeight * 0.56f).toInt()
            for (shot in shots) {
                shot.layoutParams = LayoutParams(shotWidth, shotHeight, Gravity.CENTER_VERTICAL or Gravity.START).apply {
                    marginStart = dp(4)
                }
                shot.pivotX = shotWidth / 2f
                shot.pivotY = shotHeight.toFloat()
            }
            updateFanVisibility()
        }
    }

    private fun updateFanVisibility() {
        val count = ad?.screenshots?.size ?: 0
        fan.visibility = if (fanAllowed && count > 0) View.VISIBLE else View.GONE
    }

    // --- Rythme : un pas toutes les 2,6 s ------------------------------------------------------------------

    private fun restartStepper() {
        removeCallbacks(stepper)
        if (ad != null && isAttachedToWindow) postDelayed(stepper, STEP_MS)
        if (isAttachedToWindow && animationsEnabled()) startDrift() else stopDrift()
    }

    private fun nextStep() {
        val current = ad ?: return
        step++
        if (current.descriptions.size > 1) showHook(animated = true)
        if (!animationsEnabled()) return
        playWave()
        if (fan.visibility == View.VISIBLE && current.screenshots.size > 1) rotateFan()
        cta.pulseAndShine()
    }

    private fun showHook(animated: Boolean) {
        val hooks = ad?.descriptions.orEmpty()
        val marked = Hooks.parse(hooks.getOrNull(step % max(1, hooks.size)) ?: "")
        val motion = animationsEnabled()
        if (!animated || !motion) {
            hook.animate().cancel()
            hook.translationY = 0f
            hook.alpha = 1f
            hook.setMarked(marked, animate = motion)
            return
        }
        val distance = dp(14).toFloat()
        hook.animate().translationY(-distance).alpha(0f).setDuration(200).withEndAction {
            hook.setMarked(marked, animate = true)
            hook.translationY = distance
            hook.animate().translationY(0f).alpha(1f).setDuration(250).setInterpolator(DecelerateInterpolator()).start()
        }.start()
    }

    private fun playWave() {
        wave.animate().cancel()
        wave.scaleX = 1f
        wave.scaleY = 1f
        wave.alpha = 0.8f
        wave.animate().scaleX(1.35f).scaleY(1.35f).alpha(0f).setDuration(1200).setInterpolator(DecelerateInterpolator()).start()
    }

    /** Apparition : icône et bouton surgissent avec un rebond, texte depuis la gauche, captures depuis le bas */
    private fun playAppearance() {
        if (!animationsEnabled()) return
        for (view in listOf(iconBox, cta)) {
            view.scaleX = 0.4f
            view.scaleY = 0.4f
            view.alpha = 0f
            view.animate().scaleX(1f).scaleY(1f).alpha(1f).setStartDelay(100).setDuration(600)
                .setInterpolator(OvershootInterpolator(2f)).start()
        }
        texts.translationX = -dp(16).toFloat()
        texts.alpha = 0f
        texts.animate().translationX(0f).alpha(1f).setStartDelay(150).setDuration(500).start()
        fan.translationY = dp(40).toFloat()
        fan.alpha = 0f
        fan.animate().translationY(0f).alpha(1f).setStartDelay(150).setDuration(700)
            .setInterpolator(OvershootInterpolator(1.6f)).start()
    }

    // --- Éventail --------------------------------------------------------------------------------------

    private fun rotateFan() {
        fanAnimator?.cancel()
        val count = visibleShots()
        zOrderFan(count)
        fanAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 550
            interpolator = OvershootInterpolator(1.4f)
            addUpdateListener { placeFan(it.animatedValue as Float, count) }
            start()
        }
    }

    private fun visibleShots() = min(shots.size, ad?.screenshots?.size ?: 0)

    /** Place de chaque capture entre le pas précédent et le pas courant ([t] de 0 à 1, au-delà : rebond) */
    private fun placeFan(t: Float, count: Int) {
        for (i in 0 until count) {
            val from = FAN_SLOTS[slotOf(i, step - 1, count)]
            val to = FAN_SLOTS[slotOf(i, step, count)]
            val shot = shots[i]
            shot.rotation = lerp(from.rotation, to.rotation, t)
            shot.translationX = dp(1) * lerp(from.x, to.x, t)
            val scale = lerp(from.scale, to.scale, t)
            shot.scaleX = scale
            shot.scaleY = scale
            shot.colorFilter = dim(lerp(from.brightness, to.brightness, t.coerceIn(0f, 1f)))
        }
    }

    /** La capture de devant passe au-dessus des autres dès le début du mouvement */
    private fun zOrderFan(count: Int) {
        for (i in 0 until count) shots[i].translationZ = dp(1) * (3 - slotOf(i, step, count)).toFloat()
    }

    private fun slotOf(i: Int, step: Int, count: Int) = ((i - step) % count + count) % count

    private fun dim(brightness: Float): ColorFilter? {
        if (brightness >= 0.999f) return null
        val v = (brightness * 255).toInt().coerceIn(0, 255)
        return LightingColorFilter(Color.rgb(v, v, v), 0)
    }

    // --- Halo -------------------------------------------------------------------------------------------

    private fun startDrift() {
        if (drift != null) return
        drift = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 9000
            repeatMode = ValueAnimator.REVERSE
            repeatCount = ValueAnimator.INFINITE
            interpolator = android.view.animation.AccelerateDecelerateInterpolator()
            addUpdateListener {
                val t = it.animatedValue as Float
                halo.translationX = dp(180) * t
                halo.translationY = dp(30) * t
            }
            start()
        }
    }

    private fun stopDrift() {
        drift?.cancel()
        drift = null
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        restartStepper()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        removeCallbacks(stepper)
        stopDrift()
    }

    // --- Outils -----------------------------------------------------------------------------------------

    /** Réglage « Supprimer les animations » du téléphone (échelle de durée des animations à 0) */
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

    companion object {
        const val STEP_MS = 2600L

        /** 0 : devant, droite et nette ; puis inclinée, décalée à droite, réduite et assombrie */
        private val FAN_SLOTS = listOf(
            FanSlot(-8f, 0f, 1f, 1f),
            FanSlot(3f, 9f, 0.9f, 0.78f),
            FanSlot(13f, 18f, 0.8f, 0.6f)
        )

        private fun lerp(a: Float, b: Float, t: Float) = a + (b - a) * t

        /** Très gras (800) quand le système le permet, sinon gras */
        fun heavy(base: Typeface): Typeface =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) Typeface.create(base, 800, false)
            else Typeface.create(base, Typeface.BOLD)
    }
}

/**
 * Fond du style dynamique : dégradé vertical et motif. Rayures à 45° (6 dp sur 14), grille (traits de 1 dp tous les
 * 14 dp) ou points (rayon 1,5 dp tous les 10 dp), comme les motifs CSS de l'aperçu.
 */
internal class BackdropDrawable : Drawable() {
    private var top = Color.BLACK
    private var bottom = Color.BLACK
    private var pattern: String? = null
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val motif = Paint(Paint.ANTI_ALIAS_FLAG)

    fun set(top: Int, bottom: Int, pattern: String?, patternColor: Int) {
        this.top = top
        this.bottom = bottom
        this.pattern = pattern
        motif.color = patternColor
        fill.shader = null
        invalidateSelf()
    }

    override fun onBoundsChange(bounds: android.graphics.Rect) {
        fill.shader = null
    }

    override fun draw(canvas: Canvas) {
        val b = bounds
        if (fill.shader == null) {
            fill.shader = LinearGradient(0f, b.top.toFloat(), 0f, b.bottom.toFloat(), top, bottom, Shader.TileMode.CLAMP)
        }
        canvas.drawRect(b, fill)

        val density = android.content.res.Resources.getSystem().displayMetrics.density
        canvas.save()
        canvas.clipRect(b)
        when (pattern) {
            "stripes" -> {
                // Bandes verticales dans un repère tourné de 45° : bords parallèles à x + y = constante
                val diagonal = hypot(b.width().toFloat(), b.height().toFloat())
                canvas.rotate(45f, b.exactCenterX(), b.exactCenterY())
                val period = 14 * density
                var x = b.exactCenterX() - diagonal
                while (x < b.exactCenterX() + diagonal) {
                    canvas.drawRect(x, b.exactCenterY() - diagonal, x + 6 * density, b.exactCenterY() + diagonal, motif)
                    x += period
                }
            }
            "grid" -> {
                val step = 14 * density
                var x = b.left.toFloat()
                while (x < b.right) {
                    canvas.drawRect(x, b.top.toFloat(), x + density, b.bottom.toFloat(), motif)
                    x += step
                }
                var y = b.top.toFloat()
                while (y < b.bottom) {
                    canvas.drawRect(b.left.toFloat(), y, b.right.toFloat(), y + density, motif)
                    y += step
                }
            }
            "dots" -> {
                val step = 10 * density
                var y = b.top + step / 2
                while (y < b.bottom) {
                    var x = b.left + step / 2
                    while (x < b.right) {
                        canvas.drawCircle(x, y, 1.5f * density, motif)
                        x += step
                    }
                    y += step
                }
            }
        }
        canvas.restore()
    }

    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}
    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}

/** Couleur d'un passage surligné, modifiable sans reconstruire le texte (interpolée pendant le surlignage) */
internal class MarkColorSpan(var color: Int) : CharacterStyle() {
    override fun updateDrawState(paint: TextPaint) {
        paint.color = color
    }
}

/**
 * Accroche avec passages surlignés : une bande de la couleur d'accent se trace de gauche à droite (0,45 s) sous chaque
 * passage, dont le texte passe à la couleur du texte d'accent.
 */
internal class HookTextView(context: Context) : TextView(context) {
    var markColor = Color.BLACK
    var markTextColor = Color.WHITE
    private var marks: List<IntRange> = emptyList()
    private var spans: List<MarkColorSpan> = emptyList()
    private var progress = 1f
    private var animator: ValueAnimator? = null
    private val band = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    private val evaluator = ArgbEvaluator()

    fun setMarked(marked: Hooks.Marked, animate: Boolean) {
        stopMark()
        marks = marked.marks
        val text = SpannableString(marked.text)
        spans = marks.map { range ->
            MarkColorSpan(currentTextColor).also {
                text.setSpan(it, range.first, range.last + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
        }
        setText(text)
        setProgress(if (animate && marks.isNotEmpty()) 0f else 1f)
        if (animate && marks.isNotEmpty()) {
            animator = ValueAnimator.ofFloat(0f, 1f).apply {
                startDelay = 250
                duration = 450
                interpolator = DecelerateInterpolator()
                addUpdateListener { setProgress(it.animatedValue as Float) }
                start()
            }
        }
    }

    fun stopMark() {
        animator?.cancel()
        animator = null
    }

    private fun setProgress(value: Float) {
        progress = value
        val color = evaluator.evaluate(value, currentTextColor, markTextColor) as Int
        spans.forEach { it.color = color }
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        val layout = layout
        if (layout != null && marks.isNotEmpty() && progress > 0f) {
            band.color = markColor
            val pad = 2 * resources.displayMetrics.density
            val radius = 4 * resources.displayMetrics.density
            canvas.save()
            canvas.translate(totalPaddingLeft.toFloat(), totalPaddingTop.toFloat())
            val lastLine = min(layout.lineCount, maxLines) - 1
            for (range in marks) {
                val firstLine = layout.getLineForOffset(range.first)
                val endLine = min(layout.getLineForOffset(range.last), lastLine)
                for (line in firstLine..endLine) {
                    val start = max(range.first, layout.getLineStart(line))
                    val end = min(range.last + 1, layout.getLineEnd(line))
                    if (end <= start) continue
                    val left = layout.getPrimaryHorizontal(start)
                    val right = if (end >= layout.getLineEnd(line)) layout.getLineLeft(line) + layout.getLineMax(line)
                    else layout.getPrimaryHorizontal(end)
                    val width = (right - left + 2 * pad) * progress
                    rect.set(left - pad, layout.getLineTop(line).toFloat(), left - pad + width, layout.getLineBottom(line).toFloat())
                    canvas.drawRoundRect(rect, radius, radius, band)
                }
            }
            canvas.restore()
        }
        super.onDraw(canvas)
    }
}

/** Bouton pilule : pulse bref et reflet blanc qui le traverse en diagonale */
internal class ShineButton(context: Context) : TextView(context) {
    private var shine = -1f
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val clip = Path()
    private var animator: ValueAnimator? = null

    init {
        gravity = Gravity.CENTER
    }

    fun pulseAndShine() {
        animator?.cancel()
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 800
            addUpdateListener {
                val t = it.animatedValue as Float
                // Pulse sur les 500 premières ms, reflet sur toute la durée
                val pulse = if (t < 0.625f) 1f + 0.08f * kotlin.math.sin(Math.PI * t / 0.625).toFloat() else 1f
                scaleX = pulse
                scaleY = pulse
                shine = t
                invalidate()
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    shine = -1f
                    invalidate()
                }
            })
            start()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (shine < 0f || width == 0) return
        val w = width.toFloat()
        val h = height.toFloat()
        val x = -w * 0.6f + w * 1.8f * shine
        paint.shader = LinearGradient(
            x, 0f, x + w * 0.5f, h * 0.35f,
            intArrayOf(Color.TRANSPARENT, Color.argb(140, 255, 255, 255), Color.TRANSPARENT),
            null, Shader.TileMode.CLAMP
        )
        clip.reset()
        clip.addRoundRect(0f, 0f, w, h, h / 2, h / 2, Path.Direction.CW)
        canvas.save()
        canvas.clipPath(clip)
        canvas.drawRect(0f, 0f, w, h, paint)
        canvas.restore()
    }
}

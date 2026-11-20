package com.boostyourapp.network

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Bannière native : icône, nom, accroches qui alternent et bouton, sur le modèle de l'aperçu du
 * tableau de bord (BoostStrip.vue). Construite en code : aucune ressource à fusionner dans l'app.
 *
 * Deux styles, choisis par le développeur de l'app hôte ([BoostNetwork.setStyle]) avec une palette de couleurs :
 * - standard : carte claire bordée, bouton plein ;
 * - dynamic : vitrine ([ShowcaseView]) : fond travaillé, mot surligné, captures en éventail.
 * Même hauteur pour les deux ([heightPx]). Un style inconnu (ajouté côté serveur après cette version du SDK)
 * s'affiche en standard.
 */
@SuppressLint("ViewConstructor")
internal class BannerView(context: Context, private val icons: IconLoader) : FrameLayout(context) {

    private val icon = ImageView(context)
    private val name = TextView(context)
    private val description = TextView(context)
    private val cta = TextView(context)
    private val adLabel = TextView(context)
    private val row = LinearLayout(context)
    /** Style dynamique, créé au premier besoin */
    private var showcase: ShowcaseView? = null

    private var ad: Ad? = null
    private var descriptionIndex = 0
    /** Style et couleurs appliqués : évite de tout reconstruire quand la pub suivante a le même rendu */
    private var appliedTheme: Theme? = null
    /** Bannière haute (80 dp et plus) : icône et textes plus grands, accroche sur 2 lignes */
    private var tall = false

    private val rotateDescription = object : Runnable {
        override fun run() {
            val current = ad ?: return
            if (current.descriptions.size > 1) {
                descriptionIndex = (descriptionIndex + 1) % current.descriptions.size
                slideDescription(Hooks.plain(current.descriptions[descriptionIndex]))
            }
            postDelayed(this, current.rotationSeconds * 1000L)
        }
    }

    init {
        // Le libellé « Ad » déborde sur la marge intérieure, dans le coin
        clipToPadding = false
        isClickable = true
        isFocusable = true
        contentDescription = "Ad"

        icon.scaleType = ImageView.ScaleType.CENTER_CROP
        icon.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setRoundRect(0, 0, view.width, view.height, view.width * 0.22f)
            }
        }
        icon.clipToOutline = true
        icon.background = GradientDrawable().apply { setColor(Color.rgb(244, 244, 245)) }

        name.typeface = Typeface.DEFAULT_BOLD
        name.maxLines = 1
        name.isSingleLine = true
        name.ellipsize = TextUtils.TruncateAt.END
        description.ellipsize = TextUtils.TruncateAt.END

        cta.typeface = Typeface.DEFAULT_BOLD
        cta.maxLines = 1
        cta.isSingleLine = true

        adLabel.text = "Ad"
        adLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 9f)

        val texts = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(name)
            addView(description)
        }
        row.apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(icon, LinearLayout.LayoutParams(dp(44), dp(44)))
            addView(texts, LinearLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
                marginStart = dp(12)
                marginEnd = dp(8)
            })
            addView(cta, LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        }
        addView(row, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(adLabel, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.TOP or Gravity.END).apply {
            topMargin = dp(4)
            marginEnd = -dp(4)
        })

        applySizes()
        applyTheme(Theme.of(Look()))
    }

    fun bind(newAd: Ad, look: Look) {
        val changed = ad?.id != newAd.id
        ad = newAd
        descriptionIndex = 0
        val theme = Theme.of(look)
        applyTheme(theme)
        removeCallbacks(rotateDescription)
        contentDescription = "Ad: ${newAd.name}"

        if (theme.style == "dynamic") {
            val view = showcase ?: ShowcaseView(context, icons).also {
                showcase = it
                addView(it, 0, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
            }
            view.visibility = View.VISIBLE
            view.bind(newAd, theme)
            return
        }

        name.text = newAd.name
        description.text = Hooks.plain(newAd.descriptions.firstOrNull() ?: "")
        description.translationY = 0f
        description.alpha = 1f
        cta.text = newAd.cta

        if (changed || icon.drawable == null) {
            icon.setImageDrawable(null)
            newAd.iconUrl?.let { url ->
                icons.load(url, dp(56)) { bitmap -> if (ad?.id == newAd.id) icon.setImageBitmap(bitmap) }
            }
        }

        postDelayed(rotateDescription, newAd.rotationSeconds * 1000L)
    }

    fun clear() {
        ad = null
        removeCallbacks(rotateDescription)
        showcase?.stop()
    }

    /** Entrée par glissement depuis le bord de l'écran ; l'impression ne compte qu'une fois l'opacité pleine. */
    fun playEnterAnimation(fromTop: Boolean) {
        translationY = (if (fromTop) -1 else 1) * dp(110).toFloat()
        alpha = 0f
        animate().translationY(0f).alpha(1f).setDuration(350).start()
    }

    // --- Styles ------------------------------------------------------------------------------------

    private fun applyTheme(theme: Theme) {
        if (theme == appliedTheme) return
        appliedTheme = theme

        // Style dynamique : la vitrine remplace la ligne classique, dans une carte arrondie qui découpe son contenu
        val dynamic = theme.style == "dynamic"
        row.visibility = if (dynamic) View.GONE else View.VISIBLE
        adLabel.visibility = if (dynamic) View.GONE else View.VISIBLE
        if (!dynamic) showcase?.let { it.stop(); it.visibility = View.GONE }
        outlineProvider = if (dynamic) ROUNDED_16 else ViewOutlineProvider.BACKGROUND
        clipToOutline = dynamic

        if (dynamic) {
            background = null
            elevation = dp(6).toFloat()
            setPadding(0, 0, 0, 0)
            return
        }

        background = GradientDrawable().apply {
            setColor(theme.background)
            cornerRadius = dp(12).toFloat()
            setStroke(dp(1), theme.border)
        }
        elevation = dp(4).toFloat()
        setPadding(dp(12), 0, dp(12), 0)
        name.setTextColor(theme.title)
        description.setTextColor(theme.text)
        cta.setTextColor(theme.buttonText)
        cta.background = GradientDrawable().apply {
            setColor(theme.button)
            cornerRadius = dp(999).toFloat()
        }
        adLabel.setTextColor(withAlpha(theme.text, 0.75f))
    }

    /** Tailles du style standard selon la hauteur : même hauteur que le style dynamique, contenu à l'échelle */
    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val nowTall = h / resources.displayMetrics.density >= 80
        if (nowTall != tall) {
            tall = nowTall
            post { applySizes() }
        }
    }

    private fun applySizes() {
        val iconSize = dp(if (tall) 56 else 44)
        icon.layoutParams = (icon.layoutParams as LinearLayout.LayoutParams).apply {
            width = iconSize
            height = iconSize
        }
        name.setTextSize(TypedValue.COMPLEX_UNIT_SP, if (tall) 15f else 14f)
        description.setTextSize(TypedValue.COMPLEX_UNIT_SP, if (tall) 13f else 12f)
        description.isSingleLine = !tall
        description.maxLines = if (tall) 2 else 1
        cta.setTextSize(TypedValue.COMPLEX_UNIT_SP, if (tall) 13f else 12f)
        cta.setPadding(dp(if (tall) 14 else 12), dp(if (tall) 8 else 6), dp(if (tall) 14 else 12), dp(if (tall) 8 else 6))
    }

    private fun slideDescription(text: String) {
        val distance = description.height.takeIf { it > 0 }?.toFloat() ?: dp(16).toFloat()
        description.animate().translationY(-distance).alpha(0f).setDuration(200).withEndAction {
            description.text = text
            description.translationY = distance
            description.animate().translationY(0f).alpha(1f).setDuration(200).start()
        }.start()
    }

    // La bannière passe d'une activité à l'autre : l'alternance des accroches suit son attachement
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        removeCallbacks(rotateDescription)
        if (appliedTheme?.style != "dynamic") ad?.let { postDelayed(rotateDescription, it.rotationSeconds * 1000L) }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        removeCallbacks(rotateDescription)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun withAlpha(color: Int, alpha: Float): Int =
        Color.argb((alpha * 255).toInt(), Color.red(color), Color.green(color), Color.blue(color))

    /** Style, couleurs, motif et police résolus : ceux du rendu de l'app, à défaut ceux du style. */
    internal data class Theme(
        val style: String,
        val background: Int,
        val background2: Int,
        val border: Int,
        val title: Int,
        val text: Int,
        val button: Int,
        val buttonText: Int,
        /** Motif du fond (style dynamique) ; à défaut, la couleur du bas du dégradé */
        val patternColor: Int,
        val pattern: String?,
        val font: String?
    ) {
        companion object {
            /** Couleurs par défaut de chaque style (palettes Marine et Stade de nuit) */
            private val DEFAULTS = mapOf(
                "standard" to mapOf(
                    "background" to "#FFFFFF", "background2" to "#FFFFFF", "border" to "#E4E4E7", "title" to "#18181B",
                    "text" to "#71717A", "button" to "#193865", "buttonText" to "#FFFFFF"
                ),
                "dynamic" to mapOf(
                    "background" to "#0B1D24", "background2" to "#10292C", "border" to "#0B1D24", "title" to "#FFFFFF",
                    "text" to "#FFFFFF", "button" to "#22C08C", "buttonText" to "#06231A"
                )
            )

            fun of(look: Look): Theme {
                val style = if (look.style in DEFAULTS) look.style else "standard"
                val defaults = DEFAULTS.getValue(style)
                val colors = look.colors
                fun color(key: String): Int = parse(colors[key]) ?: parse(defaults.getValue(key))!!
                return Theme(
                    style = style,
                    background = color("background"),
                    // Dégradé sans seconde couleur : uni
                    background2 = parse(colors["background2"]) ?: color("background"),
                    border = color("border"),
                    title = color("title"),
                    text = color("text"),
                    button = color("button"),
                    buttonText = color("buttonText"),
                    patternColor = parse(colors["patternColor"]) ?: parse(colors["background2"]) ?: color("background"),
                    pattern = look.pattern.takeIf { style == "dynamic" },
                    font = look.font.takeIf { style == "dynamic" }
                )
            }

            private fun parse(value: String?): Int? = try {
                value?.let { Color.parseColor(it) }
            } catch (e: IllegalArgumentException) {
                null
            }
        }
    }

    companion object {
        /** Format prévu : largeur de l'écran limitée à 468 dp */
        const val MAX_WIDTH_DP = 468
        const val MARGIN_DP = 8
        /** Hauteur : 13 % de celle de l'écran, entre 64 et 100 dp, la même pour les deux styles */
        const val MIN_HEIGHT_DP = 64
        const val MAX_HEIGHT_DP = 100

        fun heightPx(context: Context): Int {
            val resources = context.resources
            val dp = (resources.configuration.screenHeightDp * 0.13f).toInt().coerceIn(MIN_HEIGHT_DP, MAX_HEIGHT_DP)
            return (dp * resources.displayMetrics.density).toInt()
        }

        private val ROUNDED_16 = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setRoundRect(0, 0, view.width, view.height, 16 * view.resources.displayMetrics.density)
            }
        }
    }
}

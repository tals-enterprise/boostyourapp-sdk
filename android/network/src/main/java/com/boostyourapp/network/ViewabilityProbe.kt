package com.boostyourapp.network

import android.content.Context
import android.graphics.Rect
import android.os.PowerManager
import android.view.View
import android.view.ViewGroup

/** Mesure la visibilité réelle de la bannière à l'écran. */
internal object ViewabilityProbe {

    fun sample(view: View, expectedWidth: Int, expectedHeight: Int, appForeground: Boolean): ViewabilitySample {
        val shown = view.isAttachedToWindow && view.isShown
        return ViewabilitySample(
            visibleFraction = if (shown) visibleFraction(view) else 0.0,
            shown = shown,
            opaque = effectiveAlpha(view) >= 0.99f,
            sizeOk = sizeOk(view, expectedWidth, expectedHeight),
            windowFocused = view.hasWindowFocus(),
            appForeground = appForeground,
            screenOn = isScreenOn(view.context)
        )
    }

    /**
     * Part visible : rectangle visible dans la fenêtre (getGlobalVisibleRect), limité à la zone
     * d'affichage de la fenêtre (hors barres système et clavier), moins les vues de l'app dessinées
     * par-dessus la bannière.
     */
    private fun visibleFraction(view: View): Double {
        val total = view.width.toLong() * view.height
        if (total <= 0) return 0.0

        val visible = Rect()
        if (!view.getGlobalVisibleRect(visible)) return 0.0

        // Coordonnées de la fenêtre -> coordonnées de l'écran, puis zone réellement affichée
        val windowOrigin = IntArray(2)
        view.rootView.getLocationOnScreen(windowOrigin)
        visible.offset(windowOrigin[0], windowOrigin[1])
        val displayFrame = Rect()
        view.getWindowVisibleDisplayFrame(displayFrame)
        if (!displayFrame.isEmpty && !visible.intersect(displayFrame)) return 0.0

        var area = visible.width().toLong() * visible.height()
        area -= obscuredArea(view, visible, windowOrigin)
        return (area.coerceAtLeast(0).toDouble() / total).coerceIn(0.0, 1.0)
    }

    /** Surface masquée par les vues sœurs ajoutées après la bannière (dessinées au-dessus). */
    private fun obscuredArea(view: View, visible: Rect, windowOrigin: IntArray): Long {
        val parent = view.parent as? ViewGroup ?: return 0
        val index = parent.indexOfChild(view)
        var obscured = 0L
        val other = Rect()
        for (i in index + 1 until parent.childCount) {
            val sibling = parent.getChildAt(i)
            if (!sibling.isShown || sibling.alpha < 0.1f || !sibling.getGlobalVisibleRect(other)) continue
            other.offset(windowOrigin[0], windowOrigin[1])
            if (other.intersect(visible)) obscured += other.width().toLong() * other.height()
        }
        return obscured
    }

    private fun effectiveAlpha(view: View): Float {
        var alpha = 1f
        var current: View? = view
        while (current != null) {
            alpha *= current.alpha
            current = current.parent as? View
        }
        return alpha
    }

    /** Taille réelle (échelle des parents comprise) d'au moins 90 % du format prévu. */
    private fun sizeOk(view: View, expectedWidth: Int, expectedHeight: Int): Boolean {
        var scaleX = 1f
        var scaleY = 1f
        var current: View? = view
        while (current != null) {
            scaleX *= current.scaleX
            scaleY *= current.scaleY
            current = current.parent as? View
        }
        return view.width * scaleX >= expectedWidth * 0.9f && view.height * scaleY >= expectedHeight * 0.9f
    }

    private fun isScreenOn(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return true
        return power.isInteractive
    }
}

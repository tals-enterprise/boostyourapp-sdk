package com.boostyourapp.network

/** Mesure instantanée de la bannière (voir ViewabilityProbe). */
internal data class ViewabilitySample(
    /** Part des pixels de la bannière visibles à l'écran, de 0 à 1 */
    val visibleFraction: Double,
    /** Vue attachée, visible, ainsi que tous ses parents */
    val shown: Boolean,
    /** Opacité pleine, y compris celle des parents */
    val opaque: Boolean,
    /** Taille au moins égale au format prévu (pas de bannière réduite) */
    val sizeOk: Boolean,
    /** Fenêtre au premier plan (pas de boîte de dialogue par-dessus) */
    val windowFocused: Boolean,
    val appForeground: Boolean,
    val screenOn: Boolean
) {
    val viewable: Boolean
        get() = shown && opaque && sizeOk && windowFocused && appForeground && screenOn &&
            visibleFraction >= MIN_VISIBLE_FRACTION

    companion object {
        const val MIN_VISIBLE_FRACTION = 0.5
    }
}

/**
 * Règle d'affichage effectif inspirée de la norme IAB/MRC : au moins 50 % des pixels visibles
 * pendant au moins 1 seconde continue, app au premier plan et écran allumé.
 * Une seule impression par pub affichée.
 */
internal class ViewabilityTracker(
    private val requiredMs: Long = 1_000,
    /** Au-delà de cet écart entre deux mesures (app suspendue...), la continuité est rompue */
    private val maxGapMs: Long = 500
) {
    private var visibleSince: Long? = null
    private var lastSampleAt: Long? = null
    private var counted = false

    /** À appeler à chaque nouvelle pub. */
    fun reset() {
        visibleSince = null
        lastSampleAt = null
        counted = false
    }

    /** Vrai une seule fois : quand la pub vient d'atteindre la durée de visibilité requise. */
    fun onSample(sample: ViewabilitySample, nowMs: Long): Boolean {
        val previous = lastSampleAt
        lastSampleAt = nowMs
        if (counted) return false
        if (!sample.viewable || (previous != null && nowMs - previous > maxGapMs)) {
            visibleSince = if (sample.viewable) nowMs else null
            return false
        }
        val since = visibleSince ?: nowMs.also { visibleSince = it }
        if (nowMs - since >= requiredMs) {
            counted = true
            return true
        }
        return false
    }
}

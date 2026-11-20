package com.boostyourapp.network

/** Position de la bannière, fixée en haut ou en bas de l'écran, par-dessus l'app. */
enum class BannerPosition {
    TOP, BOTTOM;

    companion object {
        /** "top" ou "bottom" (insensible à la casse), comme dans les plugins. Par défaut : bas. */
        @JvmStatic
        fun from(value: String?): BannerPosition =
            if (value.equals("top", ignoreCase = true)) TOP else BOTTOM
    }
}

/** Événements transmis à l'app via [BoostNetwork.onEvent], toujours sur le thread principal. */
sealed class BoostEvent {
    /** Une pub est affichée dans la bannière. */
    data class Loaded(val adId: String) : BoostEvent()

    /** L'utilisateur a touché la bannière ou l'interstitiel ; le store va s'ouvrir. */
    data class Clicked(val adId: String) : BoostEvent()

    /** Un interstitiel couvre l'écran : mettez l'app en pause (son, jeu). */
    data class InterstitialShown(val adId: String) : BoostEvent()

    /** L'interstitiel est fermé : l'app peut reprendre. */
    data class InterstitialClosed(val adId: String) : BoostEvent()

    /**
     * Erreur : `unknown_app` (appKey inconnue), `suspended`, `network`, `not_initialized`...
     * La bannière réessaie d'elle-même sauf pour `unknown_app`.
     */
    data class Error(val code: String, val message: String) : BoostEvent()

    /** Nom de l'événement pour les plugins : "loaded", "clicked", "interstitialShown", "interstitialClosed" ou "error". */
    val type: String
        get() = when (this) {
            is Loaded -> "loaded"
            is Clicked -> "clicked"
            is InterstitialShown -> "interstitialShown"
            is InterstitialClosed -> "interstitialClosed"
            is Error -> "error"
        }

    /** Pub concernée (null pour une erreur) */
    val adIdOrNull: String?
        get() = when (this) {
            is Loaded -> adId
            is Clicked -> adId
            is InterstitialShown -> adId
            is InterstitialClosed -> adId
            is Error -> null
        }
}

/** Fin d'un interstitiel : false s'il n'a pas pu s'afficher, true à sa fermeture. Sur le thread principal. */
fun interface InterstitialCallback {
    fun onFinished(shown: Boolean)
}

fun interface BoostEventListener {
    fun onEvent(event: BoostEvent)
}

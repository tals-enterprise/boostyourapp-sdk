import Foundation

/// Mesure instantanée de la bannière (voir ViewabilityProbe).
struct ViewabilitySample {
    /// Part des pixels de la bannière visibles à l'écran, de 0 à 1
    var visibleFraction: Double
    /// Vue dans une fenêtre, ni elle ni ses parents masqués (isHidden)
    var shown: Bool
    /// Opacité pleine, y compris celle des parents
    var opaque: Bool
    /// Taille au moins égale au format prévu (pas de bannière réduite)
    var sizeOk: Bool
    /// App au premier plan et active (écran allumé, pas de centre de contrôle ni d'appel par-dessus)
    var appActive: Bool

    static let minVisibleFraction = 0.5

    var viewable: Bool {
        return shown && opaque && sizeOk && appActive && visibleFraction >= ViewabilitySample.minVisibleFraction
    }
}

/**
 * Règle d'affichage effectif inspirée de la norme IAB/MRC : au moins 50 % des pixels visibles
 * pendant au moins 1 seconde continue, app au premier plan et écran allumé.
 * Une seule impression par pub affichée.
 */
final class ViewabilityTracker {
    private let required: TimeInterval
    /// Au-delà de cet écart entre deux mesures (app suspendue...), la continuité est rompue
    private let maxGap: TimeInterval
    private var visibleSince: TimeInterval?
    private var lastSampleAt: TimeInterval?
    private var counted = false

    init(required: TimeInterval = 1.0, maxGap: TimeInterval = 0.5) {
        self.required = required
        self.maxGap = maxGap
    }

    /// À appeler à chaque nouvelle pub.
    func reset() {
        visibleSince = nil
        lastSampleAt = nil
        counted = false
    }

    /// Vrai une seule fois : quand la pub vient d'atteindre la durée de visibilité requise.
    func onSample(_ sample: ViewabilitySample, now: TimeInterval) -> Bool {
        let previous = lastSampleAt
        lastSampleAt = now
        if counted { return false }
        if let previous = previous, now - previous > maxGap {
            visibleSince = sample.viewable ? now : nil
            return false
        }
        guard sample.viewable else {
            visibleSince = nil
            return false
        }
        let since: TimeInterval
        if let existing = visibleSince {
            since = existing
        } else {
            since = now
            visibleSince = now
        }
        if now - since >= required {
            counted = true
            return true
        }
        return false
    }
}

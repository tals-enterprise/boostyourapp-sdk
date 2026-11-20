#if os(iOS)
import UIKit

/// Mesure la visibilité réelle de la bannière à l'écran.
enum ViewabilityProbe {

    /**
     * - `keyboardFrame` : clavier affiché, en coordonnées de l'écran (`.null` sinon) ;
     * - `appActive` : `UIApplication.applicationState == .active`.
     */
    static func sample(_ view: UIView, expectedSize: CGSize, keyboardFrame: CGRect, appActive: Bool) -> ViewabilitySample {
        guard let window = view.window else {
            return ViewabilitySample(visibleFraction: 0, shown: false, opaque: false, sizeOk: false, appActive: appActive)
        }
        let shown = isShown(view)
        // Cadre réellement affiché (animations en cours comprises), en coordonnées de la fenêtre
        let layer = view.layer.presentation() ?? view.layer
        let windowLayer = window.layer.presentation() ?? window.layer
        let frame = layer.convert(layer.bounds, to: windowLayer)

        return ViewabilitySample(
            visibleFraction: shown ? visibleFraction(view, frame: frame, window: window, keyboardFrame: keyboardFrame) : 0,
            shown: shown,
            opaque: effectiveAlpha(view) >= 0.99,
            sizeOk: frame.width >= expectedSize.width * 0.9 && frame.height >= expectedSize.height * 0.9,
            appActive: appActive
        )
    }

    /// Ni la vue ni ses parents (fenêtre comprise) ne sont masqués.
    private static func isShown(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if candidate.isHidden { return false }
            current = candidate.superview
        }
        return true
    }

    /// Opacité affichée, parents compris : la plus faible de la valeur cible et de la valeur en cours d'animation.
    private static func effectiveAlpha(_ view: UIView) -> CGFloat {
        var alpha: CGFloat = 1
        var current: UIView? = view
        while let candidate = current {
            let animated = CGFloat(candidate.layer.presentation()?.opacity ?? candidate.layer.opacity)
            alpha *= min(candidate.alpha, animated)
            current = candidate.superview
        }
        return alpha
    }

    /**
     * Part visible : cadre de la bannière limité à l'écran et à la fenêtre, moins le clavier et les vues
     * ajoutées par-dessus dans la fenêtre (contrôleurs présentés en modale...).
     */
    private static func visibleFraction(_ view: UIView, frame: CGRect, window: UIWindow, keyboardFrame: CGRect) -> Double {
        let total = Double(frame.width * frame.height)
        guard total > 0 else { return 0 }

        let screen = window.screen
        let inScreen = window.convert(frame, to: screen.coordinateSpace)
        let windowInScreen = window.convert(window.bounds, to: screen.coordinateSpace)
        let visible = inScreen.intersection(screen.bounds).intersection(windowInScreen)
        if visible.isNull || visible.isEmpty { return 0 }

        var area = Double(visible.width * visible.height)
        if !keyboardFrame.isNull {
            let covered = visible.intersection(keyboardFrame)
            if !covered.isNull { area -= Double(covered.width * covered.height) }
        }
        area -= obscuredArea(view, visible: visible, window: window, screen: screen)
        return min(1, max(0, area / total))
    }

    /// Surface masquée par les vues sœurs ajoutées après la bannière (dessinées au-dessus).
    private static func obscuredArea(_ view: UIView, visible: CGRect, window: UIWindow, screen: UIScreen) -> Double {
        guard let parent = view.superview, let index = parent.subviews.firstIndex(of: view) else { return 0 }
        var obscured = 0.0
        for sibling in parent.subviews[(index + 1)...] {
            if sibling.isHidden || sibling.alpha < 0.1 { continue }
            let inWindow = sibling.convert(sibling.bounds, to: window)
            let covered = window.convert(inWindow, to: screen.coordinateSpace).intersection(visible)
            if !covered.isNull { obscured += Double(covered.width * covered.height) }
        }
        return obscured
    }
}
#endif

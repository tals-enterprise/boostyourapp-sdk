#if os(iOS)
import UIKit

/**
 * Interstitiels : une pub plein écran, affichée quand l'app le demande (`BoostNetwork.showInterstitial`), par exemple
 * entre deux niveaux. Sur le thread principal.
 *
 * - Une pub est gardée prête (demandée au serveur avec p_format = interstitial), au plus 20 minutes : son jeton
 *   expire au bout de 30. Après le premier usage, le SDK en prépare une à chaque lancement.
 * - Au moins `intervalSeconds` (réglage du serveur, 3 minutes par défaut) entre deux interstitiels sur l'appareil ;
 *   avant, la demande est refusée.
 * - Présentée en plein écran au-dessus du contrôleur le plus haut de la fenêtre de l'app ; bouton de fermeture au
 *   bout de `closeSeconds` (5 s par défaut).
 * - Vue 1 s en continu (app active, rien présenté par-dessus, animation d'entrée terminée) : son jeton rejoint les
 *   affichages en attente. Un interstitiel vu compte davantage qu'une bannière pour la visibilité de l'app.
 */
final class InterstitialController {
    private static let maxAge: TimeInterval = 20 * 60
    private static let retryDelay: TimeInterval = 60
    private static let visibleDuration: TimeInterval = 1
    private static let usedKey = "interstitial_used"
    private static let shownAtKey = "interstitial_shown_at"
    private static let configKey = "interstitial_config"

    private unowned let host: BannerController
    private let store: KeyValueStore
    private let images: IconLoader
    private let emit: (BoostEvent) -> Void

    private var ad: Ad?
    private var loadedAt: TimeInterval = 0
    private var config = InterstitialConfig()
    private var lastShownAt: TimeInterval
    private var loading = false
    /// Pas de nouvelle demande avant (échec ou aucune pub disponible), en temps monotone
    private var nextLoadAt: TimeInterval = 0
    private var showing: Showing?

    private final class Showing {
        let ad: Ad
        let controller: InterstitialViewController
        let onFinished: ((Bool) -> Void)?
        var visibleSince: TimeInterval = 0
        var counted = false
        var timer: Timer?

        init(ad: Ad, controller: InterstitialViewController, onFinished: ((Bool) -> Void)?) {
            self.ad = ad
            self.controller = controller
            self.onFinished = onFinished
        }
    }

    init(host: BannerController, store: KeyValueStore, images: IconLoader, emit: @escaping (BoostEvent) -> Void) {
        self.host = host
        self.store = store
        self.images = images
        self.emit = emit
        lastShownAt = store.string(forKey: InterstitialController.shownAtKey).flatMap { Double($0) } ?? 0
        if let text = store.string(forKey: InterstitialController.configKey),
           let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] {
            config = ApiJson.parseInterstitial(json)
        }
    }

    // MARK: - API

    /// Une pub est prête et l'intervalle depuis le dernier interstitiel est écoulé.
    var isReady: Bool {
        return showing == nil && freshAd() != nil && intervalElapsed()
    }

    /// L'app utilise les interstitiels : en préparer un, et en préparer un à chaque lancement.
    func load() {
        markUsed()
        fetchIfNeeded()
    }

    /// Lancement : prépare un interstitiel si l'app en a déjà affiché.
    func preloadIfUsed() {
        if store.string(forKey: InterstitialController.usedKey) != nil { fetchIfNeeded() }
    }

    /// Affiche l'interstitiel s'il est prêt. `onFinished` reçoit false aussitôt sinon (aucune pub prête, intervalle
    /// pas écoulé, app en arrière-plan), ou true à sa fermeture.
    func show(_ onFinished: ((Bool) -> Void)?) {
        markUsed()
        guard showing == nil, let current = freshAd(), intervalElapsed(), !host.stopped,
              UIApplication.shared.applicationState == .active,
              let presenter = InterstitialController.topController() else {
            fetchIfNeeded()
            onFinished?(false)
            return
        }

        ad = nil
        lastShownAt = Date().timeIntervalSince1970
        store.set(String(lastShownAt), forKey: InterstitialController.shownAtKey)

        let controller = InterstitialViewController(ad: current, look: host.currentLook, closeSeconds: config.closeSeconds,
                                                    images: images)
        let session = Showing(ad: current, controller: controller, onFinished: onFinished)
        controller.onClose = { [weak self, weak session] in
            guard let self = self, let session = session else { return }
            self.close(session)
        }
        controller.onAdClick = { [weak self, weak session] in
            guard let self = self, let session = session else { return }
            self.host.click(session.ad)
            self.close(session)
        }
        showing = session
        presenter.present(controller, animated: true)
        emit(.interstitialShown(current.id))
        startTracking(session)
    }

    // MARK: - Interne

    private func close(_ session: Showing) {
        guard showing === session else { return }
        showing = nil
        session.timer?.invalidate()
        session.timer = nil
        session.controller.stop()
        if session.controller.presentingViewController != nil {
            session.controller.dismiss(animated: true)
        }
        emit(.interstitialClosed(session.ad.id))
        session.onFinished?(true)
        // Le suivant, prêt pour la prochaine demande (et envoi de l'affichage qui vient d'être compté)
        fetchIfNeeded()
    }

    /// Visibilité mesurée toutes les 100 ms jusqu'à ce que l'affichage soit compté
    private func startTracking(_ session: Showing) {
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self, weak session] timer in
            guard let self = self, let session = session, self.showing === session, !session.counted else {
                timer.invalidate()
                return
            }
            let controller = session.controller
            let visible = UIApplication.shared.applicationState == .active && controller.fullyShown &&
                controller.viewIfLoaded?.window != nil && controller.presentedViewController == nil
            let now = ProcessInfo.processInfo.systemUptime
            if !visible {
                session.visibleSince = 0
            } else if session.visibleSince == 0 {
                session.visibleSince = now
            } else if now - session.visibleSince >= InterstitialController.visibleDuration {
                session.counted = true
                self.host.recordImpression(session.ad.token)
                timer.invalidate()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        session.timer = timer
    }

    private func fetchIfNeeded() {
        if loading || host.stopped || freshAd() != nil { return }
        if ProcessInfo.processInfo.systemUptime < nextLoadAt { return }
        loading = true
        host.requestInterstitial { [weak self] response in
            guard let self = self else { return }
            self.loading = false
            if let settings = response?.interstitial {
                self.config = settings
                if let data = try? JSONSerialization.data(withJSONObject: ApiJson.interstitialJson(settings)) {
                    self.store.set(String(decoding: data, as: UTF8.self), forKey: InterstitialController.configKey)
                }
            }
            if let received = response?.ads.first {
                self.ad = received
                self.loadedAt = Date().timeIntervalSince1970
                self.nextLoadAt = 0
            } else {
                self.nextLoadAt = ProcessInfo.processInfo.systemUptime + InterstitialController.retryDelay
            }
        }
    }

    private func freshAd() -> Ad? {
        guard let current = ad else { return nil }
        let age = Date().timeIntervalSince1970 - loadedAt
        return age >= 0 && age < InterstitialController.maxAge ? current : nil
    }

    /// Horloge reculée (changement d'heure manuel) : l'intervalle est considéré écoulé
    private func intervalElapsed() -> Bool {
        let elapsed = Date().timeIntervalSince1970 - lastShownAt
        return elapsed < 0 || elapsed >= TimeInterval(config.intervalSeconds)
    }

    private func markUsed() {
        if store.string(forKey: InterstitialController.usedKey) == nil {
            store.set("1", forKey: InterstitialController.usedKey)
        }
    }

    /// Contrôleur le plus haut de la fenêtre de l'app : l'interstitiel passe par-dessus tout, modales comprises
    private static func topController() -> UIViewController? {
        guard var top = BannerController.hostWindow()?.rootViewController else { return nil }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top.isBeingDismissed ? nil : top
    }
}
#endif

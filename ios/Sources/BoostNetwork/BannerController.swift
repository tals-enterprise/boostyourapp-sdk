#if os(iOS)
import UIKit

/**
 * Cœur du SDK, entièrement sur le thread principal (les appels réseau passent par URLSession).
 *
 * - Superpose la bannière à l'app : vue ajoutée à la fenêtre principale, juste au-dessus de la vue du
 *   contrôleur racine. Les contrôleurs présentés en modale passent donc par-dessus, comme les dialogues
 *   sur Android, et la bannière n'est alors pas comptée comme visible.
 * - Affiche chaque pub pendant refreshSeconds, puis la suivante ; redemande des pubs quand la file se vide.
 * - Mesure la visibilité toutes les 100 ms ; une pub visible 1 s continue rejoint les affichages en attente.
 * - Envoie les affichages avec la demande de pubs suivante, et à la mise en arrière-plan.
 * - Partage avec les interstitiels (`InterstitialController`) le rendu, les affichages en attente et les clics.
 */
final class BannerController: NSObject {
    private static let tickInterval: TimeInterval = 0.1
    private static let maxImpressionsPerCall = 50
    private static let minBackoff: TimeInterval = 30
    private static let maxBackoff: TimeInterval = 5 * 60
    private static let suspendedRetry: TimeInterval = 60 * 60
    private static let lookKey = "look"
    /// Style et palette demandés quand le rendu gardé a été reçu
    private static let lookRequestKey = "look_request"

    private let appKey: String
    private let api: ApiClient
    private let installationId: String
    private let emit: (BoostEvent) -> Void
    private let icons = IconLoader()
    private let queue: AdQueue
    private let pending: PendingImpressions
    private let creatives: CreativeCache
    private let tracker = ViewabilityTracker()
    private let store: KeyValueStore
    /// Pubs plein écran, affichées à la demande de l'app
    private(set) lazy var interstitials = InterstitialController(host: self, store: store, images: icons, emit: emit)

    private var position: BannerPosition = .bottom
    private var wantShown = false
    private var foreground: Bool
    private var banner: BannerView?
    private var bannerConstraints: [NSLayoutConstraint] = []
    /// Rendu demandé par l'app (setStyle) et rendu résolu par le serveur, gardé d'un lancement à l'autre
    private var requestedStyle: String?
    private var requestedPalette: String?
    private var look = Look()
    /// Contrôleur racine dont la zone sûre est agrandie de la place de la bannière, et la valeur ajoutée
    private weak var reservedController: UIViewController?
    private var reservedInsets = UIEdgeInsets.zero
    private var currentAd: Ad?
    private var refreshSeconds = 60

    private var fetching = false
    /// appKey inconnue : plus aucun appel
    private(set) var stopped = false
    private var retryAt: TimeInterval = 0
    private var backoff: TimeInterval = 0
    private var rotateWork: DispatchWorkItem?
    private var retryWork: DispatchWorkItem?
    private var tickTimer: Timer?
    private var keyboardFrame: CGRect = .null
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(appKey: String, api: ApiClient, store: KeyValueStore, installationId: String, emit: @escaping (BoostEvent) -> Void) {
        self.appKey = appKey
        self.api = api
        self.installationId = installationId
        self.emit = emit
        let wallClock: () -> TimeInterval = { Date().timeIntervalSince1970 }
        queue = AdQueue(clock: wallClock)
        pending = PendingImpressions(store: store, clock: wallClock)
        creatives = CreativeCache(store: store)
        self.store = store
        foreground = UIApplication.shared.applicationState != .background
        super.init()
        look = loadLook()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        center.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Rendu courant des pubs (bannière et interstitiel)
    var currentLook: Look { return look }

    // MARK: - API

    func show(_ newPosition: BannerPosition) {
        if stopped { return }
        let moved = newPosition != position
        position = newPosition
        wantShown = true
        attach(relayout: moved)
        if currentAd == nil { advance() }
    }

    /// Style (standard, dynamic) et palette des pubs. Appliqué aussitôt avec les couleurs par défaut du style, puis
    /// avec celles de la palette dès la réponse du serveur.
    func setStyle(_ style: String?, palette: String?) {
        if style == requestedStyle && palette == requestedPalette { return }
        requestedStyle = style
        requestedPalette = palette
        if store.string(forKey: BannerController.lookRequestKey) != lookRequest {
            look = Look(style: style ?? "standard")
            if let ad = currentAd { banner?.bind(ad, look: look) }
        }
        if !stopped && !fetching { fetch(force: true, reportOnly: true) }
    }

    func hide() {
        wantShown = false
        rotateWork?.cancel()
        rotateWork = nil
        retryWork?.cancel()
        retryWork = nil
        detach()
        currentAd = nil
    }

    // MARK: - Rotation et chargement

    private func advance() {
        rotateWork?.cancel()
        rotateWork = nil
        guard wantShown, foreground, !stopped else {
            currentAd = nil
            return
        }

        let ad = queue.poll()
        currentAd = ad
        tracker.reset()

        guard let next = ad else {
            banner?.isHidden = true
            fetch()
            return
        }

        if let view = banner {
            let wasHidden = view.isHidden
            view.isHidden = false
            // Le style dynamique est plus haut : la bannière suit la hauteur du style de la pub
            view.bind(next, look: look)
            if wasHidden { view.playEnterAnimation(fromTop: position == .top) }
        }
        emit(.loaded(next.id))
        rotateWork = after(TimeInterval(refreshSeconds)) { [weak self] in self?.advance() }

        // Dernière pub de la file : on prépare la suite (et on envoie les affichages en attente)
        if queue.count == 0 { fetch() }
    }

    /// `reportOnly` : seulement envoyer les affichages en attente, sans recevoir de pubs (mise en arrière-plan)
    private func fetch(force: Bool = false, reportOnly: Bool = false) {
        if fetching || stopped { return }
        if !force && uptime() < retryAt { return }
        fetching = true

        let impressions = pending.take(BannerController.maxImpressionsPerCall)
        let request = NextRequest(
            appKey: appKey,
            installationId: installationId,
            device: Self.deviceInfo(),
            recent: queue.recentIds,
            impressions: impressions,
            count: reportOnly ? 0 : nil,
            cached: reportOnly ? nil : creatives.versions,
            style: requestedStyle,
            palette: requestedPalette
        )
        // En arrière-plan, iOS laisse quelques secondes pour terminer l'envoi
        if !foreground { beginBackgroundTask() }
        let creatives = self.creatives
        api.next(request, cached: { creatives.get(id: $0, version: $1) }) { [weak self] result in
            DispatchQueue.main.async { self?.onFetched(result, sent: impressions, reportOnly: reportOnly) }
        }
    }

    private func onFetched(_ result: Result<NextResponse, ApiError>, sent: [String], reportOnly: Bool) {
        fetching = false
        defer { endBackgroundTask() }

        switch result {
        case .success(let response):
            pending.confirm(sent)
            backoff = 0
            retryAt = 0
            refreshSeconds = response.refreshSeconds
            if let newLook = response.look { updateLook(newLook) }
            creatives.put(response.ads)
            queue.add(response.ads)
            if response.ads.isEmpty && !reportOnly { scheduleRetry(TimeInterval(refreshSeconds)) }
            if wantShown && currentAd == nil { advance() }

        case .failure(let error):
            handleFailure(error, sent: sent)
            switch error.code {
            case "unknown_app":
                hide()
            case "suspended":
                banner?.isHidden = true
                currentAd = nil
                scheduleRetry(BannerController.suspendedRetry)
            default:
                backoff = min(max(backoff * 2, BannerController.minBackoff), BannerController.maxBackoff)
                scheduleRetry(backoff)
            }
        }
    }

    /// Erreur d'une demande (bannières ou interstitiel) : jetons à garder ou non, arrêt si appKey inconnue
    private func handleFailure(_ error: ApiError, sent: [String]) {
        switch error.code {
        case "unknown_app":
            stopped = true
            BoostNetwork.log("appKey inconnue : vérifiez la clé passée à BoostNetwork.initialize(appKey:)")
        case "suspended":
            // Les affichages d'une app suspendue ne comptent plus : inutile de les garder
            pending.confirm(sent)
        default:
            pending.release(sent)
        }
        BoostNetwork.log("Échec de network_next : \(error.code)")
        emit(.error(error.code, error.message))
    }

    /// Demande un interstitiel (une pub, sans cache du contenu), avec les affichages en attente. `completion` reçoit
    /// la réponse, ou nil en cas d'échec (erreur déjà signalée), sur le thread principal.
    func requestInterstitial(_ completion: @escaping (NextResponse?) -> Void) {
        if stopped { return completion(nil) }
        let impressions = pending.take(BannerController.maxImpressionsPerCall)
        let request = NextRequest(
            appKey: appKey,
            installationId: installationId,
            device: Self.deviceInfo(),
            recent: queue.recentIds,
            impressions: impressions,
            count: 1,
            style: requestedStyle,
            palette: requestedPalette,
            format: "interstitial"
        )
        api.next(request) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    self.pending.confirm(impressions)
                    if let newLook = response.look { self.updateLook(newLook) }
                    completion(response)
                case .failure(let error):
                    self.handleFailure(error, sent: impressions)
                    if error.code == "unknown_app" { self.hide() }
                    completion(nil)
                }
            }
        }
    }

    /// Pub (bannière ou interstitiel) réellement vue : son jeton partira avec la demande suivante
    func recordImpression(_ token: String) {
        pending.add(token)
    }

    private func scheduleRetry(_ delay: TimeInterval) {
        retryAt = uptime() + delay
        retryWork?.cancel()
        retryWork = after(delay) { [weak self] in
            // Pas de nouvel essai en arrière-plan : la demande partira au retour au premier plan
            guard let self = self, self.wantShown, self.currentAd == nil, self.foreground else { return }
            self.fetch(force: true)
        }
    }

    /// Mise en arrière-plan : on envoie les affichages en attente sans attendre la prochaine demande.
    private func flush() {
        if !stopped && !fetching && pending.available > 0 { fetch(force: true, reportOnly: true) }
    }

    // MARK: - Visibilité

    private func measureViewability() {
        guard let ad = currentAd, let view = banner, let window = view.window else { return }
        keepAboveRootView(view, in: window)
        let sample = ViewabilityProbe.sample(
            view,
            expectedSize: expectedSize(in: window),
            keyboardFrame: keyboardFrame,
            appActive: UIApplication.shared.applicationState == .active
        )
        if tracker.onSample(sample, now: uptime()) {
            recordImpression(ad.token)
        }
    }

    private func startTick() {
        guard tickTimer == nil else { return }
        let timer = Timer(timeInterval: BannerController.tickInterval, repeats: true) { [weak self] _ in
            self?.measureViewability()
        }
        // Mode commun : la mesure continue pendant les défilements
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTick() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: - Overlay

    private func attach(relayout: Bool = false) {
        guard wantShown, !stopped, let window = BannerController.hostWindow() else { return }

        let view: BannerView
        if let existing = banner {
            view = existing
        } else {
            view = BannerView(icons: icons)
            view.isHidden = true
            view.onTap = { [weak self] in self?.onTap() }
            banner = view
            // Pub choisie avant que la fenêtre de l'app n'existe (lancement)
            if let ad = currentAd {
                view.isHidden = false
                view.bind(ad, look: look)
            }
        }

        if view.superview !== window {
            view.removeFromSuperview()
            if let root = window.rootViewController?.view, root.superview === window {
                window.insertSubview(view, aboveSubview: root)
            } else {
                window.addSubview(view)
            }
            installConstraints(view, in: window)
        } else if relayout {
            installConstraints(view, in: window)
        }
        keepAboveRootView(view, in: window)
        reserveSpace(in: window)
        startTick()
    }

    private func detach() {
        stopTick()
        banner?.removeFromSuperview()
        releaseSpace()
    }

    /// Agrandit la zone sûre du contrôleur racine de la place de la bannière (hauteur et marges) : les vues de l'app
    /// qui respectent la zone sûre s'arrêtent au-dessus de la bannière, rien n'est masqué.
    private func reserveSpace(in window: UIWindow) {
        guard let root = window.rootViewController else { return }
        let space = BannerView.height + 2 * BannerView.margin
        let wanted = position == .top ? UIEdgeInsets(top: space, left: 0, bottom: 0, right: 0)
            : UIEdgeInsets(top: 0, left: 0, bottom: space, right: 0)
        if root === reservedController && wanted == reservedInsets { return }
        releaseSpace()
        var insets = root.additionalSafeAreaInsets
        insets.top += wanted.top
        insets.bottom += wanted.bottom
        root.additionalSafeAreaInsets = insets
        reservedController = root
        reservedInsets = wanted
    }

    private func releaseSpace() {
        if let root = reservedController {
            var insets = root.additionalSafeAreaInsets
            insets.top = max(0, insets.top - reservedInsets.top)
            insets.bottom = max(0, insets.bottom - reservedInsets.bottom)
            root.additionalSafeAreaInsets = insets
        }
        reservedController = nil
        reservedInsets = .zero
    }

    // MARK: - Rendu

    private var lookRequest: String {
        return "\(requestedStyle ?? "")|\(requestedPalette ?? "")"
    }

    private func loadLook() -> Look {
        guard let text = store.string(forKey: BannerController.lookKey),
              let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return Look() }
        return ApiJson.parseLook(json)
    }

    /// Rendu résolu par le serveur : appliqué à la pub affichée et gardé pour le lancement suivant
    private func updateLook(_ newLook: Look) {
        if let data = try? JSONSerialization.data(withJSONObject: ApiJson.lookJson(newLook)) {
            store.set(String(decoding: data, as: UTF8.self), forKey: BannerController.lookKey)
        }
        store.set(lookRequest, forKey: BannerController.lookRequestKey)
        guard newLook != look else { return }
        look = newLook
        if let ad = currentAd { banner?.bind(ad, look: look) }
    }

    /// L'app peut remplacer son contrôleur racine : la bannière repasse au-dessus de sa vue.
    private func keepAboveRootView(_ view: UIView, in window: UIWindow) {
        guard let root = window.rootViewController?.view, root.superview === window,
              let bannerIndex = window.subviews.firstIndex(of: view),
              let rootIndex = window.subviews.firstIndex(of: root),
              bannerIndex < rootIndex else { return }
        window.insertSubview(view, aboveSubview: root)
    }

    /// Centrée, 468 pt au plus, à 8 pt du bord dans la zone sûre (encoche, barre d'accueil).
    private func installConstraints(_ view: UIView, in window: UIWindow) {
        NSLayoutConstraint.deactivate(bannerConstraints)
        view.translatesAutoresizingMaskIntoConstraints = false
        let guide = window.safeAreaLayoutGuide
        let margin = BannerView.margin

        let height = view.heightAnchor.constraint(equalToConstant: BannerView.height)
        let fullWidth = view.widthAnchor.constraint(equalTo: guide.widthAnchor, constant: -2 * margin)
        fullWidth.priority = .defaultHigh
        var constraints = [
            view.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            view.widthAnchor.constraint(lessThanOrEqualToConstant: BannerView.maxWidth),
            view.widthAnchor.constraint(lessThanOrEqualTo: guide.widthAnchor, constant: -2 * margin),
            fullWidth,
            height
        ]
        if position == .top {
            constraints.append(view.topAnchor.constraint(equalTo: guide.topAnchor, constant: margin))
        } else {
            constraints.append(view.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -margin))
        }
        NSLayoutConstraint.activate(constraints)
        bannerConstraints = constraints
    }

    private func expectedSize(in window: UIWindow) -> CGSize {
        let available = window.safeAreaLayoutGuide.layoutFrame.width - 2 * BannerView.margin
        return CGSize(width: min(available, BannerView.maxWidth), height: BannerView.height)
    }

    /// Fenêtre principale de la scène au premier plan.
    static func hostWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let ordered = scenes.filter { $0.activationState == .foregroundActive }
            + scenes.filter { $0.activationState == .foregroundInactive }
        for scene in ordered {
            let windows = scene.windows.filter { !$0.isHidden && $0.windowLevel == .normal }
            if let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first {
                return window
            }
        }
        if let window = UIApplication.shared.delegate?.window ?? nil, !window.isHidden {
            return window
        }
        return nil
    }

    /// Langue et version majeure du système : langue des textes et statistiques d'audience de l'annonceur.
    private static func deviceInfo() -> DeviceInfo {
        DeviceInfo(
            lang: Locale.preferredLanguages.first ?? "en",
            os: "iOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)"
        )
    }

    // MARK: - Clics

    private func onTap() {
        guard let ad = currentAd else { return }
        click(ad)
    }

    /// Clic sur une pub (bannière ou interstitiel) : compté par le serveur, qui renvoie l'URL du store à ouvrir
    func click(_ ad: Ad) {
        emit(.clicked(ad.id))
        api.click(ad.token, device: Self.deviceInfo()) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let url):
                    self.openStore(url)
                case .failure(let error):
                    self.emit(.error(error.code, error.message))
                }
            }
        }
    }

    /// Lien App Store : iOS ouvre directement l'app App Store.
    private func openStore(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    // MARK: - Cycle de vie

    @objc private func didEnterBackground() {
        foreground = false
        // La rotation reprendra sur une nouvelle pub au retour au premier plan
        rotateWork?.cancel()
        rotateWork = nil
        currentAd = nil
        stopTick()
        flush()
    }

    @objc private func willEnterForeground() {
        resume()
    }

    @objc private func didBecomeActive() {
        resume()
    }

    private func resume() {
        foreground = true
        guard wantShown else { return }
        attach()
        if currentAd == nil { advance() }
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        if let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            keyboardFrame = frame
        }
    }

    @objc private func keyboardWillHide() {
        keyboardFrame = .null
    }

    // MARK: - Outils

    private func after(_ delay: TimeInterval, _ block: @escaping () -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem(block: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return work
    }

    /// Horloge monotone (indépendante de l'heure du téléphone)
    private func uptime() -> TimeInterval {
        return ProcessInfo.processInfo.systemUptime
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "BoostNetwork") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
#endif

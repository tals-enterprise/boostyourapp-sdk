import Foundation

/// Position de la bannière, en haut ou en bas de l'écran ; le contenu de l'app est réduit d'autant.
@objc(BoostBannerPosition)
public enum BannerPosition: Int {
    case top
    case bottom

    /// "top" ou "bottom" (insensible à la casse), comme dans les plugins. Par défaut : bas.
    public static func from(_ value: String?) -> BannerPosition {
        return value?.lowercased() == "top" ? .top : .bottom
    }
}

/**
 * Événement transmis à l'app via `BoostNetwork.onEvent`, toujours sur le thread principal.
 *
 * - `loaded` : une pub est affichée dans la bannière (`adId`) ;
 * - `clicked` : l'utilisateur a touché la bannière ou l'interstitiel, le store va s'ouvrir (`adId`) ;
 * - `interstitialShown` : un interstitiel couvre l'écran, mettez l'app en pause (`adId`) ;
 * - `interstitialClosed` : l'interstitiel est fermé, l'app peut reprendre (`adId`) ;
 * - `error` : `unknown_app` (appKey inconnue), `suspended`, `network`, `not_initialized`... (`code`, `message`).
 *   La bannière réessaie d'elle-même sauf pour `unknown_app`.
 */
@objc(BoostEvent)
public final class BoostEvent: NSObject {
    /// "loaded", "clicked", "interstitialShown", "interstitialClosed" ou "error"
    @objc public let type: String
    @objc public let adId: String?
    @objc public let code: String?
    @objc public let message: String?

    init(type: String, adId: String? = nil, code: String? = nil, message: String? = nil) {
        self.type = type
        self.adId = adId
        self.code = code
        self.message = message
        super.init()
    }

    static func loaded(_ adId: String) -> BoostEvent {
        return BoostEvent(type: "loaded", adId: adId)
    }

    static func clicked(_ adId: String) -> BoostEvent {
        return BoostEvent(type: "clicked", adId: adId)
    }

    static func interstitialShown(_ adId: String) -> BoostEvent {
        return BoostEvent(type: "interstitialShown", adId: adId)
    }

    static func interstitialClosed(_ adId: String) -> BoostEvent {
        return BoostEvent(type: "interstitialClosed", adId: adId)
    }

    static func error(_ code: String, _ message: String) -> BoostEvent {
        return BoostEvent(type: "error", code: code, message: message)
    }

    /// Forme transmise par les plugins : { type, adId } ou { type, code, message }.
    @objc public var dictionary: [String: Any] {
        var result: [String: Any] = ["type": type]
        if let adId = adId { result["adId"] = adId }
        if let code = code { result["code"] = code }
        if let message = message { result["message"] = message }
        return result
    }

    public override var description: String {
        return "BoostEvent(\(dictionary))"
    }
}

/**
 * Point d'entrée du SDK BoostYourApp.
 *
 * ```swift
 * BoostNetwork.initialize(appKey: "bya_…")   // une fois, idéalement au lancement
 * BoostNetwork.setStyle("dynamic", palette: "neon") // facultatif : style et couleurs des pubs
 * BoostNetwork.showBanner("bottom")           // ou "top"
 * BoostNetwork.hideBanner()
 * BoostNetwork.loadInterstitial()             // facultatif : prépare un interstitiel dès le lancement
 * BoostNetwork.showInterstitial { shown in nextLevel() } // pub plein écran, entre deux niveaux par exemple
 * BoostNetwork.onEvent { event in … }          // facultatif : loaded, clicked, interstitialShown/Closed, error
 * ```
 *
 * `init` étant réservé en Swift, l'initialisation s'appelle `initialize(appKey:)` (`initializeWithAppKey:`
 * en Objective-C). Les méthodes peuvent être appelées depuis n'importe quel thread (ponts des plugins) :
 * elles s'exécutent sur le thread principal.
 */
@objc(BoostNetwork)
public final class BoostNetwork: NSObject {

    private static let suiteName = "com.boostyourapp.network"
    private static let installationIdKey = "installation_id"

    private static var apiUrl = BoostConfig.apiUrl
    private static var apiKey = BoostConfig.apiKey
    private static var handler: ((BoostEvent) -> Void)?
    private static var style: String?
    private static var palette: String?
    #if os(iOS)
    private static var controller: BannerController?
    #endif

    private override init() {
        super.init()
    }

    /// Version du SDK.
    @objc public static var version: String {
        return BoostConfig.sdkVersion
    }

    /// Initialise le SDK avec la clé de l'app (tableau de bord BoostYourApp). Les appels suivants sont ignorés.
    @objc(initializeWithAppKey:)
    public static func initialize(appKey: String) {
        onMain {
            #if os(iOS)
            if controller != nil {
                log("BoostNetwork.initialize() déjà appelé")
                return
            }
            let store = UserDefaultsStore(suiteName: suiteName)
            // Identifiant d'installation : UUID aléatoire, sans lien avec l'appareil ni l'identifiant publicitaire
            let installationId: String
            if let saved = store.string(forKey: installationIdKey) {
                installationId = saved
            } else {
                installationId = UUID().uuidString.lowercased()
                store.set(installationId, forKey: installationIdKey)
            }
            controller = BannerController(
                appKey: appKey.trimmingCharacters(in: .whitespacesAndNewlines),
                api: ApiClient(baseUrl: apiUrl, apiKey: apiKey, sdkVersion: BoostConfig.sdkVersion),
                store: store,
                installationId: installationId,
                emit: { event in dispatch(event) }
            )
            controller?.setStyle(style, palette: palette)
            controller?.interstitials.preloadIfUsed()
            #else
            log("BoostNetwork ne fonctionne que sur iOS")
            #endif
        }
    }

    /// Rendu des pubs dans votre app : `style` "standard" (carte claire) ou "dynamic" (vitrine : fond travaillé, mot
    /// surligné, captures en éventail), et `palette`, clé d'une couleur de ce style (tableau de bord BoostYourApp,
    /// page d'intégration). Sans palette, ou palette inconnue : la première du style. Sans appel : standard.
    /// Peut être appelé avant ou après `initialize`.
    @objc(setStyle:palette:)
    public static func setStyle(_ style: String, palette: String? = nil) {
        onMain {
            self.style = style.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let key = palette?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.palette = (key?.isEmpty ?? true) ? nil : key
            #if os(iOS)
            controller?.setStyle(self.style, palette: self.palette)
            #endif
        }
    }

    /// Affiche la bannière en haut ("top") ou en bas ("bottom") de l'écran, au-dessus du contenu de l'app : la zone
    /// sûre du contrôleur racine est agrandie d'autant.
    @objc(showBanner:)
    public static func showBanner(_ position: String) {
        showBanner(position: BannerPosition.from(position))
    }

    @objc(showBannerAtPosition:)
    public static func showBanner(position: BannerPosition = .bottom) {
        onMain {
            #if os(iOS)
            guard let current = controller else {
                dispatch(.error("not_initialized", "Appelez BoostNetwork.initialize(appKey:) avant showBanner()"))
                return
            }
            current.show(position)
            #endif
        }
    }

    @objc public static func hideBanner() {
        onMain {
            #if os(iOS)
            controller?.hide()
            #endif
        }
    }

    /// Prépare un interstitiel (facultatif) : appelez-le au lancement si l'app en affiche, pour qu'il soit prêt au
    /// premier `showInterstitial`. Ensuite, le SDK en garde un prêt, et en prépare un à chaque lancement.
    @objc public static func loadInterstitial() {
        onMain {
            #if os(iOS)
            guard let current = controller else {
                dispatch(.error("not_initialized", "Appelez BoostNetwork.initialize(appKey:) avant loadInterstitial()"))
                return
            }
            current.interstitials.load()
            #endif
        }
    }

    /// Un interstitiel est prêt et le délai depuis le précédent est écoulé (3 minutes par défaut). Thread principal.
    @objc public static var isInterstitialReady: Bool {
        #if os(iOS)
        return controller?.interstitials.isReady ?? false
        #else
        return false
        #endif
    }

    /// Affiche un interstitiel plein écran, dans le style choisi avec `setStyle`. `completion` reçoit false aussitôt
    /// s'il n'y en a pas de prêt (le SDK en prépare un pour la prochaine fois) ou si le précédent date de moins de
    /// 3 minutes, et true quand l'utilisateur le ferme : reprenez alors le cours de l'app. Un interstitiel vu compte
    /// davantage qu'une bannière pour la visibilité de votre app.
    @objc(showInterstitial:)
    public static func showInterstitial(_ completion: ((Bool) -> Void)? = nil) {
        onMain {
            #if os(iOS)
            guard let current = controller else {
                dispatch(.error("not_initialized", "Appelez BoostNetwork.initialize(appKey:) avant showInterstitial()"))
                completion?(false)
                return
            }
            current.interstitials.show(completion)
            #else
            completion?(false)
            #endif
        }
    }

    /// Écoute les événements de la bannière (nil pour arrêter). Appelé sur le thread principal.
    @objc public static func onEvent(_ handler: ((BoostEvent) -> Void)?) {
        onMain {
            self.handler = handler
        }
    }

    /// Change le serveur du réseau (tests, environnement de préproduction). À appeler avant `initialize`.
    @objc(setEndpointWithApiUrl:apiKey:)
    public static func setEndpoint(apiUrl: String, apiKey: String) {
        onMain {
            #if os(iOS)
            if controller != nil {
                log("setEndpoint() doit être appelé avant initialize()")
            }
            #endif
            self.apiUrl = apiUrl
            self.apiKey = apiKey
        }
    }

    private static func dispatch(_ event: BoostEvent) {
        if event.type == "error" {
            log("\(event.code ?? "") : \(event.message ?? "")")
        }
        handler?(event)
    }

    static func log(_ message: String) {
        NSLog("[BoostNetwork] %@", message)
    }

    private static func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}

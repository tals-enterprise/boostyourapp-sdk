import Foundation

/// Une pub renvoyée par network_next.
struct Ad: Equatable {
    let id: String
    let name: String
    let descriptions: [String]
    let languageCode: String
    let iconUrl: String?
    let rating: Double?
    let cta: String
    let rotationSeconds: Int
    /// Jeton d'impression : renvoyé au serveur si la pub a été réellement visible
    let token: String
    /// Empreinte du contenu, pour le cache (`CreativeCache`) ; nil avec un serveur ancien
    var version: String? = nil
    /// Style dynamique : captures de l'app en éventail (3 au plus)
    var screenshots: [String] = []
    /// Rendu choisi par l'annonceur pour sa pub ; nil (serveur ancien, pub du service) : celui de l'app hôte
    var look: Look? = nil

    func with(token: String) -> Ad {
        return Ad(id: id, name: name, descriptions: descriptions, languageCode: languageCode, iconUrl: iconUrl,
                  rating: rating, cta: cta, rotationSeconds: rotationSeconds, token: token, version: version,
                  screenshots: screenshots, look: look)
    }
}

/// Rendu d'une pub, choisi par l'annonceur avec sa campagne (`Ad.look`) ; à défaut, rendu de l'app hôte
/// (`BoostNetwork.setStyle`, pub du service ou serveur ancien). Résolu par le serveur : style (standard ou dynamic, inconnu : standard), couleurs de la palette (#RRGGBB : background,
/// background2, border, patternColor, title, text, button, buttonText ; absente : celle du style par défaut),
/// motif du fond (stripes, grid, dots) et police de l'accroche (serif, rounded) du style dynamique.
/// En style dynamique, un mot entre étoiles dans une accroche est surligné (`Hooks`).
struct Look: Equatable {
    var style: String = "standard"
    var colors: [String: String] = [:]
    var pattern: String? = nil
    var font: String? = nil
}

/// Envoyé avec chaque appel. La langue choisit celle des textes des pubs ; avec la version majeure du système
/// (« iOS 17 »), elle alimente les statistiques d'audience de l'annonceur (compteurs agrégés côté serveur).
/// Rien d'autre sur l'appareil : ni pays, ni marque, ni modèle.
struct DeviceInfo: Equatable {
    let lang: String
    let os: String
}

struct NextRequest: Equatable {
    let appKey: String
    let installationId: String
    let device: DeviceInfo
    let recent: [String]
    let impressions: [String]
    /// Nombre de pubs voulues : nil = valeur du serveur, 0 = seulement envoyer les affichages
    var count: Int? = nil
    /// Versions des pubs en cache : le serveur n'en renvoie pas le contenu
    var cached: [String]? = nil
    /// Rendu choisi par l'app (`BoostNetwork.setStyle`) : style et clé de palette ; nil = valeurs du serveur
    var style: String? = nil
    var palette: String? = nil
    /// "interstitial" : une pub plein écran (descriptions longues, jeton d'interstitiel) ; nil = bannières
    var format: String? = nil
}

struct NextResponse: Equatable {
    let ads: [Ad]
    /// Rendu à appliquer ; nil avec un serveur ancien
    var look: Look? = nil
    let refreshSeconds: Int
    let accepted: Int
    let rejected: Int
    /// Réglages des interstitiels, renvoyés avec une demande d'interstitiel
    var interstitial: InterstitialConfig? = nil
}

/// Bouton de fermeture au bout de `closeSeconds` ; au moins `intervalSeconds` entre deux interstitiels.
struct InterstitialConfig: Equatable {
    var closeSeconds: Int = 5
    var intervalSeconds: Int = 180
}

/// Erreur d'appel : code renvoyé par le serveur (`unknown_app`, `suspended`...) ou `network`.
struct ApiError: Error, Equatable {
    let code: String
    let status: Int

    var message: String { return code }
}

/// Sérialisation, isolée pour être testée. Contrat : docs/network-sdk-api.md.
enum ApiJson {
    static func nextRequest(_ request: NextRequest) -> Data {
        var body: [String: Any] = [
            "p_app_key": request.appKey,
            "p_installation_id": request.installationId,
            "p_recent": request.recent,
            "p_impressions": request.impressions
        ]
        put(request.device, into: &body)
        if let count = request.count { body["p_count"] = count }
        if let cached = request.cached { body["p_cached"] = cached }
        if let style = request.style { body["p_style"] = style }
        if let palette = request.palette { body["p_palette"] = palette }
        if let format = request.format { body["p_format"] = format }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    static func clickRequest(_ token: String, device: DeviceInfo? = nil) -> Data {
        var body: [String: Any] = ["p_token": token]
        if let device = device { put(device, into: &body) }
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    private static func put(_ device: DeviceInfo, into body: inout [String: Any]) {
        body["p_lang"] = device.lang
        body["p_os"] = device.os
    }

    /// `cached` retrouve le contenu d'une pub que le serveur n'a pas renvoyé (déjà en cache sur l'appareil) ;
    /// une pub introuvable est ignorée.
    static func parseNext(_ data: Data, cached: (String, String) -> Ad? = { _, _ in nil }) throws -> NextResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ApiError(code: "invalid_response", status: 200)
        }
        let ads = (json["ads"] as? [[String: Any]] ?? []).compactMap { parseAd($0, cached: cached) }
        return NextResponse(
            ads: ads,
            look: (json["look"] as? [String: Any]).map(parseLook),
            refreshSeconds: clamp(int(json["refreshSeconds"]) ?? 60, 15, 600),
            accepted: int(json["accepted"]) ?? 0,
            rejected: int(json["rejected"]) ?? 0,
            interstitial: (json["interstitial"] as? [String: Any]).map(parseInterstitial)
        )
    }

    static func parseInterstitial(_ json: [String: Any]) -> InterstitialConfig {
        return InterstitialConfig(
            closeSeconds: clamp(int(json["closeSeconds"]) ?? 5, 0, 15),
            intervalSeconds: clamp(int(json["intervalSeconds"]) ?? 180, 30, 3600)
        )
    }

    static func interstitialJson(_ config: InterstitialConfig) -> [String: Any] {
        return ["closeSeconds": config.closeSeconds, "intervalSeconds": config.intervalSeconds]
    }

    static func parseClick(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = json["url"] as? String else {
            throw ApiError(code: "invalid_response", status: 200)
        }
        return url
    }

    /// Message d'une erreur PostgREST : { "code": "P0001", "message": "unknown_app" }
    static func parseErrorMessage(_ data: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let message = json["message"] as? String, !message.isEmpty else {
            return nil
        }
        return message
    }

    private static func parseAd(_ json: [String: Any], cached: (String, String) -> Ad?) -> Ad? {
        guard let token = json["token"] as? String, let id = json["id"] as? String else { return nil }
        if json["name"] == nil {
            // Contenu omis : l'appareil l'a déjà
            guard let version = json["version"] as? String else { return nil }
            return cached(id, version)?.with(token: token)
        }
        return parseContent(json)?.with(token: token)
    }

    /// Contenu d'une pub, sans jeton (réponse du serveur ou cache).
    static func parseContent(_ json: [String: Any]) -> Ad? {
        guard let id = json["id"] as? String else { return nil }
        return Ad(
            id: id,
            name: json["name"] as? String ?? "",
            descriptions: (json["descriptions"] as? [Any] ?? []).compactMap { $0 as? String },
            languageCode: json["languageCode"] as? String ?? "en",
            iconUrl: json["iconUrl"] as? String,
            rating: (json["rating"] as? NSNumber)?.doubleValue,
            cta: json["cta"] as? String ?? "Install",
            rotationSeconds: clamp(int(json["rotationSeconds"]) ?? 4, 2, 30),
            token: "",
            version: json["version"] as? String,
            screenshots: Array(parseUrls(json["screenshots"]).prefix(3)),
            look: (json["look"] as? [String: Any]).map(parseLook)
        )
    }

    /// Adresses http(s) seulement
    private static func parseUrls(_ value: Any?) -> [String] {
        return (value as? [Any] ?? []).compactMap { $0 as? String }
            .filter { $0.hasPrefix("https://") || $0.hasPrefix("http://") }
    }

    static func parseLook(_ json: [String: Any]) -> Look {
        return Look(style: json["style"] as? String ?? "standard", colors: parseColors(json["colors"]),
                    pattern: json["pattern"] as? String, font: json["font"] as? String)
    }

    static func lookJson(_ look: Look) -> [String: Any] {
        return [
            "style": look.style,
            "colors": look.colors,
            "pattern": (look.pattern as Any?) ?? NSNull(),
            "font": (look.font as Any?) ?? NSNull()
        ]
    }

    /// Couleurs #RRGGBB seulement : une valeur mal formée est ignorée (couleur par défaut du style).
    private static func parseColors(_ value: Any?) -> [String: String] {
        guard let json = value as? [String: Any] else { return [:] }
        var colors: [String: String] = [:]
        for (key, raw) in json {
            if let color = raw as? String, isHexColor(color) { colors[key] = color }
        }
        return colors
    }

    static func isHexColor(_ value: String) -> Bool {
        guard value.count == 7, value.hasPrefix("#") else { return false }
        return value.dropFirst().allSatisfy { $0.isHexDigit }
    }

    static func contentJson(_ ad: Ad) -> [String: Any] {
        return [
            "id": ad.id,
            "name": ad.name,
            "descriptions": ad.descriptions,
            "languageCode": ad.languageCode,
            "iconUrl": (ad.iconUrl as Any?) ?? NSNull(),
            "rating": (ad.rating as Any?) ?? NSNull(),
            "cta": ad.cta,
            "rotationSeconds": ad.rotationSeconds,
            "version": (ad.version as Any?) ?? NSNull(),
            "screenshots": ad.screenshots,
            "look": (ad.look.map(lookJson) as Any?) ?? NSNull()
        ]
    }

    private static func int(_ value: Any?) -> Int? {
        return (value as? NSNumber)?.intValue
    }

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        return min(max(value, low), high)
    }
}

/// Appels des fonctions du réseau via l'API REST de Supabase (POST /rest/v1/rpc/<fonction>).
/// Les résultats arrivent sur une file de URLSession : à l'appelant de revenir sur le thread principal.
final class ApiClient {
    private let baseUrl: String
    private let apiKey: String
    private let sdkVersion: String
    private let session: URLSession

    init(baseUrl: String, apiKey: String, sdkVersion: String, session: URLSession? = nil) {
        self.baseUrl = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        self.apiKey = apiKey
        self.sdkVersion = sdkVersion
        if let session = session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: configuration)
        }
    }

    func next(_ request: NextRequest, cached: @escaping (String, String) -> Ad? = { _, _ in nil },
              completion: @escaping (Result<NextResponse, ApiError>) -> Void) {
        post("network_next", body: ApiJson.nextRequest(request)) { result in
            completion(result.flatMap { (data: Data) -> Result<NextResponse, ApiError> in
                do {
                    return .success(try ApiJson.parseNext(data, cached: cached))
                } catch {
                    return .failure(error as? ApiError ?? ApiError(code: "invalid_response", status: 200))
                }
            })
        }
    }

    func click(_ token: String, device: DeviceInfo? = nil, completion: @escaping (Result<String, ApiError>) -> Void) {
        post("network_click", body: ApiJson.clickRequest(token, device: device)) { result in
            completion(result.flatMap { (data: Data) -> Result<String, ApiError> in
                do {
                    return .success(try ApiJson.parseClick(data))
                } catch {
                    return .failure(error as? ApiError ?? ApiError(code: "invalid_response", status: 200))
                }
            })
        }
    }

    private func post(_ function: String, body: Data, completion: @escaping (Result<Data, ApiError>) -> Void) {
        guard let url = URL(string: "\(baseUrl)/rest/v1/rpc/\(function)") else {
            completion(.failure(ApiError(code: "network", status: 0)))
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("boostnetwork-ios/\(sdkVersion)", forHTTPHeaderField: "X-Client-Info")
        request.httpBody = body

        session.dataTask(with: request) { data, response, error in
            if error != nil {
                completion(.failure(ApiError(code: "network", status: 0)))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let payload = data ?? Data()
            if (200..<300).contains(status) {
                completion(.success(payload))
            } else {
                completion(.failure(ApiError(code: ApiJson.parseErrorMessage(payload) ?? "http_\(status)", status: status)))
            }
        }.resume()
    }
}

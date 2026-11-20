import Foundation

/// Stockage clé-valeur persistant (UserDefaults dans le SDK, un dictionnaire dans les tests).
protocol KeyValueStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

final class UserDefaultsStore: KeyValueStore {
    private let defaults: UserDefaults

    init(suiteName: String) {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    func string(forKey key: String) -> String? {
        return defaults.string(forKey: key)
    }

    func set(_ value: String?, forKey key: String) {
        if let value = value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/**
 * Pubs reçues en attente d'affichage. Une pub trop ancienne est écartée : son jeton
 * expirerait avant d'être renvoyé (30 minutes côté serveur).
 */
final class AdQueue {
    private let clock: () -> TimeInterval
    private let maxAge: TimeInterval
    private let recentSize: Int
    private var ads: [(ad: Ad, at: TimeInterval)] = []
    private var recent: [String] = []

    init(clock: @escaping () -> TimeInterval, maxAge: TimeInterval = 20 * 60, recentSize: Int = 5) {
        self.clock = clock
        self.maxAge = maxAge
        self.recentSize = recentSize
    }

    var count: Int {
        dropExpired()
        return ads.count
    }

    func add(_ list: [Ad]) {
        let now = clock()
        ads.append(contentsOf: list.map { (ad: $0, at: now) })
    }

    /// Pub suivante, mémorisée comme récente pour ne pas la remontrer tout de suite au même appareil.
    func poll() -> Ad? {
        dropExpired()
        guard !ads.isEmpty else { return nil }
        let ad = ads.removeFirst().ad
        recent.removeAll { $0 == ad.id }
        recent.append(ad.id)
        if recent.count > recentSize {
            recent.removeFirst(recent.count - recentSize)
        }
        return ad
    }

    var recentIds: [String] {
        return recent
    }

    private func dropExpired() {
        let limit = clock() - maxAge
        while let first = ads.first, first.at < limit {
            ads.removeFirst()
        }
    }
}

/**
 * Jetons des pubs réellement visibles, en attente d'envoi. Persistés pour survivre à l'arrêt de l'app ;
 * ceux de plus de 30 minutes sont abandonnés (expirés côté serveur).
 */
final class PendingImpressions {
    private static let key = "pending_impressions"

    private let store: KeyValueStore
    private let clock: () -> TimeInterval
    private let maxAge: TimeInterval
    private let maxStored: Int
    private var entries: [(token: String, at: TimeInterval)] = []
    /// Jetons partis avec une demande en cours (bannières et interstitiels peuvent appeler en même temps)
    private var inFlight = Set<String>()

    init(store: KeyValueStore, clock: @escaping () -> TimeInterval, maxAge: TimeInterval = 30 * 60, maxStored: Int = 200) {
        self.store = store
        self.clock = clock
        self.maxAge = maxAge
        self.maxStored = maxStored

        if let saved = store.string(forKey: PendingImpressions.key) {
            if let data = saved.data(using: .utf8),
               let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                for item in array {
                    if let token = item["t"] as? String, let at = (item["at"] as? NSNumber)?.doubleValue {
                        entries.append((token: token, at: at))
                    }
                }
            } else {
                store.set(nil, forKey: PendingImpressions.key)
            }
        }
        prune()
    }

    var count: Int {
        prune()
        return entries.count
    }

    func add(_ token: String) {
        entries.append((token: token, at: clock()))
        if entries.count > maxStored {
            entries.removeFirst(entries.count - maxStored)
        }
        save()
    }

    /// Jetons qui ne sont pas déjà partis avec une autre demande
    var available: Int {
        prune()
        return entries.filter { !inFlight.contains($0.token) }.count
    }

    /// Les plus anciens d'abord, hors jetons déjà en cours d'envoi ; ils restent en attente jusqu'à `confirm`, ou
    /// redeviennent disponibles avec `release` si l'envoi échoue.
    func take(_ max: Int) -> [String] {
        prune()
        let tokens = entries.lazy.map { $0.token }.filter { !self.inFlight.contains($0) }.prefix(max)
        let taken = Array(tokens)
        inFlight.formUnion(taken)
        return taken
    }

    /// Retire les jetons transmis au serveur (acceptés ou refusés : les renvoyer ne servirait à rien).
    func confirm(_ tokens: [String]) {
        guard !tokens.isEmpty else { return }
        let sent = Set(tokens)
        inFlight.subtract(sent)
        entries.removeAll { sent.contains($0.token) }
        save()
    }

    /// Envoi échoué : les jetons repartiront avec la demande suivante
    func release(_ tokens: [String]) {
        inFlight.subtract(tokens)
    }

    private func prune() {
        let limit = clock() - maxAge
        let before = entries.count
        entries.removeAll { $0.at < limit }
        if entries.count != before {
            save()
        }
    }

    private func save() {
        guard !entries.isEmpty else {
            store.set(nil, forKey: PendingImpressions.key)
            return
        }
        let array = entries.map { ["t": $0.token, "at": $0.at] as [String: Any] }
        if let data = try? JSONSerialization.data(withJSONObject: array) {
            store.set(String(data: data, encoding: .utf8), forKey: PendingImpressions.key)
        }
    }
}

/**
 * Contenu des pubs déjà reçues (sans jeton). Le SDK envoie leurs versions avec chaque demande : le serveur ne
 * renvoie alors que l'id, la version et un jeton, ce qui allège beaucoup les réponses. Persisté ; les pubs
 * les moins récemment reçues ou affichées sont oubliées au-delà de `maxEntries`.
 * Lu depuis la file de URLSession (lecture de la réponse) et écrit depuis le thread principal : verrouillé.
 */
final class CreativeCache {
    private static let key = "creative_cache"

    private let store: KeyValueStore
    private let maxEntries: Int
    private let lock = NSLock()
    private var entries: [String: Ad] = [:]
    /// Ids du moins au plus récemment utilisé
    private var order: [String] = []

    init(store: KeyValueStore, maxEntries: Int = 50) {
        self.store = store
        self.maxEntries = maxEntries
        guard let saved = store.string(forKey: CreativeCache.key) else { return }
        if let data = saved.data(using: .utf8),
           let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            for item in array {
                if let ad = ApiJson.parseContent(item), ad.version != nil, entries[ad.id] == nil {
                    entries[ad.id] = ad
                    order.append(ad.id)
                }
            }
        } else {
            store.set(nil, forKey: CreativeCache.key)
        }
    }

    var versions: [String] {
        lock.lock()
        defer { lock.unlock() }
        return order.compactMap { entries[$0]?.version }
    }

    func get(id: String, version: String) -> Ad? {
        lock.lock()
        defer { lock.unlock() }
        guard let ad = entries[id], ad.version == version else { return nil }
        touch(id)
        return ad
    }

    /// Mémorise le contenu des pubs reçues (celles qui ont une version).
    func put(_ ads: [Ad]) {
        lock.lock()
        defer { lock.unlock() }
        var changed = false
        for ad in ads {
            guard let version = ad.version else { continue }
            if entries[ad.id]?.version != version {
                entries[ad.id] = ad.with(token: "")
                changed = true
            }
            touch(ad.id)
        }
        while order.count > maxEntries {
            entries.removeValue(forKey: order.removeFirst())
            changed = true
        }
        if changed { save() }
    }

    private func touch(_ id: String) {
        order.removeAll { $0 == id }
        order.append(id)
    }

    private func save() {
        guard !order.isEmpty else {
            store.set(nil, forKey: CreativeCache.key)
            return
        }
        let array = order.compactMap { entries[$0] }.map(ApiJson.contentJson)
        if let data = try? JSONSerialization.data(withJSONObject: array) {
            store.set(String(data: data, encoding: .utf8), forKey: CreativeCache.key)
        }
    }
}

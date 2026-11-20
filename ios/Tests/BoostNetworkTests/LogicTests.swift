import XCTest
@testable import BoostNetwork

private final class MemoryStore: KeyValueStore {
    var values: [String: String] = [:]

    func string(forKey key: String) -> String? {
        return values[key]
    }

    func set(_ value: String?, forKey key: String) {
        values[key] = value
    }
}

private func ad(_ id: String) -> Ad {
    return Ad(id: id, name: id, descriptions: ["a"], languageCode: "en", iconUrl: nil, rating: nil,
              cta: "Install", rotationSeconds: 4, token: "token-\(id)")
}

private func viewable(_ fraction: Double = 1) -> ViewabilitySample {
    return ViewabilitySample(visibleFraction: fraction, shown: true, opaque: true, sizeOk: true, appActive: true)
}

private func versioned(_ id: String, _ version: String, name: String? = nil) -> Ad {
    return Ad(id: id, name: name ?? id, descriptions: ["a"], languageCode: "en", iconUrl: nil, rating: nil,
              cta: "Install", rotationSeconds: 4, token: "token-\(id)", version: version)
}

final class HooksTests: XCTestCase {
    func testStarredWordsAreMarked() {
        let marked = Hooks.parse("Prêt en *5 minutes* et *gratuit*")
        XCTAssertEqual(marked.text, "Prêt en 5 minutes et gratuit")
        XCTAssertEqual(marked.marks, [NSRange(location: 8, length: 9), NSRange(location: 21, length: 7)])
        // Étoile seule : gardée telle quelle
        XCTAssertEqual(Hooks.parse("Note 4* sur 5"), Hooks.Marked(text: "Note 4* sur 5", marks: []))
        XCTAssertEqual(Hooks.plain("Prêt en *5 minutes*"), "Prêt en 5 minutes")
        XCTAssertEqual(Hooks.parse("").text, "")
    }
}

final class CreativeCacheTests: XCTestCase {
    func testVersionsReplacementLimitAndPersistence() {
        let store = MemoryStore()
        let cache = CreativeCache(store: store, maxEntries: 2)
        cache.put([versioned("a", "va"), versioned("b", "vb"), ad("old")])
        XCTAssertEqual(cache.versions, ["va", "vb"]) // sans version : pas mis en cache
        XCTAssertEqual(cache.get(id: "a", version: "va")?.token, "") // le jeton n'est pas gardé
        XCTAssertNil(cache.get(id: "a", version: "autre"))

        cache.put([versioned("c", "vc")]) // « b » est la moins récemment utilisée
        XCTAssertEqual(Set(cache.versions), ["va", "vc"])
        cache.put([versioned("a", "va2", name: "A2")])
        XCTAssertEqual(cache.get(id: "a", version: "va2")?.name, "A2")

        let reloaded = CreativeCache(store: store, maxEntries: 2)
        XCTAssertEqual(Set(reloaded.versions), ["vc", "va2"])
        XCTAssertEqual(reloaded.get(id: "c", version: "vc"), versioned("c", "vc").with(token: ""))
    }
}

final class AdQueueTests: XCTestCase {
    func testPollsInOrderAndRemembersRecentAds() {
        var now: TimeInterval = 0
        let queue = AdQueue(clock: { now }, recentSize: 2)
        queue.add([ad("a"), ad("b"), ad("c")])

        XCTAssertEqual(queue.poll()?.id, "a")
        XCTAssertEqual(queue.poll()?.id, "b")
        XCTAssertEqual(queue.poll()?.id, "c")
        XCTAssertNil(queue.poll())
        XCTAssertEqual(queue.recentIds, ["b", "c"])

        // Pub déjà récente : elle repasse en dernière position, sans doublon
        queue.add([ad("b")])
        _ = queue.poll()
        XCTAssertEqual(queue.recentIds, ["c", "b"])
        now += 1
    }

    func testDropsAdsWhoseTokenWouldExpire() {
        var now: TimeInterval = 0
        let queue = AdQueue(clock: { now }, maxAge: 20 * 60)
        queue.add([ad("old")])
        now = 10 * 60
        queue.add([ad("new")])
        now = 21 * 60

        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.poll()?.id, "new")
    }
}

final class PendingImpressionsTests: XCTestCase {
    func testPersistsUntilConfirmed() {
        let store = MemoryStore()
        var now: TimeInterval = 1000
        let pending = PendingImpressions(store: store, clock: { now })
        pending.add("t1")
        pending.add("t2")
        pending.add("t3")

        XCTAssertEqual(pending.take(2), ["t1", "t2"])
        // Déjà partis avec une demande en cours : pas renvoyés par une autre
        XCTAssertEqual(pending.take(10), ["t3"])
        XCTAssertEqual(pending.available, 0)
        pending.release(["t3"])
        pending.confirm(["t1", "t2"])
        XCTAssertEqual(pending.take(10), ["t3"])

        // Relu après un redémarrage de l'app
        now += 60
        let reloaded = PendingImpressions(store: store, clock: { now })
        XCTAssertEqual(reloaded.take(10), ["t3"])
    }

    func testDropsExpiredTokensAndCapsStorage() {
        let store = MemoryStore()
        var now: TimeInterval = 0
        let pending = PendingImpressions(store: store, clock: { now }, maxAge: 30 * 60, maxStored: 3)
        pending.add("old")
        now = 31 * 60
        pending.add("a")
        pending.add("b")
        pending.add("c")
        pending.add("d")

        XCTAssertEqual(pending.take(10), ["b", "c", "d"])

        pending.confirm(["b", "c", "d"])
        XCTAssertNil(store.values["pending_impressions"])
    }

    func testIgnoresCorruptedStorage() {
        let store = MemoryStore()
        store.values["pending_impressions"] = "{not json"
        let pending = PendingImpressions(store: store, clock: { 0 })

        XCTAssertEqual(pending.count, 0)
        XCTAssertNil(store.values["pending_impressions"])
    }
}

final class ViewabilityTests: XCTestCase {
    func testEveryConditionIsRequired() {
        XCTAssertTrue(viewable().viewable)
        XCTAssertTrue(viewable(0.5).viewable)
        XCTAssertFalse(viewable(0.49).viewable)

        var sample = viewable()
        sample.shown = false
        XCTAssertFalse(sample.viewable)
        sample = viewable()
        sample.opaque = false
        XCTAssertFalse(sample.viewable)
        sample = viewable()
        sample.sizeOk = false
        XCTAssertFalse(sample.viewable)
        sample = viewable()
        sample.appActive = false
        XCTAssertFalse(sample.viewable)
    }

    func testCountsOnceAfterOneContinuousSecond() {
        let tracker = ViewabilityTracker()
        var counted = 0
        var now: TimeInterval = 0
        while now <= 3 {
            if tracker.onSample(viewable(), now: now) { counted += 1 }
            now += 0.1
        }
        XCTAssertEqual(counted, 1)
    }

    func testInterruptionRestartsTheSecond() {
        let tracker = ViewabilityTracker()
        XCTAssertFalse(tracker.onSample(viewable(), now: 0))
        XCTAssertFalse(tracker.onSample(viewable(), now: 0.25))
        XCTAssertFalse(tracker.onSample(viewable(), now: 0.5))
        XCTAssertFalse(tracker.onSample(viewable(), now: 0.75))
        // Moins de 50 % visible : la seconde repart de zéro
        XCTAssertFalse(tracker.onSample(viewable(0.2), now: 1.0))
        XCTAssertFalse(tracker.onSample(viewable(), now: 1.25))
        XCTAssertFalse(tracker.onSample(viewable(), now: 1.5))
        XCTAssertFalse(tracker.onSample(viewable(), now: 1.75))
        XCTAssertFalse(tracker.onSample(viewable(), now: 2.0))
        XCTAssertTrue(tracker.onSample(viewable(), now: 2.25))
    }

    func testGapBetweenSamplesBreaksContinuity() {
        let tracker = ViewabilityTracker()
        XCTAssertFalse(tracker.onSample(viewable(), now: 0))
        XCTAssertFalse(tracker.onSample(viewable(), now: 0.25))
        // App suspendue 2 s : la seconde repart de zéro
        XCTAssertFalse(tracker.onSample(viewable(), now: 2.25))
        XCTAssertFalse(tracker.onSample(viewable(), now: 2.5))
        XCTAssertFalse(tracker.onSample(viewable(), now: 2.75))
        XCTAssertFalse(tracker.onSample(viewable(), now: 3.0))
        XCTAssertTrue(tracker.onSample(viewable(), now: 3.25))
    }

    func testResetAllowsCountingTheNextAd() {
        let tracker = ViewabilityTracker()
        var counted = 0
        for step in 0...4 where tracker.onSample(viewable(), now: Double(step) * 0.25) {
            counted += 1
        }
        XCTAssertEqual(counted, 1)

        tracker.reset()
        XCTAssertFalse(tracker.onSample(viewable(), now: 5))
        XCTAssertFalse(tracker.onSample(viewable(), now: 5.5))
        XCTAssertTrue(tracker.onSample(viewable(), now: 6))
    }
}

package com.boostyourapp.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LogicTest {

    @Test
    fun `accroches, passages entre étoiles surlignés`() {
        val marked = Hooks.parse("Prêt en *5 minutes* et *gratuit*")
        assertEquals("Prêt en 5 minutes et gratuit", marked.text)
        assertEquals(listOf(8..16, 21..27), marked.marks)
        assertEquals("5 minutes", marked.text.substring(marked.marks[0]))
        // Étoile seule : gardée telle quelle
        assertEquals(Hooks.Marked("Note 4* sur 5", emptyList()), Hooks.parse("Note 4* sur 5"))
        assertEquals("Prêt en 5 minutes", Hooks.plain("Prêt en *5 minutes*"))
        assertEquals("", Hooks.parse("").text)
    }

    private var now = 1_000_000L
    private val clock = { now }

    private fun ad(id: String) = Ad(id, id, listOf("d"), "en", null, null, "Free", 4, "token-$id")

    private class MapStore : KeyValueStore {
        val values = mutableMapOf<String, String>()
        override fun getString(key: String) = values[key]
        override fun putString(key: String, value: String?) {
            if (value == null) values.remove(key) else values[key] = value
        }
    }

    // --- Cache des pubs ------------------------------------------------------------------

    @Test
    fun `cache des pubs, versions, remplacement, limite et persistance`() {
        val store = MapStore()
        val cache = CreativeCache(store, maxEntries = 2)
        cache.putAll(listOf(ad("a").copy(version = "va"), ad("b").copy(version = "vb"), ad("old")))
        assertEquals(listOf("va", "vb"), cache.versions()) // sans version : pas mis en cache
        assertEquals("", cache.get("a", "va")?.token) // le jeton n'est pas gardé
        assertNull(cache.get("a", "autre"))

        cache.putAll(listOf(ad("c").copy(version = "vc"))) // « b » est la moins récemment utilisée
        assertEquals(listOf("va", "vc"), cache.versions())
        cache.putAll(listOf(ad("a").copy(name = "A2", version = "va2")))
        assertEquals("A2", cache.get("a", "va2")?.name)

        val reloaded = CreativeCache(store, maxEntries = 2)
        assertEquals(setOf("vc", "va2"), reloaded.versions().toSet())
        assertEquals(ad("c").copy(version = "vc", token = ""), reloaded.get("c", "vc"))
    }

    // --- File de pubs --------------------------------------------------------------------

    @Test
    fun `file de pubs dans l'ordre, pubs récentes mémorisées`() {
        val queue = AdQueue(clock, recentSize = 2)
        queue.addAll(listOf(ad("a"), ad("b"), ad("c")))
        assertEquals(3, queue.size)
        assertEquals("a", queue.poll()?.id)
        assertEquals("b", queue.poll()?.id)
        assertEquals("c", queue.poll()?.id)
        assertNull(queue.poll())
        assertEquals(listOf("b", "c"), queue.recentIds())
    }

    @Test
    fun `les pubs trop anciennes sont écartées (jeton bientôt expiré)`() {
        val queue = AdQueue(clock, maxAgeMs = 1_000)
        queue.addAll(listOf(ad("old")))
        now += 500
        queue.addAll(listOf(ad("new")))
        now += 600
        assertEquals("new", queue.poll()?.id)
    }

    // --- Affichages en attente ------------------------------------------------------------

    @Test
    fun `affichages en attente persistés jusqu'à confirmation`() {
        val store = MapStore()
        val pending = PendingImpressions(store, clock)
        pending.add("t1")
        pending.add("t2")
        pending.add("t3")
        assertEquals(listOf("t1", "t2"), pending.take(2))
        // Déjà partis avec une demande en cours : pas renvoyés par une autre
        assertEquals(listOf("t3"), pending.take(10))
        assertEquals(0, pending.available)
        pending.release(listOf("t3"))
        assertEquals(listOf("t3"), pending.take(10))

        // Redémarrage de l'app : rien n'est perdu
        val restored = PendingImpressions(store, clock)
        assertEquals(3, restored.size)
        restored.confirm(listOf("t1", "t2"))
        assertEquals(listOf("t3"), restored.take(10))
        assertEquals(1, PendingImpressions(store, clock).size)

        restored.confirm(listOf("t3"))
        assertNull(store.values["pending_impressions"])
    }

    @Test
    fun `affichages expirés abandonnés, stockage borné`() {
        val store = MapStore()
        val pending = PendingImpressions(store, clock, maxAgeMs = 1_000, maxStored = 3)
        pending.add("old")
        now += 2_000
        listOf("a", "b", "c", "d").forEach(pending::add)
        assertEquals(listOf("b", "c", "d"), pending.take(10))

        store.values["pending_impressions"] = "corrompu"
        assertEquals(0, PendingImpressions(store, clock).size)
    }

    // --- Visibilité -----------------------------------------------------------------------------

    private val visible = ViewabilitySample(1.0, shown = true, opaque = true, sizeOk = true, windowFocused = true, appForeground = true, screenOn = true)

    private fun ViewabilityTracker.feed(sample: ViewabilitySample, from: Long, to: Long, step: Long = 100): Int {
        var counted = 0
        var t = from
        while (t <= to) {
            if (onSample(sample, t)) counted++
            t += step
        }
        return counted
    }

    @Test
    fun `une impression après 1 seconde continue, une seule fois`() {
        val tracker = ViewabilityTracker()
        assertEquals(0, tracker.feed(visible, 0, 900))
        assertTrue(tracker.onSample(visible, 1_000))
        assertEquals(0, tracker.feed(visible, 1_100, 10_000))

        tracker.reset()
        assertEquals(1, tracker.feed(visible, 20_000, 21_000))
    }

    @Test
    fun `50 % visibles suffisent, pas 49 %`() {
        assertTrue(visible.copy(visibleFraction = 0.5).viewable)
        assertFalse(visible.copy(visibleFraction = 0.49).viewable)
        assertEquals(1, ViewabilityTracker().feed(visible.copy(visibleFraction = 0.5), 0, 1_000))
        assertEquals(0, ViewabilityTracker().feed(visible.copy(visibleFraction = 0.49), 0, 5_000))
    }

    @Test
    fun `chaque condition est requise`() {
        val failing = listOf(
            visible.copy(shown = false),
            visible.copy(opaque = false),
            visible.copy(sizeOk = false),
            visible.copy(windowFocused = false),
            visible.copy(appForeground = false),
            visible.copy(screenOn = false)
        )
        for (sample in failing) {
            assertFalse(sample.toString(), sample.viewable)
            assertEquals(sample.toString(), 0, ViewabilityTracker().feed(sample, 0, 5_000))
        }
    }

    @Test
    fun `une interruption remet le compteur à zéro`() {
        val tracker = ViewabilityTracker()
        tracker.feed(visible, 0, 800)
        assertFalse(tracker.onSample(visible.copy(visibleFraction = 0.2), 900))
        assertEquals(0, tracker.feed(visible, 1_000, 1_800))
        assertTrue(tracker.onSample(visible, 2_000))
    }

    @Test
    fun `un trou dans les mesures (app suspendue) rompt la continuité`() {
        val tracker = ViewabilityTracker()
        tracker.feed(visible, 0, 700)
        // Plus de mesure pendant 5 s : la pub n'a pas été vue 1 s d'affilée
        assertFalse(tracker.onSample(visible, 5_700))
        assertEquals(0, tracker.feed(visible, 5_800, 6_600))
        assertTrue(tracker.onSample(visible, 6_700))
    }

    @Test
    fun `position de la bannière`() {
        assertEquals(BannerPosition.TOP, BannerPosition.from("top"))
        assertEquals(BannerPosition.TOP, BannerPosition.from("TOP"))
        assertEquals(BannerPosition.BOTTOM, BannerPosition.from("bottom"))
        assertEquals(BannerPosition.BOTTOM, BannerPosition.from(null))
        assertEquals("clicked", BoostEvent.Clicked("x").type)
    }
}

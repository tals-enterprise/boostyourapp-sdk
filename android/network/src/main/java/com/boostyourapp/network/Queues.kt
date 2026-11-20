package com.boostyourapp.network

import org.json.JSONArray
import org.json.JSONObject

/** Stockage clé-valeur persistant (SharedPreferences sur Android, une Map dans les tests). */
internal interface KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String?)
}

/**
 * Pubs reçues en attente d'affichage. Une pub trop ancienne est écartée : son jeton
 * expirerait avant d'être renvoyé (30 minutes côté serveur).
 */
internal class AdQueue(
    private val clock: () -> Long,
    private val maxAgeMs: Long = 20 * 60_000L,
    private val recentSize: Int = 5
) {
    private val ads = ArrayDeque<Pair<Ad, Long>>()
    private val recent = ArrayDeque<String>()

    val size: Int
        get() {
            dropExpired()
            return ads.size
        }

    fun addAll(list: List<Ad>) {
        val now = clock()
        list.forEach { ads.addLast(it to now) }
    }

    /** Pub suivante, mémorisée comme récente pour ne pas la remontrer tout de suite au même appareil. */
    fun poll(): Ad? {
        dropExpired()
        val ad = ads.removeFirstOrNull()?.first ?: return null
        recent.remove(ad.id)
        recent.addLast(ad.id)
        while (recent.size > recentSize) recent.removeFirst()
        return ad
    }

    fun recentIds(): List<String> = recent.toList()

    private fun dropExpired() {
        val limit = clock() - maxAgeMs
        while (ads.firstOrNull()?.let { it.second < limit } == true) ads.removeFirst()
    }
}

/**
 * Jetons des pubs réellement visibles, en attente d'envoi. Persistés pour survivre à l'arrêt de l'app ;
 * ceux de plus de 30 minutes sont abandonnés (expirés côté serveur).
 */
internal class PendingImpressions(
    private val store: KeyValueStore,
    private val clock: () -> Long,
    private val maxAgeMs: Long = 30 * 60_000L,
    private val maxStored: Int = 200
) {
    private val entries = ArrayList<Pair<String, Long>>()
    /** Jetons partis avec une demande en cours (bannières et interstitiels peuvent appeler en même temps) */
    private val inFlight = HashSet<String>()

    init {
        store.getString(KEY)?.let { saved ->
            try {
                val array = JSONArray(saved)
                for (i in 0 until array.length()) {
                    val item = array.getJSONObject(i)
                    entries.add(item.getString("t") to item.getLong("at"))
                }
            } catch (e: Exception) {
                store.putString(KEY, null)
            }
        }
        prune()
    }

    val size: Int
        get() {
            prune()
            return entries.size
        }

    fun add(token: String) {
        entries.add(token to clock())
        while (entries.size > maxStored) entries.removeAt(0)
        save()
    }

    /** Jetons qui ne sont pas déjà partis avec une autre demande */
    val available: Int
        get() {
            prune()
            return entries.count { it.first !in inFlight }
        }

    /**
     * Les plus anciens d'abord, hors jetons déjà en cours d'envoi ; ils restent en attente jusqu'à [confirm], ou
     * redeviennent disponibles avec [release] si l'envoi échoue.
     */
    fun take(max: Int): List<String> {
        prune()
        val tokens = entries.asSequence().map { it.first }.filter { it !in inFlight }.take(max).toList()
        inFlight.addAll(tokens)
        return tokens
    }

    /** Retire les jetons transmis au serveur (acceptés ou refusés : les renvoyer ne servirait à rien). */
    fun confirm(tokens: Collection<String>) {
        if (tokens.isEmpty()) return
        val sent = tokens.toHashSet()
        inFlight.removeAll(sent)
        entries.removeAll { it.first in sent }
        save()
    }

    /** Envoi échoué : les jetons repartiront avec la demande suivante */
    fun release(tokens: Collection<String>) {
        inFlight.removeAll(tokens.toSet())
    }

    private fun prune() {
        val limit = clock() - maxAgeMs
        if (entries.removeAll { it.second < limit }) save()
    }

    private fun save() {
        val array = JSONArray()
        entries.forEach { array.put(JSONObject().put("t", it.first).put("at", it.second)) }
        store.putString(KEY, if (entries.isEmpty()) null else array.toString())
    }

    private companion object {
        const val KEY = "pending_impressions"
    }
}

/**
 * Contenu des pubs déjà reçues (sans jeton). Le SDK envoie leurs versions avec chaque demande : le serveur ne
 * renvoie alors que l'id, la version et un jeton, ce qui allège beaucoup les réponses. Persisté ; les pubs
 * les moins récemment reçues ou affichées sont oubliées au-delà de [maxEntries].
 * Lu depuis le thread réseau (lecture de la réponse) et écrit depuis le thread principal : synchronisé.
 */
internal class CreativeCache(
    private val store: KeyValueStore,
    private val maxEntries: Int = 50
) {
    /** Ordre d'accès : la première entrée est la moins récemment utilisée */
    private val entries = LinkedHashMap<String, Ad>(16, 0.75f, true)

    init {
        store.getString(KEY)?.let { saved ->
            try {
                val array = JSONArray(saved)
                for (i in 0 until array.length()) {
                    ApiJson.parseContent(array.getJSONObject(i))?.takeIf { it.version != null }?.let { entries[it.id] = it }
                }
            } catch (e: Exception) {
                store.putString(KEY, null)
            }
        }
    }

    @Synchronized
    fun versions(): List<String> = entries.values.mapNotNull { it.version }

    @Synchronized
    fun get(id: String, version: String): Ad? = entries[id]?.takeIf { it.version == version }

    /** Mémorise le contenu des pubs reçues (celles qui ont une version). */
    @Synchronized
    fun putAll(ads: List<Ad>) {
        var changed = false
        for (ad in ads) {
            val version = ad.version ?: continue
            val known = entries[ad.id]
            if (known?.version != version) {
                entries[ad.id] = ad.copy(token = "")
                changed = true
            }
        }
        while (entries.size > maxEntries) {
            entries.remove(entries.keys.first())
            changed = true
        }
        if (changed) save()
    }

    private fun save() {
        val array = JSONArray()
        entries.values.forEach { array.put(ApiJson.contentJson(it)) }
        store.putString(KEY, if (entries.isEmpty()) null else array.toString())
    }

    private companion object {
        const val KEY = "creative_cache"
    }
}

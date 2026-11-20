package com.boostyourapp.network

import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.ServerSocket
import kotlin.concurrent.thread

class ApiTest {

    private lateinit var server: ServerSocket
    private val requests = mutableListOf<Triple<String, Map<String, String>, String>>()
    @Volatile private var nextStatus = 200
    @Volatile private var nextBody = ""

    /** Serveur HTTP minimal (une requête par connexion) : les tests compilent contre android.jar, sans com.sun.net.httpserver. */
    @Before
    fun start() {
        server = ServerSocket(0, 10, InetAddress.getByName("127.0.0.1"))
        thread(isDaemon = true) {
            while (!server.isClosed) {
                val socket = try { server.accept() } catch (e: Exception) { break }
                socket.use {
                    val reader = BufferedReader(InputStreamReader(it.getInputStream(), Charsets.UTF_8))
                    val path = reader.readLine().split(" ")[1]
                    val headers = mutableMapOf<String, String>()
                    while (true) {
                        val line = reader.readLine()
                        if (line.isNullOrEmpty()) break
                        headers[line.substringBefore(":").trim().lowercase()] = line.substringAfter(":").trim()
                    }
                    val body = CharArray(headers["content-length"]?.toInt() ?: 0)
                    var read = 0
                    while (read < body.size) read += reader.read(body, read, body.size - read)
                    synchronized(requests) { requests += Triple(path, headers, String(body)) }
                    val bytes = nextBody.toByteArray(Charsets.UTF_8)
                    val out = it.getOutputStream()
                    val head = listOf("HTTP/1.1 $nextStatus X", "Content-Type: application/json", "Content-Length: ${bytes.size}", "Connection: close", "", "")
                    out.write(head.joinToString("\r\n").toByteArray())
                    out.write(bytes)
                    out.flush()
                }
            }
        }
    }

    @After
    fun stop() = server.close()

    private fun client() = ApiClient("http://127.0.0.1:${server.localPort}/", "sb_publishable_test", "1.2.3")

    @Test
    fun `network_next envoie les paramètres attendus par la fonction SQL`() {
        nextBody = """
            {"ads":[{"id":"ad-1","name":"Mon App","descriptions":["Un","Deux"],"languageCode":"fr",
              "iconUrl":"https://icon","rating":4.5,"cta":"Gratuit","rotationSeconds":4,"token":"tok-1"},
              {"id":"ad-2","name":"Autre","descriptions":[],"languageCode":"en","iconUrl":null,"rating":null,
              "cta":"Free","rotationSeconds":99,"token":"tok-2"}],
             "refreshSeconds":60,"accepted":2,"rejected":1}
        """.trimIndent()

        val response = client().next(NextRequest("bya_key", "inst-1", DeviceInfo("fr-FR", "Android 14"), listOf("ad-9"), listOf("t1", "t2")))

        val (path, headers, body) = requests.single()
        assertEquals("/rest/v1/rpc/network_next", path)
        assertEquals("sb_publishable_test", headers["apikey"])
        assertEquals("application/json", headers["content-type"])
        assertEquals("boostnetwork-android/1.2.3", headers["x-client-info"])
        val json = JSONObject(body)
        assertEquals(
            setOf("p_app_key", "p_installation_id", "p_lang", "p_os", "p_recent", "p_impressions"),
            json.keys().asSequence().toSet()
        )
        assertEquals("bya_key", json.getString("p_app_key"))
        assertEquals("inst-1", json.getString("p_installation_id"))
        assertEquals("fr-FR", json.getString("p_lang"))
        assertEquals("Android 14", json.getString("p_os"))
        assertEquals("ad-9", json.getJSONArray("p_recent").getString(0))
        assertEquals(2, json.getJSONArray("p_impressions").length())

        assertEquals(2, response.ads.size)
        assertEquals(Ad("ad-1", "Mon App", listOf("Un", "Deux"), "fr", "https://icon", 4.5, "Gratuit", 4, "tok-1"), response.ads[0])
        assertNull(response.ads[1].iconUrl)
        assertNull(response.ads[1].rating)
        assertEquals(30, response.ads[1].rotationSeconds) // borné
        assertEquals(60, response.refreshSeconds)
        assertEquals(2, response.accepted)
        assertEquals(1, response.rejected)
    }

    @Test
    fun `network_next envoie le nombre de pubs voulues et les versions en cache`() {
        nextBody = """{"ads":[],"refreshSeconds":60,"accepted":0,"rejected":0}"""
        val device = DeviceInfo("fr-FR", "Android 14")
        client().next(NextRequest("k", "i", device, emptyList(), listOf("t1"), count = 0))
        client().next(NextRequest("k", "i", device, emptyList(), emptyList(), cached = listOf("v1", "v2")))
        val (reportOnly, withCache) = requests.map { JSONObject(it.third) }
        assertEquals(0, reportOnly.getInt("p_count"))
        assertFalse(reportOnly.has("p_cached"))
        assertFalse(withCache.has("p_count"))
        assertEquals(listOf("v1", "v2"), withCache.getJSONArray("p_cached").let { a -> (0 until a.length()).map(a::getString) })
    }

    @Test
    fun `une pub sans contenu est reprise du cache ou ignorée si absente`() {
        val body = """
            {"ads":[{"id":"a","version":"v1","token":"tok-a"},{"id":"b","version":"v9","token":"tok-b"},
              {"id":"c","name":"C","descriptions":["x"],"languageCode":"en","iconUrl":null,"rating":null,
              "cta":"Free","rotationSeconds":30,"version":"v3","token":"tok-c"}],
             "refreshSeconds":60,"accepted":0,"rejected":0}
        """.trimIndent()
        val cachedA = Ad("a", "A", listOf("y"), "fr", "https://i", 4.0, "Gratuit", 15, "", "v1")
        val response = ApiJson.parseNext(body) { id, version -> cachedA.takeIf { id == "a" && version == "v1" } }
        assertEquals(listOf("a", "c"), response.ads.map { it.id })
        assertEquals(cachedA.copy(token = "tok-a"), response.ads[0])
        assertEquals("v3", response.ads[1].version)
        assertEquals("tok-c", response.ads[1].token)
    }

    @Test
    fun `rendu de l'app et captures, gardées par le cache`() {
        val body = """
            {"ads":[{"id":"a","name":"A","descriptions":["x"],"languageCode":"en","iconUrl":null,"rating":null,
              "cta":"Free","rotationSeconds":30,"version":"v1","token":"tok-a",
              "screenshots":["https://s.test/1.png","javascript:alert(1)","https://s.test/2.png","https://s.test/3.png","https://s.test/4.png"]},
             {"id":"b","name":"B","descriptions":["y"],"languageCode":"en","iconUrl":null,"rating":null,
              "cta":"Free","rotationSeconds":30,"token":"tok-b"}],
             "look":{"style":"dynamic","colors":{"background":"#0369A1","background2":"#4F46E5","title":"#FFFFFF","button":"blanc"},
                     "pattern":"grid","font":"serif"},
             "refreshSeconds":60,"accepted":0,"rejected":0}
        """.trimIndent()
        val response = ApiJson.parseNext(body)
        val (withShots, plain) = response.ads
        // 3 captures au plus, adresses http(s) seulement
        assertEquals(listOf("https://s.test/1.png", "https://s.test/2.png", "https://s.test/3.png"), withShots.screenshots)
        assertEquals(emptyList<String>(), plain.screenshots)
        assertEquals(withShots.copy(token = ""), ApiJson.parseContent(ApiJson.contentJson(withShots)))
        // Rendu de l'app : couleur mal formée ignorée (celle du style par défaut), gardé tel quel
        val look = response.look!!
        assertEquals("dynamic", look.style)
        assertEquals(mapOf("background" to "#0369A1", "background2" to "#4F46E5", "title" to "#FFFFFF"), look.colors)
        assertEquals("grid", look.pattern)
        assertEquals("serif", look.font)
        assertEquals(look, ApiJson.parseLook(ApiJson.lookJson(look)))
        // Serveur ancien : pas de rendu
        assertNull(ApiJson.parseNext("""{"ads":[],"refreshSeconds":60,"accepted":0,"rejected":0}""").look)
    }

    @Test
    fun `network_next envoie le style et la palette demandés`() {
        val request = NextRequest("k", "i", DeviceInfo("en", "Android 14"), emptyList(), emptyList(), style = "dynamic", palette = "neon")
        val body = JSONObject(ApiJson.nextRequest(request))
        assertEquals("dynamic", body.getString("p_style"))
        assertEquals("neon", body.getString("p_palette"))
        // Sans setStyle : rien d'envoyé, le serveur prend le standard
        assertFalse(JSONObject(ApiJson.nextRequest(request.copy(style = null, palette = null))).has("p_style"))
    }

    @Test
    fun `interstitiel demandé et réglages lus`() {
        val request = NextRequest("k", "i", DeviceInfo("en", "Android 14"), emptyList(), emptyList(), count = 1, format = "interstitial")
        assertEquals("interstitial", JSONObject(ApiJson.nextRequest(request)).getString("p_format"))
        assertFalse(JSONObject(ApiJson.nextRequest(request.copy(format = null))).has("p_format"))

        val body = """{"ads":[{"id":"a","name":"A","descriptions":["Une *longue* histoire"],"cta":"Get","token":"t.i.s"}],
            "refreshSeconds":60,"accepted":0,"rejected":0,"interstitial":{"closeSeconds":3,"intervalSeconds":99999}}"""
        val response = ApiJson.parseNext(body)
        assertEquals(InterstitialConfig(closeSeconds = 3, intervalSeconds = 3600), response.interstitial)
        assertEquals("t.i.s", response.ads.single().token)
        assertNull(ApiJson.parseNext("""{"ads":[],"refreshSeconds":60,"accepted":0,"rejected":0}""").interstitial)
        assertEquals(InterstitialConfig(3, 120), ApiJson.parseInterstitial(ApiJson.interstitialJson(InterstitialConfig(3, 120))))
    }

    @Test
    fun `network_click renvoie l'URL du store`() {
        nextBody = """{"url":"https://play.google.com/store/apps/details?id=com.example"}"""
        assertEquals("https://play.google.com/store/apps/details?id=com.example", client().click("tok"))
        assertEquals("/rest/v1/rpc/network_click", requests.single().first)
        assertEquals("""{"p_token":"tok"}""", requests.single().third)
    }

    @Test
    fun `network_click envoie la langue et le système`() {
        nextBody = """{"url":"https://play.google.com/store/apps/details?id=com.example"}"""
        client().click("tok", DeviceInfo("fr-FR", "Android 14"))
        val body = JSONObject(requests.single().third)
        assertEquals("tok", body.getString("p_token"))
        assertEquals("fr-FR", body.getString("p_lang"))
        assertEquals("Android 14", body.getString("p_os"))
    }

    @Test
    fun `les erreurs PostgREST donnent le code du serveur`() {
        nextStatus = 400
        nextBody = """{"code":"P0001","details":null,"hint":null,"message":"unknown_app"}"""
        assertApiError("unknown_app") { client().next(NextRequest("x", "y", DeviceInfo("en", "Android 14"), emptyList(), emptyList())) }

        nextStatus = 401
        nextBody = "pas du json"
        assertApiError("http_401") { client().click("tok") }
    }

    @Test
    fun `serveur injoignable`() {
        val unreachable = ApiClient("http://127.0.0.1:1", "key", "1")
        assertApiError("network") { unreachable.click("tok") }
    }

    @Test
    fun `réponse sans pub`() {
        val response = ApiJson.parseNext("""{"ads":[],"refreshSeconds":5,"accepted":0,"rejected":0}""")
        assertTrue(response.ads.isEmpty())
        assertEquals(15, response.refreshSeconds) // borné
    }

    private fun assertApiError(code: String, block: () -> Unit) {
        try {
            block()
            fail("ApiException attendue")
        } catch (e: ApiException) {
            assertEquals(code, e.code)
        }
    }
}

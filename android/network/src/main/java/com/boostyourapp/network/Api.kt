package com.boostyourapp.network

import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** Une pub renvoyée par network_next. */
internal data class Ad(
    val id: String,
    val name: String,
    val descriptions: List<String>,
    val languageCode: String,
    val iconUrl: String?,
    val rating: Double?,
    val cta: String,
    val rotationSeconds: Int,
    /** Jeton d'impression : renvoyé au serveur si la pub a été réellement visible */
    val token: String,
    /** Empreinte du contenu, pour le cache ([CreativeCache]) ; null avec un serveur ancien */
    val version: String? = null,
    /** Style dynamique : captures de l'app en éventail (3 au plus) */
    val screenshots: List<String> = emptyList()
)

/**
 * Rendu de toutes les pubs de l'app hôte, choisi par le développeur ([BoostNetwork.setStyle]) et résolu par le
 * serveur : style (standard ou dynamic, inconnu : standard), couleurs de la palette (#RRGGBB : background,
 * background2, border, patternColor, title, text, button, buttonText ; absente : celle du style par défaut),
 * motif du fond (stripes, grid, dots) et police de l'accroche (serif, rounded) du style dynamique.
 * En style dynamique, un mot entre étoiles dans une accroche est surligné ([Hooks]).
 */
internal data class Look(
    val style: String = "standard",
    val colors: Map<String, String> = emptyMap(),
    val pattern: String? = null,
    val font: String? = null
)

internal data class NextRequest(
    val appKey: String,
    val installationId: String,
    val device: DeviceInfo,
    val recent: List<String>,
    val impressions: List<String>,
    /** Nombre de pubs voulues : null = valeur du serveur, 0 = seulement envoyer les affichages */
    val count: Int? = null,
    /** Versions des pubs en cache : le serveur n'en renvoie pas le contenu */
    val cached: List<String>? = null,
    /** Rendu choisi par l'app ([BoostNetwork.setStyle]) : style et clé de palette ; null = valeurs du serveur */
    val style: String? = null,
    val palette: String? = null,
    /** "interstitial" : une pub plein écran (descriptions longues, jeton d'interstitiel) ; null = bannières */
    val format: String? = null
)

/**
 * Envoyé avec chaque appel. La langue choisit celle des textes des pubs ; avec la version majeure du système
 * (« Android 14 »), elle alimente les statistiques d'audience de l'annonceur (compteurs agrégés côté serveur).
 * Rien d'autre sur l'appareil : ni pays, ni marque, ni modèle.
 */
internal data class DeviceInfo(
    val lang: String,
    val os: String
)

internal data class NextResponse(
    val ads: List<Ad>,
    /** Rendu à appliquer ; null avec un serveur ancien */
    val look: Look? = null,
    val refreshSeconds: Int,
    val accepted: Int,
    val rejected: Int,
    /** Réglages des interstitiels, renvoyés avec une demande d'interstitiel */
    val interstitial: InterstitialConfig? = null
)

/** Bouton de fermeture au bout de [closeSeconds] ; au moins [intervalSeconds] entre deux interstitiels. */
internal data class InterstitialConfig(
    val closeSeconds: Int = 5,
    val intervalSeconds: Int = 180
)

/** Erreur d'appel : code renvoyé par le serveur (`unknown_app`, `suspended`...) ou `network`. */
internal class ApiException(val code: String, val status: Int, cause: Throwable? = null) : Exception(code, cause)

/** Sérialisation, isolée pour être testée sur la JVM. Contrat : docs/network-sdk-api.md. */
internal object ApiJson {
    fun nextRequest(request: NextRequest): String = JSONObject()
        .put("p_app_key", request.appKey)
        .put("p_installation_id", request.installationId)
        .put("p_recent", JSONArray(request.recent))
        .put("p_impressions", JSONArray(request.impressions))
        .putDevice(request.device)
        .apply {
            request.count?.let { put("p_count", it) }
            request.cached?.let { put("p_cached", JSONArray(it)) }
            request.style?.let { put("p_style", it) }
            request.palette?.let { put("p_palette", it) }
            request.format?.let { put("p_format", it) }
        }
        .toString()

    fun clickRequest(token: String, device: DeviceInfo? = null): String {
        val json = JSONObject().put("p_token", token)
        if (device != null) json.putDevice(device)
        return json.toString()
    }

    private fun JSONObject.putDevice(device: DeviceInfo): JSONObject = this
        .put("p_lang", device.lang)
        .put("p_os", device.os)

    /**
     * [cached] retrouve le contenu d'une pub que le serveur n'a pas renvoyé (déjà en cache sur l'appareil) ;
     * une pub introuvable est ignorée.
     */
    fun parseNext(body: String, cached: (id: String, version: String) -> Ad? = { _, _ -> null }): NextResponse {
        val json = JSONObject(body)
        val ads = json.optJSONArray("ads") ?: JSONArray()
        return NextResponse(
            ads = (0 until ads.length()).mapNotNull { parseAd(ads.getJSONObject(it), cached) },
            look = json.optJSONObject("look")?.let(::parseLook),
            refreshSeconds = json.optInt("refreshSeconds", 60).coerceIn(15, 600),
            accepted = json.optInt("accepted", 0),
            rejected = json.optInt("rejected", 0),
            interstitial = json.optJSONObject("interstitial")?.let(::parseInterstitial)
        )
    }

    fun parseInterstitial(json: JSONObject): InterstitialConfig = InterstitialConfig(
        closeSeconds = json.optInt("closeSeconds", 5).coerceIn(0, 15),
        intervalSeconds = json.optInt("intervalSeconds", 180).coerceIn(30, 3600)
    )

    fun interstitialJson(config: InterstitialConfig): JSONObject = JSONObject()
        .put("closeSeconds", config.closeSeconds)
        .put("intervalSeconds", config.intervalSeconds)

    fun parseClick(body: String): String = JSONObject(body).getString("url")

    /** Message d'une erreur PostgREST : { "code": "P0001", "message": "unknown_app" } */
    fun parseErrorMessage(body: String): String? = try {
        JSONObject(body).optString("message").takeIf { it.isNotEmpty() }
    } catch (e: Exception) {
        null
    }

    private fun parseAd(json: JSONObject, cached: (String, String) -> Ad?): Ad? {
        val token = json.stringOrNull("token") ?: return null
        if (!json.has("name")) {
            // Contenu omis : l'appareil l'a déjà
            val id = json.stringOrNull("id") ?: return null
            val version = json.stringOrNull("version") ?: return null
            return cached(id, version)?.copy(token = token)
        }
        return parseContent(json)?.copy(token = token)
    }

    /** Contenu d'une pub, sans jeton (réponse du serveur ou cache). */
    fun parseContent(json: JSONObject): Ad? {
        val id = json.stringOrNull("id") ?: return null
        val descriptions = json.optJSONArray("descriptions") ?: JSONArray()
        return Ad(
            id = id,
            name = json.stringOrNull("name") ?: "",
            descriptions = (0 until descriptions.length()).map { descriptions.getString(it) },
            languageCode = json.stringOrNull("languageCode") ?: "en",
            iconUrl = json.stringOrNull("iconUrl"),
            rating = if (json.isNull("rating")) null else json.optDouble("rating"),
            cta = json.stringOrNull("cta") ?: "Install",
            rotationSeconds = json.optInt("rotationSeconds", 4).coerceIn(2, 30),
            token = "",
            version = json.stringOrNull("version"),
            screenshots = parseUrls(json.optJSONArray("screenshots")).take(3)
        )
    }

    fun parseLook(json: JSONObject): Look = Look(
        style = json.stringOrNull("style") ?: "standard",
        colors = parseColors(json.optJSONObject("colors")),
        pattern = json.stringOrNull("pattern"),
        font = json.stringOrNull("font")
    )

    fun lookJson(look: Look): JSONObject = JSONObject()
        .put("style", look.style)
        .put("colors", JSONObject(look.colors as Map<*, *>))
        .put("pattern", look.pattern ?: JSONObject.NULL)
        .put("font", look.font ?: JSONObject.NULL)

    /** Couleurs #RRGGBB seulement : une valeur mal formée est ignorée (couleur par défaut du style). */
    private fun parseColors(json: JSONObject?): Map<String, String> {
        if (json == null) return emptyMap()
        val colors = LinkedHashMap<String, String>()
        for (key in json.keys()) {
            val value = json.optString(key)
            if (COLOR_PATTERN.matches(value)) colors[key] = value
        }
        return colors
    }

    private val COLOR_PATTERN = Regex("^#[0-9A-Fa-f]{6}$")

    /** Adresses http(s) seulement */
    private fun parseUrls(json: JSONArray?): List<String> {
        if (json == null) return emptyList()
        return (0 until json.length()).mapNotNull { i ->
            json.optString(i).takeIf { it.startsWith("https://") || it.startsWith("http://") }
        }
    }

    fun contentJson(ad: Ad): JSONObject = JSONObject()
        .put("id", ad.id)
        .put("name", ad.name)
        .put("descriptions", JSONArray(ad.descriptions))
        .put("languageCode", ad.languageCode)
        .put("iconUrl", ad.iconUrl ?: JSONObject.NULL)
        .put("rating", ad.rating ?: JSONObject.NULL)
        .put("cta", ad.cta)
        .put("rotationSeconds", ad.rotationSeconds)
        .put("version", ad.version ?: JSONObject.NULL)
        .put("screenshots", JSONArray(ad.screenshots))

    private fun JSONObject.stringOrNull(key: String): String? = if (isNull(key)) null else optString(key)
}

/** Appels des fonctions du réseau via l'API REST de Supabase (POST /rest/v1/rpc/<fonction>). */
internal class ApiClient(
    private val baseUrl: String,
    private val apiKey: String,
    private val sdkVersion: String
) {
    fun next(request: NextRequest, cached: (String, String) -> Ad? = { _, _ -> null }): NextResponse =
        ApiJson.parseNext(post("network_next", ApiJson.nextRequest(request)), cached)

    fun click(token: String, device: DeviceInfo? = null): String =
        ApiJson.parseClick(post("network_click", ApiJson.clickRequest(token, device)))

    private fun post(function: String, body: String): String {
        val connection = try {
            URL("${baseUrl.trimEnd('/')}/rest/v1/rpc/$function").openConnection() as HttpURLConnection
        } catch (e: IOException) {
            throw ApiException("network", 0, e)
        }
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 10_000
            connection.readTimeout = 15_000
            connection.doOutput = true
            connection.setRequestProperty("apikey", apiKey)
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("X-Client-Info", "boostnetwork-android/$sdkVersion")
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
            if (status !in 200..299) {
                throw ApiException(ApiJson.parseErrorMessage(text) ?: "http_$status", status)
            }
            return text
        } catch (e: IOException) {
            throw ApiException("network", 0, e)
        } finally {
            connection.disconnect()
        }
    }
}

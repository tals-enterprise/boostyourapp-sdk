package com.boostyourapp.network

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.util.LruCache
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Chargement des icônes, sans dépendance : HttpURLConnection et petit cache mémoire. */
internal class IconLoader(
    private val executor: ExecutorService = Executors.newFixedThreadPool(2),
    private val main: Handler = Handler(Looper.getMainLooper())
) {
    private val cache = LruCache<String, Bitmap>(20)

    /** [onLoaded] est appelé sur le thread principal, avec null en cas d'échec. */
    fun load(url: String, sizePx: Int, onLoaded: (Bitmap?) -> Unit) {
        cache.get(url)?.let {
            onLoaded(it)
            return
        }
        executor.execute {
            val bitmap = try {
                download(url, sizePx)
            } catch (e: Exception) {
                null
            }
            if (bitmap != null) cache.put(url, bitmap)
            main.post { onLoaded(bitmap) }
        }
    }

    private fun download(url: String, sizePx: Int): Bitmap? {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 10_000
            connection.readTimeout = 15_000
            if (connection.responseCode !in 200..299) return null
            val bytes = connection.inputStream.use { it.readBytes() }
            // Réduit les grandes icônes (512 px sur les stores) à la taille affichée
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= sizePx && bounds.outHeight / (sample * 2) >= sizePx) sample *= 2
            return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
        } finally {
            connection.disconnect()
        }
    }
}

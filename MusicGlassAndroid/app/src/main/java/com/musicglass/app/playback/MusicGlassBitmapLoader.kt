package com.musicglass.app.playback

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.media3.common.util.BitmapLoader
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.net.URL

class MusicGlassBitmapLoader(
    context: Context,
    private val scope: CoroutineScope
) : BitmapLoader {
    private val appContext = context.applicationContext

    override fun decodeBitmap(data: ByteArray): ListenableFuture<Bitmap> {
        val future = SettableFuture.create<Bitmap>()
        scope.launch(Dispatchers.IO) {
            runCatching {
                BitmapFactory.decodeByteArray(data, 0, data.size) ?: fallbackBitmap()
            }.onSuccess(future::set)
                .onFailure { future.set(fallbackBitmap()) }
        }
        return future
    }

    override fun loadBitmap(
        uri: Uri,
        options: BitmapFactory.Options?
    ): ListenableFuture<Bitmap> {
        val future = SettableFuture.create<Bitmap>()
        scope.launch(Dispatchers.IO) {
            runCatching {
                when (uri.scheme) {
                    "content", "file", "android.resource" -> {
                        appContext.contentResolver.openInputStream(uri)?.use { input ->
                            BitmapFactory.decodeStream(input, null, options)
                        }
                    }
                    else -> {
                        URL(uri.toString()).openConnection().apply {
                            connectTimeout = 10_000
                            readTimeout = 15_000
                        }.getInputStream().use { input ->
                            BitmapFactory.decodeStream(input, null, options)
                        }
                    }
                } ?: fallbackBitmap()
            }.onSuccess(future::set)
                .onFailure { future.set(fallbackBitmap()) }
        }
        return future
    }

    private fun fallbackBitmap(): Bitmap =
        Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
}

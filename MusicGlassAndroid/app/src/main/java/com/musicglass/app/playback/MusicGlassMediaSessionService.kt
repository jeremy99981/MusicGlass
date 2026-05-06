package com.musicglass.app.playback

import android.app.ForegroundServiceStartNotAllowedException
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.pm.ServiceInfo
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaController
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaNotification
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionToken
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import com.musicglass.app.MainActivity
import com.musicglass.app.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

@UnstableApi
class MusicGlassMediaSessionService : MediaSessionService() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var mediaSession: MediaSession? = null
    private var latestMediaNotification: Notification? = null
    private var mediaControllerFuture: ListenableFuture<MediaController>? = null

    override fun onCreate() {
        super.onCreate()
        setListener(
            object : Listener {
                override fun onForegroundServiceStartNotAllowedException() {
                    stopSelf()
                }
            }
        )

        if (!ensureStartedAsForegroundOrStop()) return

        val defaultProvider = DefaultMediaNotificationProvider(
            this,
            { NOTIFICATION_ID },
            CHANNEL_ID,
            R.string.app_name
        ).apply {
            setSmallIcon(R.mipmap.ic_launcher)
        }

        setMediaNotificationProvider(
            object : MediaNotification.Provider {
                override fun createNotification(
                    mediaSession: MediaSession,
                    mediaButtonPreferences: ImmutableList<CommandButton>,
                    actionFactory: MediaNotification.ActionFactory,
                    onNotificationChangedCallback: MediaNotification.Provider.Callback
                ): MediaNotification {
                    val trackingCallback = MediaNotification.Provider.Callback { notification ->
                        latestMediaNotification = notification.notification
                        Handler(Looper.getMainLooper()).post {
                            runCatching {
                                startForegroundSafely(notification.notification)
                                NotificationManagerCompat
                                    .from(this@MusicGlassMediaSessionService)
                                    .notify(notification.notificationId, notification.notification)
                            }
                        }
                        onNotificationChangedCallback.onNotificationChanged(notification)
                    }

                    return defaultProvider.createNotification(
                        mediaSession,
                        mediaButtonPreferences,
                        actionFactory,
                        trackingCallback
                    ).also { mediaNotification ->
                        latestMediaNotification = mediaNotification.notification
                        Handler(Looper.getMainLooper()).post {
                            runCatching {
                                startForegroundSafely(mediaNotification.notification)
                                NotificationManagerCompat
                                    .from(this@MusicGlassMediaSessionService)
                                    .notify(mediaNotification.notificationId, mediaNotification.notification)
                            }
                        }
                    }
                }

                override fun handleCustomCommand(
                    session: MediaSession,
                    action: String,
                    extras: Bundle
                ): Boolean = defaultProvider.handleCustomCommand(session, action, extras)
            }
        )

        val controller = MusicGlassPlaybackController.get(applicationContext)
        val notificationPlayer = MusicGlassNotificationPlayer(controller)
        val sessionActivity = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        mediaSession = MediaSession.Builder(this, notificationPlayer)
            .setSessionActivity(sessionActivity)
            .setBitmapLoader(MusicGlassBitmapLoader(this, serviceScope))
            .build()

        keepControllerConnectedForSystemMediaControls()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }

    override fun onDestroy() {
        mediaControllerFuture?.let(MediaController::releaseFuture)
        mediaControllerFuture = null
        mediaSession?.release()
        mediaSession = null
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun keepControllerConnectedForSystemMediaControls() {
        val sessionToken = SessionToken(
            this,
            ComponentName(this, MusicGlassMediaSessionService::class.java)
        )
        mediaControllerFuture = MediaController.Builder(this, sessionToken)
            .buildAsync()
            .also { future ->
                future.addListener(
                    { runCatching { future.get() } },
                    MoreExecutors.directExecutor()
                )
            }
    }

    private fun ensureStartedAsForegroundOrStop(): Boolean {
        return startForegroundSafely(createFallbackForegroundNotification())
    }

    private fun ensureForegroundChannelExists() {
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager?.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.app_name),
                NotificationManager.IMPORTANCE_LOW
            )
        )
    }

    private fun createFallbackForegroundNotification(): Notification {
        ensureForegroundChannelExists()
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText("Lecture en cours")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun startForegroundSafely(notification: Notification): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            true
        } catch (_: ForegroundServiceStartNotAllowedException) {
            stopSelf()
            false
        } catch (_: Exception) {
            stopSelf()
            false
        }
    }

    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "musicglass_playback"

        fun start(context: Context) {
            ContextCompat.startForegroundService(
                context.applicationContext,
                Intent(context.applicationContext, MusicGlassMediaSessionService::class.java)
            )
        }
    }
}

private class MusicGlassNotificationPlayer(
    private val controller: MusicGlassPlaybackController
) : ForwardingPlayer(controller.exoPlayer) {
    override fun getAvailableCommands(): Player.Commands {
        return super.getAvailableCommands()
            .buildUpon()
            .add(Player.COMMAND_PLAY_PAUSE)
            .add(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM)
            .add(Player.COMMAND_SEEK_TO_PREVIOUS)
            .add(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
            .add(Player.COMMAND_SEEK_TO_NEXT)
            .add(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
            .add(Player.COMMAND_GET_CURRENT_MEDIA_ITEM)
            .add(Player.COMMAND_GET_METADATA)
            .add(Player.COMMAND_GET_TIMELINE)
            .build()
    }

    override fun hasNextMediaItem(): Boolean = controller.canSkipNext.value

    override fun hasPreviousMediaItem(): Boolean = controller.canSkipPrevious.value

    override fun seekToNext() {
        controller.next()
    }

    override fun seekToNextMediaItem() {
        controller.next()
    }

    override fun seekToPrevious() {
        controller.previous()
    }

    override fun seekToPreviousMediaItem() {
        controller.previous()
    }
}

package org.moonfin.androidtv

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/// Keeps a Ma TV channel or an IPTV film playing with the screen off or the
/// app in the background (VJOD 4.17): a media-playback foreground service
/// with its notification (Pause / Lecture, Arrêter), a partial wake lock so
/// the CPU keeps decoding, and a Wi-Fi lock so the stream keeps coming.
///
/// It runs while a VJOD player is open on a phone or tablet; the player
/// starts it in the foreground (Android forbids starting it from the
/// background) and stops it when it closes.
class VjodPlaybackService : Service() {
    companion object {
        const val ACTION_START = "org.moonfin.vjod.playback.START"
        const val ACTION_STOP = "org.moonfin.vjod.playback.STOP"
        const val ACTION_COMMAND = "org.moonfin.vjod.playback.COMMAND"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_PLAYING = "playing"
        const val EXTRA_COMMAND = "command"
        private const val CHANNEL_ID = "vjod_playback"
        private const val NOTIFICATION_ID = 7417

        /// The notification's buttons, handed to the open player.
        @Volatile
        var onCommand: ((String) -> Unit)? = null

        fun start(context: Context, title: String, text: String, playing: Boolean) {
            val intent = Intent(context, VjodPlaybackService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
                .putExtra(EXTRA_PLAYING, playing)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            // stopService works from the background too (startService may not).
            context.stopService(Intent(context, VjodPlaybackService::class.java))
        }
    }

    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null
    private var title = "VJOD"
    private var text = ""
    private var playing = true

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                title = intent.getStringExtra(EXTRA_TITLE) ?: title
                text = intent.getStringExtra(EXTRA_TEXT) ?: ""
                playing = intent.getBooleanExtra(EXTRA_PLAYING, true)
                show()
                hold()
            }
            ACTION_COMMAND -> {
                val cmd = intent.getStringExtra(EXTRA_COMMAND) ?: return START_NOT_STICKY
                onCommand?.invoke(cmd)
                if (cmd == "stop") finish()
            }
            ACTION_STOP -> finish()
            else -> finish()
        }
        return START_NOT_STICKY
    }

    @Suppress("DEPRECATION")
    private fun show() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Lecture VJOD", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "La chaîne ou le film en cours, écran éteint ou appli réduite"
                    setShowBadge(false)
                },
            )
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            flags,
        )
        fun command(name: String, code: Int) = PendingIntent.getService(
            this, code,
            Intent(this, VjodPlaybackService::class.java).setAction(ACTION_COMMAND).putExtra(EXTRA_COMMAND, name),
            flags,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
        builder.addAction(
            Notification.Action.Builder(
                0,
                if (playing) "Pause" else "Lecture",
                command("playPause", 1),
            ).build(),
        )
        builder.addAction(Notification.Action.Builder(0, "Arrêter", command("stop", 2)).build())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setStyle(Notification.MediaStyle().setShowActionsInCompactView(0, 1))
        }
        val notification = builder.build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    @Suppress("DEPRECATION")
    private fun hold() {
        if (wake == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "vjod:playback").apply {
                setReferenceCounted(false)
                acquire(6 * 60 * 60 * 1000L)
            }
        }
        if (wifi == null) {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            } else {
                WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            wifi = wm.createWifiLock(mode, "vjod:playback").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun finish() {
        try {
            wake?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        try {
            wifi?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wake = null
        wifi = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        try {
            wake?.let { if (it.isHeld) it.release() }
            wifi?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        super.onDestroy()
    }
}

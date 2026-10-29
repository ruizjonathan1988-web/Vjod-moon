package org.moonfin.androidtv

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

/// Installs an update APK the app downloaded itself, through the system
/// installer, so a TV with no browser can update without Downloader.
object PersoApkInstaller {
    const val CHANNEL = "org.moonfin.androidtv/perso_update"
    private const val ACTION_STATUS = "org.moonfin.androidtv.PERSO_APK_STATUS"

    fun install(activity: Activity, path: String, result: MethodChannel.Result) {
        thread(name = "moonfin-apk-install") {
            try {
                val installer = activity.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(
                    PackageInstaller.SessionParams.MODE_FULL_INSTALL,
                )
                // Android 12+ lets an app update itself without asking once it is
                // the one that installed itself; elsewhere the system asks as before.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    params.setRequireUserAction(
                        PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED,
                    )
                }
                val sessionId = installer.createSession(params)
                val session = installer.openSession(sessionId)
                try {
                    File(path).inputStream().use { input ->
                        session.openWrite("vjod.apk", 0, -1).use { output ->
                            input.copyTo(output)
                            session.fsync(output)
                        }
                    }
                    val status = Intent(activity, activity.javaClass)
                        .setAction(ACTION_STATUS)
                    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }
                    val pending = PendingIntent.getActivity(activity, sessionId, status, flags)
                    session.commit(pending.intentSender)
                } finally {
                    session.close()
                }
                activity.runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("install_failed", e.message, null) }
            }
        }
    }

    /// When this copy was last installed or updated, in milliseconds.
    fun lastUpdateTime(activity: Activity): Long = try {
        @Suppress("DEPRECATION")
        activity.packageManager.getPackageInfo(activity.packageName, 0).lastUpdateTime
    } catch (e: Exception) {
        0L
    }

    /// The installer's answer comes back as an intent to the activity. When it
    /// needs the user to confirm, it carries the screen to show.
    fun handle(activity: Activity, intent: Intent?): Boolean {
        if (intent?.action != ACTION_STATUS) return false
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val confirm: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_INTENT)
            }
            if (confirm != null) {
                confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    activity.startActivity(confirm)
                } catch (e: Exception) {
                }
            }
        }
        return true
    }
}

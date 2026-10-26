package org.moonfin.androidtv

import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Opens an external IPTV player (TiviMate and the like) from VJOD's TV tab:
/// says whether one is installed, launches it, or sends the viewer to the
/// store to get it. VJOD never configures the other app; it only brings the
/// viewer to it.
object TvAppLauncher {
    const val CHANNEL = "org.moonfin.vjod/tv_launcher"

    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isInstalled" -> {
                val pkg = call.argument<String>("package")
                if (pkg == null) {
                    result.error("no_package", "package missing", null)
                } else {
                    result.success(launchIntentFor(context, pkg) != null)
                }
            }
            "launch" -> {
                val pkg = call.argument<String>("package")
                val intent = pkg?.let { launchIntentFor(context, it) }
                if (intent == null) {
                    result.success(false)
                } else {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
            }
            "openStore" -> {
                val pkg = call.argument<String>("package")
                if (pkg == null) {
                    result.error("no_package", "package missing", null)
                } else {
                    result.success(openStore(context, pkg))
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun launchIntentFor(context: Context, pkg: String): Intent? {
        val pm = context.packageManager
        // The TV launcher entry first (Android TV), the phone one otherwise.
        return pm.getLeanbackLaunchIntentForPackage(pkg)
            ?: pm.getLaunchIntentForPackage(pkg)
    }

    /// Tries, in order, the Play Store app, the Amazon Appstore (Fire TV),
    /// then the Play Store web page, so a store opens on whatever the box has.
    private fun openStore(context: Context, pkg: String): Boolean {
        val targets = listOf(
            Uri.parse("market://details?id=$pkg"),
            Uri.parse("amzn://apps/android?p=$pkg"),
            Uri.parse("https://play.google.com/store/apps/details?id=$pkg"),
        )
        for (uri in targets) {
            val intent = Intent(Intent.ACTION_VIEW, uri)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return true
            } catch (_: Exception) {
                // Try the next store.
            }
        }
        return false
    }
}

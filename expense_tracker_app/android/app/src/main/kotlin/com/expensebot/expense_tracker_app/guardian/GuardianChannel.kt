package com.expensebot.expense_tracker_app.guardian

import android.app.Activity
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate

/**
 * Flutter ↔ native bridge for the Guardian screen. The UI uses it to read
 * status and change settings; the service never depends on it, so
 * monitoring keeps working with no Flutter engine alive.
 */
class GuardianChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val store = GuardianStore(activity)
    private var preview: GuardianOverlay? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    /** Removes the preview card when the activity goes away. */
    fun dispose() {
        preview?.hide()
        preview = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getState" -> result.success(state())
            "updateSettings" -> {
                store.updateSettings(call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                // Thresholds affect which notifications are due.
                GuardianNotifications.onSnapshotUpdated(activity, store)
                result.success(state())
            }
            "pushSnapshot" -> {
                val ok = (call.arguments as? String)?.let(store::saveSnapshot) ?: false
                if (ok) GuardianNotifications.onSnapshotUpdated(activity, store)
                result.success(ok)
            }
            "setEnabled" -> result.success(setEnabled(call.arguments == true))
            "openSettings" -> result.success(openSettings(call.arguments as? String))
            "resetStats" -> {
                store.resetStats()
                result.success(state())
            }
            "previewOverlay" -> result.success(previewOverlay())
            else -> result.notImplemented()
        }
    }

    private fun setEnabled(enabled: Boolean): String {
        if (!enabled) {
            store.setEnabled(false)
            GuardianService.stop(activity)
            return "ok"
        }
        if (!GuardianService.hasUsageAccess(activity)) return "usageAccess"
        if (!GuardianService.canDrawOverlays(activity)) return "overlay"
        store.setEnabled(true)
        if (!GuardianService.start(activity)) {
            store.setEnabled(false)
            return "startFailed"
        }
        return "ok"
    }

    private fun state(): Map<String, Any?> {
        val pm = activity.packageManager
        val power = activity.getSystemService(PowerManager::class.java)
        return mapOf(
            "settings" to store.settingsMap(),
            "running" to GuardianService.running,
            "permissions" to mapOf(
                "usageAccess" to GuardianService.hasUsageAccess(activity),
                "overlay" to GuardianService.canDrawOverlays(activity),
                "notifications" to activity.getSystemService(NotificationManager::class.java).areNotificationsEnabled(),
                "batteryUnrestricted" to power.isIgnoringBatteryOptimizations(activity.packageName),
            ),
            "installed" to GuardianApps.SUPPORTED.keys.associateWith { pkg ->
                try {
                    @Suppress("DEPRECATION")
                    pm.getPackageInfo(pkg, 0)
                    true
                } catch (e: PackageManager.NameNotFoundException) {
                    false
                }
            },
            "stats" to store.stats(),
            "snapshotAt" to store.snapshot()?.computedAt,
            "sdkInt" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
        )
    }

    private fun openSettings(kind: String?): Boolean {
        val pkgUri = Uri.parse("package:${activity.packageName}")
        val details = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkgUri)
        val attempts = when (kind) {
            // Some Android versions deep-link to the app's own toggle when
            // given the package; the rest only open the list.
            "usageAccess" -> listOf(
                Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, pkgUri),
                Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS),
            )
            "overlay" -> listOf(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, pkgUri), details)
            "notifications" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                listOf(
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName),
                    details,
                )
            } else listOf(details)
            // Opens the system list; asking for an exemption directly is a
            // restricted permission on Google Play.
            "battery" -> listOf(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS), details)
            else -> listOf(details)
        }
        for (intent in attempts) {
            try {
                activity.startActivity(intent)
                return true
            } catch (e: ActivityNotFoundException) {
                continue
            } catch (e: SecurityException) {
                continue
            }
        }
        return false
    }

    /** Shows the real card over Spendo itself, with the current figures. */
    private fun previewOverlay(): String {
        if (!GuardianService.canDrawOverlays(activity)) return "overlay"
        val snapshot = store.snapshot() ?: return "noData"
        val settings = store.settings()
        val a = GuardianRules.assess(snapshot, settings, LocalDate.now()) ?: return "noData"
        if (a.budget <= 0 && a.overCategories.isEmpty()) return "noBudget"
        val overlay = preview ?: GuardianOverlay(activity.applicationContext) {}.also { preview = it }
        return if (overlay.show(a, settings)) "ok" else "overlay"
    }

    companion object {
        const val CHANNEL = "spendo/guardian"
    }
}

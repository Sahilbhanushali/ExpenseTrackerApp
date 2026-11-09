package com.expensebot.expense_tracker_app.guardian

import android.app.AppOpsManager
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import android.util.Log
import com.expensebot.expense_tracker_app.MainActivity
import java.time.LocalDate

/**
 * Watches which app is in the foreground — package names only, via
 * UsageStatsManager — and shows [GuardianOverlay] when the user opens one of
 * the UPI apps they selected while a budget threshold is active.
 *
 * Android has no broadcast for "app X came to the foreground", so the event
 * log is read on a short interval, but only while the screen is on; with the
 * screen off the service does no work at all.
 */
class GuardianService : Service() {
    private lateinit var store: GuardianStore
    private lateinit var overlay: GuardianOverlay
    private lateinit var worker: HandlerThread
    private lateinit var workHandler: Handler
    private val main = Handler(Looper.getMainLooper())

    private var polling = false
    private var lastEventTs = 0L
    /** Written on the worker thread, read on the main thread. */
    @Volatile
    private var foregroundPkg: String? = null
    private var pollsSincePermissionCheck = 0
    private var paused: String? = null

    private val poll = object : Runnable {
        override fun run() {
            if (!polling) return
            val delay = try {
                tick()
            } catch (e: RuntimeException) {
                Log.w(TAG, "Poll failed: ${e.javaClass.simpleName}")
                PAUSED_INTERVAL_MS
            }
            workHandler.postDelayed(this, delay)
        }
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    stopPolling()
                    // Leaving the screen off counts as leaving the app, so the
                    // alert re-arms (subject to the cooldown) on return.
                    workHandler.post { foregroundPkg = null }
                    main.post { overlay.hide() }
                }
                Intent.ACTION_SCREEN_ON, Intent.ACTION_USER_PRESENT -> startPolling()
            }
        }
    }

    private val prefsListener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
        // Fresh figures while the card is up (e.g. an SMS import finished):
        // update the card in place rather than leaving old numbers showing.
        if (key == GuardianStore.K_SNAPSHOT || key == GuardianStore.K_CAUTION) refreshVisibleOverlay()
        if (key == GuardianStore.K_APPS) updateStatusText()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        store = GuardianStore(this)
        overlay = GuardianOverlay(this) { openApp() }
        worker = HandlerThread("SpendingGuardian").apply { start() }
        workHandler = Handler(worker.looper)
        GuardianNotifications.ensureChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            store.setEnabled(false)
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }
        // Restarted by the system after being killed, but the user has since
        // turned monitoring off: don't come back.
        if (!store.settings().enabled) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            val notification = GuardianNotifications.status(this, statusText())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    GuardianNotifications.STATUS_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(GuardianNotifications.STATUS_ID, notification)
            }
        } catch (e: Exception) {
            // Android 12+ refuses foreground starts from the background in
            // most cases (ForegroundServiceStartNotAllowedException).
            // Monitoring stays off until the user opens the app again.
            Log.w(TAG, "startForeground refused: ${e.javaClass.simpleName}")
            stopSelf()
            return START_NOT_STICKY
        }
        if (!running) {
            running = true
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_USER_PRESENT)
            }
            // System broadcasts still reach a not-exported receiver.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(screenReceiver, filter, RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(screenReceiver, filter)
            }
            store.prefs.registerOnSharedPreferenceChangeListener(prefsListener)
            if (getSystemService(PowerManager::class.java).isInteractive) startPolling()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        stopPolling()
        runCatching { unregisterReceiver(screenReceiver) }
        store.prefs.unregisterOnSharedPreferenceChangeListener(prefsListener)
        overlay.hide()
        worker.quitSafely()
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        main.post { overlay.onConfigurationChanged() }
    }

    private fun stopForegroundCompat() {
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    // Detection --------------------------------------------------------------

    private fun startPolling() {
        workHandler.post {
            if (polling) return@post
            polling = true
            // Look a little into the past so an app already open when the
            // screen came on is picked up.
            lastEventTs = System.currentTimeMillis() - LOOKBACK_MS
            workHandler.post(poll)
        }
    }

    private fun stopPolling() {
        workHandler.post {
            polling = false
            workHandler.removeCallbacks(poll)
        }
    }

    /** One poll; returns the delay until the next. Runs on the worker thread. */
    private fun tick(): Long {
        if (pollsSincePermissionCheck++ % PERMISSION_CHECK_EVERY == 0) {
            val reason = when {
                !hasUsageAccess(this) -> "Usage access was turned off, so monitoring is paused. Open Spendo to fix it."
                !canDrawOverlays(this) -> "Display over other apps was turned off, so alerts can't be shown. Open Spendo to fix it."
                else -> null
            }
            if (reason != paused) {
                paused = reason
                updateStatusText()
            }
        }
        if (paused != null) {
            main.post { overlay.hide() }
            return PAUSED_INTERVAL_MS
        }

        val now = System.currentTimeMillis()
        val usm = getSystemService(UsageStatsManager::class.java)
        val events = usm.queryEvents(lastEventTs + 1, now)
        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            lastEventTs = maxOf(lastEventTs, e.timeStamp)
            if (e.eventType == RESUMED) onResumed(e.packageName)
        }
        return POLL_INTERVAL_MS
    }

    private fun onResumed(pkg: String) {
        // System dialogs drawn over the current app (permission prompts,
        // notification shade) don't mean the user left it.
        if (pkg in TRANSIENT_PACKAGES || pkg == foregroundPkg) return
        val previous = foregroundPkg
        foregroundPkg = pkg
        val monitored = store.settings().apps
        if (previous != null && previous in monitored) main.post { overlay.hide() }
        if (pkg in monitored) onMonitoredAppOpened(pkg)
    }

    private fun onMonitoredAppOpened(pkg: String) {
        store.recordOpen(pkg)
        val settings = store.settings()
        val snapshot = store.snapshot() ?: return
        val a = GuardianRules.assess(snapshot, settings, LocalDate.now()) ?: return
        if (a.severity == Level.NONE) return

        // One alert per opening, then a cooldown across all monitored apps —
        // unless things got worse since the last alert (e.g. caution → over).
        val now = System.currentTimeMillis()
        val cooling = now - store.lastAlertAt < settings.cooldownMinutes * 60_000L
        if (cooling && a.severity.ordinal <= store.lastAlertSeverity) return

        main.post {
            // The user may have left in the meantime.
            if (foregroundPkg != pkg) return@post
            if (overlay.show(a, settings)) store.recordAlert(now, a.severity.ordinal)
        }
    }

    private fun refreshVisibleOverlay() {
        main.post {
            if (!overlay.isShowing) return@post
            val settings = store.settings()
            val a = store.snapshot()?.let { GuardianRules.assess(it, settings, LocalDate.now()) }
            if (a == null || a.severity == Level.NONE) overlay.hide() else overlay.update(a, settings)
        }
    }

    // Status -----------------------------------------------------------------

    private fun statusText(): String {
        paused?.let { return it }
        val names = store.settings().apps.map(GuardianApps::label).sorted()
        return if (names.isEmpty()) "No apps selected. Choose UPI apps in Spendo."
        else "Watching ${names.joinToString(", ")} for budget alerts. Tap Stop to turn it off."
    }

    private fun updateStatusText() = GuardianNotifications.updateStatus(this, statusText())

    private fun openApp() {
        startActivity(
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        )
    }

    companion object {
        private const val TAG = "SpendingGuardian"
        const val ACTION_STOP = "com.expensebot.expense_tracker_app.guardian.STOP"

        private const val POLL_INTERVAL_MS = 1_000L
        private const val PAUSED_INTERVAL_MS = 10_000L
        private const val LOOKBACK_MS = 10_000L
        private const val PERMISSION_CHECK_EVERY = 30

        /** ACTIVITY_RESUMED on API 29+, MOVE_TO_FOREGROUND before — same value. */
        private const val RESUMED = 1

        private val TRANSIENT_PACKAGES = setOf(
            "com.android.systemui",
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
        )

        @Volatile
        var running = false
            private set

        fun hasUsageAccess(context: Context): Boolean {
            val ops = context.getSystemService(AppOpsManager::class.java)
            // Still the documented way to read this app-op; deprecated on
            // API 36 without a public replacement for usage stats.
            @Suppress("DEPRECATION")
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
            }
            return if (mode == AppOpsManager.MODE_DEFAULT) {
                context.checkCallingOrSelfPermission(android.Manifest.permission.PACKAGE_USAGE_STATS) ==
                    android.content.pm.PackageManager.PERMISSION_GRANTED
            } else {
                mode == AppOpsManager.MODE_ALLOWED
            }
        }

        fun canDrawOverlays(context: Context): Boolean = Settings.canDrawOverlays(context)

        /** Starts monitoring. Only call from a user action while the app is visible, or at boot. */
        fun start(context: Context): Boolean = try {
            val intent = Intent(context, GuardianService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
            else context.startService(intent)
            true
        } catch (e: Exception) {
            Log.w(TAG, "Could not start: ${e.javaClass.simpleName}")
            false
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, GuardianService::class.java))
        }
    }
}

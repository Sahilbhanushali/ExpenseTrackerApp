package com.expensebot.expense_tracker_app.guardian

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.expensebot.expense_tracker_app.MainActivity
import com.expensebot.expense_tracker_app.R
import java.time.LocalDate

object GuardianNotifications {
    private const val CHANNEL_STATUS = "guardian_status"
    private const val CHANNEL_ALERTS = "guardian_alerts"
    const val STATUS_ID = 7100
    private const val MONTH_ALERT_ID = 7101
    private const val CATEGORY_ALERT_ID = 7102

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_STATUS, "Spending Guardian status", NotificationManager.IMPORTANCE_LOW)
                .apply {
                    description = "Shown while Smart Spending Guardian is monitoring your selected UPI apps."
                    setShowBadge(false)
                },
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ALERTS, "Budget threshold alerts", NotificationManager.IMPORTANCE_DEFAULT)
                .apply { description = "When your spending reaches 80%, 100% or more of a budget." },
        )
    }

    private fun builder(context: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, channel)
        else @Suppress("DEPRECATION") Notification.Builder(context)

    private fun openAppIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context, 0,
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** The persistent notification a foreground service must show. */
    fun status(context: Context, text: String): Notification {
        val stop = PendingIntent.getService(
            context, 1,
            Intent(context, GuardianService::class.java).setAction(GuardianService.ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return builder(context, CHANNEL_STATUS)
            .setSmallIcon(R.drawable.ic_guardian)
            .setContentTitle("Smart Spending Guardian is on")
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(openAppIntent(context))
            .addAction(Notification.Action.Builder(null, "Stop monitoring", stop).build())
            .build()
    }

    fun updateStatus(context: Context, text: String) {
        context.getSystemService(NotificationManager::class.java).notify(STATUS_ID, status(context, text))
    }

    private fun canPost(context: Context): Boolean =
        context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    /**
     * Called whenever Flutter pushes fresh figures. Notifies once per level
     * crossed per month (and per category), independently of the overlay and
     * of whether monitoring is on. A level that drops (an expense deleted) is
     * re-armed, so crossing it again notifies again.
     */
    fun onSnapshotUpdated(context: Context, store: GuardianStore) {
        val snapshot = store.snapshot() ?: return
        val settings = store.settings()
        val a = GuardianRules.assess(snapshot, settings, LocalDate.now()) ?: return
        // The first evaluation only records where things stand, so turning
        // the feature on doesn't immediately announce an old crossing.
        val firstRun = !store.hasNotifiedState()
        val previous = store.notifiedLevels(snapshot.month)
        val current = mutableMapOf("month" to a.monthLevel.ordinal)
        for (c in snapshot.categories) {
            current["c:${c.name}"] = GuardianRules.monthLevel(c.spentPaise, c.capPaise, settings.cautionPercent).ordinal
        }
        store.saveNotifiedLevels(snapshot.month, current)
        if (firstRun) return

        val prevMonth = previous["month"] ?: 0
        if (a.monthLevel == Level.EXCEEDED && prevMonth < Level.EXCEEDED.ordinal) store.recordBudgetExceeded()
        if (!settings.notifyThresholds || !canPost(context)) return

        val cur = snapshot.currency
        if (a.monthLevel.ordinal > prevMonth) {
            val (title, body) = when (a.monthLevel) {
                Level.EXCEEDED -> "Monthly budget exceeded" to
                    "You've spent ${Money.format(a.spent, cur)} of ${Money.format(a.budget, cur)}, ${Money.format(a.spent - a.budget, cur)} over."
                Level.REACHED -> "Monthly budget reached" to
                    "You've spent your full ${Money.format(a.budget, cur)} budget for this month."
                else -> "${a.percent}% of monthly budget used" to
                    "${Money.format(a.budget - a.spent, cur)} left for the rest of the month."
            }
            post(context, MONTH_ALERT_ID, title, body)
        }

        val crossed = snapshot.categories.filter {
            val now = current["c:${it.name}"] ?: 0
            now >= Level.CAUTION.ordinal && now > (previous["c:${it.name}"] ?: 0)
        }
        if (crossed.isNotEmpty()) {
            val body = crossed.joinToString(" ") {
                if (it.spentPaise > it.capPaise) "${it.name}: ${Money.format(it.spentPaise - it.capPaise, cur)} over budget."
                else "${it.name}: ${Money.format(it.capPaise - it.spentPaise, cur)} left."
            }
            post(context, CATEGORY_ALERT_ID, "Category budget alert", body)
        }
    }

    private fun post(context: Context, id: Int, title: String, body: String) {
        val n = builder(context, CHANNEL_ALERTS)
            .setSmallIcon(R.drawable.ic_guardian)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(openAppIntent(context))
            .build()
        context.getSystemService(NotificationManager::class.java).notify(id, n)
    }
}

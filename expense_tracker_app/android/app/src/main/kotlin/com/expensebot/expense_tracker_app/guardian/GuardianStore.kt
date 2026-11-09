package com.expensebot.expense_tracker_app.guardian

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/** The UPI apps the Guardian can watch, in display order. */
object GuardianApps {
    val SUPPORTED: Map<String, String> = linkedMapOf(
        "com.google.android.apps.nbu.paisa.user" to "Google Pay",
        "com.phonepe.app" to "PhonePe",
        "net.one97.paytm" to "Paytm",
        "in.org.npci.upiapp" to "BHIM",
    )

    fun label(pkg: String): String = SUPPORTED[pkg] ?: pkg
}

data class GuardianSettings(
    val enabled: Boolean,
    val apps: Set<String>,
    val cautionPercent: Int,
    val alertCaution: Boolean,
    val alertLimit: Boolean,
    val alertDaily: Boolean,
    val alertCategory: Boolean,
    val cooldownMinutes: Int,
    val notifyThresholds: Boolean,
)

data class CategorySpend(val name: String, val capPaise: Long, val spentPaise: Long)

/**
 * Budget figures as Flutter last computed them from the ledger. A cache, not
 * a second source of truth: the Flutter app rewrites it after every change to
 * transactions or budgets, and [computedAt] lets readers judge staleness.
 */
data class BudgetSnapshot(
    val computedAt: Long,
    /** yyyy-MM the figures belong to. */
    val month: String,
    /** yyyy-MM-dd [todaySpentPaise] belongs to. */
    val day: String,
    val currency: String,
    val budgetPaise: Long,
    val spentPaise: Long,
    val todaySpentPaise: Long,
    val categories: List<CategorySpend>,
) {
    companion object {
        fun parse(json: String): BudgetSnapshot? = try {
            val o = JSONObject(json)
            val cats = o.optJSONArray("categories") ?: JSONArray()
            BudgetSnapshot(
                computedAt = o.getLong("computedAt"),
                month = o.getString("month"),
                day = o.getString("day"),
                currency = o.optString("currency", "₹"),
                budgetPaise = o.getLong("budget"),
                spentPaise = o.getLong("spent"),
                todaySpentPaise = o.optLong("todaySpent", 0),
                categories = (0 until cats.length()).map {
                    val c = cats.getJSONObject(it)
                    CategorySpend(c.getString("name"), c.getLong("cap"), c.getLong("spent"))
                },
            )
        } catch (e: Exception) {
            null
        }
    }
}

/**
 * Native-side persistence for the Guardian. It must work while no Flutter
 * engine is running, so it never depends on a MethodChannel round trip.
 *
 * Stores only preferences, the budget snapshot, alert bookkeeping and
 * opening counts per monitored app — never payment details or any content
 * from other apps.
 */
class GuardianStore(context: Context) {
    val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    fun settings() = GuardianSettings(
        enabled = prefs.getBoolean(K_ENABLED, false),
        apps = prefs.getStringSet(K_APPS, null)?.toSet() ?: GuardianApps.SUPPORTED.keys,
        cautionPercent = prefs.getInt(K_CAUTION, 80).coerceIn(50, 95),
        alertCaution = prefs.getBoolean(K_ALERT_CAUTION, true),
        alertLimit = prefs.getBoolean(K_ALERT_LIMIT, true),
        alertDaily = prefs.getBoolean(K_ALERT_DAILY, false),
        alertCategory = prefs.getBoolean(K_ALERT_CATEGORY, true),
        cooldownMinutes = prefs.getInt(K_COOLDOWN, 30).coerceIn(0, 24 * 60),
        notifyThresholds = prefs.getBoolean(K_NOTIFY, true),
    )

    fun settingsMap(): Map<String, Any> = settings().let {
        mapOf(
            "enabled" to it.enabled,
            "apps" to it.apps.toList(),
            "cautionPercent" to it.cautionPercent,
            "alertCaution" to it.alertCaution,
            "alertLimit" to it.alertLimit,
            "alertDaily" to it.alertDaily,
            "alertCategory" to it.alertCategory,
            "cooldownMinutes" to it.cooldownMinutes,
            "notifyThresholds" to it.notifyThresholds,
        )
    }

    /** Applies only the keys present; unknown keys are ignored. */
    fun updateSettings(values: Map<*, *>) {
        val e = prefs.edit()
        (values["apps"] as? List<*>)?.let { list ->
            e.putStringSet(K_APPS, list.filterIsInstance<String>()
                .filter { it in GuardianApps.SUPPORTED }.toSet())
        }
        (values["cautionPercent"] as? Number)?.let { e.putInt(K_CAUTION, it.toInt().coerceIn(50, 95)) }
        (values["cooldownMinutes"] as? Number)?.let { e.putInt(K_COOLDOWN, it.toInt().coerceIn(0, 24 * 60)) }
        for ((key, pref) in BOOL_KEYS) {
            (values[key] as? Boolean)?.let { e.putBoolean(pref, it) }
        }
        e.apply()
    }

    fun setEnabled(enabled: Boolean) = prefs.edit().putBoolean(K_ENABLED, enabled).apply()

    fun snapshot(): BudgetSnapshot? = prefs.getString(K_SNAPSHOT, null)?.let(BudgetSnapshot::parse)

    /** Returns false (and stores nothing) if [json] isn't a valid snapshot. */
    fun saveSnapshot(json: String): Boolean {
        if (BudgetSnapshot.parse(json) == null) return false
        prefs.edit().putString(K_SNAPSHOT, json).apply()
        return true
    }

    // Alert bookkeeping ------------------------------------------------------

    val lastAlertAt: Long get() = prefs.getLong(K_LAST_ALERT_AT, 0)
    val lastAlertSeverity: Int get() = prefs.getInt(K_LAST_ALERT_SEVERITY, 0)

    fun recordAlert(now: Long, severity: Int) {
        prefs.edit()
            .putLong(K_LAST_ALERT_AT, now)
            .putInt(K_LAST_ALERT_SEVERITY, severity)
            .putInt(K_STAT_ALERTS, prefs.getInt(K_STAT_ALERTS, 0) + 1)
            .apply()
    }

    fun recordOpen(pkg: String) {
        val key = K_STAT_OPENS + pkg
        prefs.edit().putInt(key, prefs.getInt(key, 0) + 1).apply()
    }

    /** Levels already notified this month: "month" → overall, "c:<name>" → category. */
    fun notifiedLevels(month: String): MutableMap<String, Int> {
        val raw = prefs.getString(K_NOTIFIED, null) ?: return mutableMapOf()
        return try {
            val o = JSONObject(raw)
            if (o.optString("month") != month) return mutableMapOf()
            val levels = o.getJSONObject("levels")
            levels.keys().asSequence().associateWith { levels.getInt(it) }.toMutableMap()
        } catch (e: Exception) {
            mutableMapOf()
        }
    }

    /** False until the first snapshot has been evaluated on this install. */
    fun hasNotifiedState(): Boolean = prefs.contains(K_NOTIFIED)

    fun saveNotifiedLevels(month: String, levels: Map<String, Int>) {
        val o = JSONObject().put("month", month).put("levels", JSONObject(levels))
        prefs.edit().putString(K_NOTIFIED, o.toString()).apply()
    }

    fun recordBudgetExceeded() =
        prefs.edit().putInt(K_STAT_EXCEEDED, prefs.getInt(K_STAT_EXCEEDED, 0) + 1).apply()

    fun stats(): Map<String, Any> = mapOf(
        "alertsShown" to prefs.getInt(K_STAT_ALERTS, 0),
        "budgetExceeded" to prefs.getInt(K_STAT_EXCEEDED, 0),
        "opens" to GuardianApps.SUPPORTED.keys.associateWith { prefs.getInt(K_STAT_OPENS + it, 0) },
    )

    fun resetStats() {
        val e = prefs.edit().remove(K_STAT_ALERTS).remove(K_STAT_EXCEEDED)
        GuardianApps.SUPPORTED.keys.forEach { e.remove(K_STAT_OPENS + it) }
        e.apply()
    }

    companion object {
        private const val NAME = "spending_guardian"
        const val K_ENABLED = "enabled"
        const val K_APPS = "apps"
        const val K_CAUTION = "caution_percent"
        const val K_ALERT_CAUTION = "alert_caution"
        const val K_ALERT_LIMIT = "alert_limit"
        const val K_ALERT_DAILY = "alert_daily"
        const val K_ALERT_CATEGORY = "alert_category"
        const val K_COOLDOWN = "cooldown_minutes"
        const val K_NOTIFY = "notify_thresholds"
        const val K_SNAPSHOT = "snapshot"
        private const val K_LAST_ALERT_AT = "last_alert_at"
        private const val K_LAST_ALERT_SEVERITY = "last_alert_severity"
        private const val K_NOTIFIED = "notified_levels"
        private const val K_STAT_ALERTS = "stat_alerts"
        private const val K_STAT_EXCEEDED = "stat_exceeded"
        private const val K_STAT_OPENS = "stat_opens_"

        private val BOOL_KEYS = mapOf(
            "alertCaution" to K_ALERT_CAUTION,
            "alertLimit" to K_ALERT_LIMIT,
            "alertDaily" to K_ALERT_DAILY,
            "alertCategory" to K_ALERT_CATEGORY,
            "notifyThresholds" to K_NOTIFY,
        )
    }
}

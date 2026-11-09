package com.expensebot.expense_tracker_app.guardian

import java.time.LocalDate
import java.time.format.DateTimeFormatter

/** Ordered by severity, so `>` means "worse". Mirrored in Dart as GuardianLevel. */
enum class Level { NONE, CAUTION, REACHED, EXCEEDED }

data class Assessment(
    val snapshot: BudgetSnapshot,
    val monthLevel: Level,
    /** Worst of month, category and daily triggers that the user enabled. */
    val severity: Level,
    val percent: Int,
    val overCategories: List<CategorySpend>,
    /** Today's limit, set at the start of the day; null without a budget. */
    val dailyLimitPaise: Long?,
    val todaySpentPaise: Long,
    val dailyOver: Boolean,
) {
    val budget get() = snapshot.budgetPaise
    val spent get() = snapshot.spentPaise
}

/**
 * Same thresholds as the app's budget logic: "over" means spent > budget,
 * "reached" means spent == budget, caution starts at the configured
 * percentage (80% by default, matching the existing in-app warnings).
 */
object GuardianRules {
    private val MONTH = DateTimeFormatter.ofPattern("yyyy-MM")
    private val DAY = DateTimeFormatter.ofPattern("yyyy-MM-dd")

    fun monthLevel(spent: Long, budget: Long, cautionPercent: Int): Level = when {
        budget <= 0 -> Level.NONE
        spent > budget -> Level.EXCEEDED
        spent == budget -> Level.REACHED
        spent * 100 >= budget * cautionPercent -> Level.CAUTION
        else -> Level.NONE
    }

    /**
     * Null when the snapshot belongs to a different month: last month's
     * spending must never be presented as this month's.
     */
    fun assess(s: BudgetSnapshot, settings: GuardianSettings, today: LocalDate): Assessment? {
        if (s.month != today.format(MONTH)) return null
        val month = monthLevel(s.spentPaise, s.budgetPaise, settings.cautionPercent)
        val percent = if (s.budgetPaise > 0) (s.spentPaise * 100 / s.budgetPaise).toInt() else 0
        val over = s.categories.filter { it.capPaise > 0 && it.spentPaise > it.capPaise }

        // A snapshot from an earlier day has nothing spent "today" yet.
        val sameDay = s.day == today.format(DAY)
        val todaySpent = if (sameDay) s.todaySpentPaise else 0L
        val daysLeft = today.lengthOfMonth() - today.dayOfMonth + 1
        val dailyLimit = if (s.budgetPaise > 0) {
            ((s.budgetPaise - (s.spentPaise - todaySpent)) / daysLeft).coerceAtLeast(0)
        } else null
        val dailyOver = dailyLimit != null && todaySpent > 0 && todaySpent > dailyLimit

        var severity = Level.NONE
        // With limit alerts off, being at or past 100% still deserves the
        // caution the user did ask for.
        if (month >= Level.CAUTION && settings.alertCaution) severity = Level.CAUTION
        if (month >= Level.REACHED && settings.alertLimit) severity = month
        if (settings.alertCategory && over.isNotEmpty() && severity < Level.CAUTION) severity = Level.CAUTION
        if (settings.alertDaily && dailyOver && severity < Level.CAUTION) severity = Level.CAUTION
        return Assessment(s, month, severity, percent, over, dailyLimit, todaySpent, dailyOver)
    }

    /** Overlay title and one-line message for the worst active trigger. */
    fun headline(a: Assessment, settings: GuardianSettings): Pair<String, String> {
        val cur = a.snapshot.currency
        return when {
            a.severity == Level.EXCEEDED -> "Your monthly budget has been exceeded!" to
                "You have exceeded your budget by ${Money.format(a.spent - a.budget, cur)}."
            a.severity == Level.REACHED -> "Monthly limit reached" to
                "You have reached your monthly spending limit."
            // Only reachable from the in-app preview.
            a.severity == Level.NONE -> "Your budget is on track" to
                "You have used ${a.percent}% of your monthly budget."
            a.monthLevel >= Level.CAUTION && settings.alertCaution ->
                (if (a.percent >= 100) "You've used your monthly budget" else "You're close to your budget") to
                    "You have used ${a.percent}% of your monthly budget."
            settings.alertCategory && a.overCategories.size == 1 -> a.overCategories[0].let {
                "${it.name.titleCase()} budget exceeded" to
                    "You're ${Money.format(it.spentPaise - it.capPaise, cur)} over your ${it.name} budget this month."
            }
            settings.alertCategory && a.overCategories.size > 1 ->
                "${a.overCategories.size} category budgets exceeded" to
                    "Some of your category budgets are already used up this month."
            else -> "Over today's spending limit" to
                "You've spent ${Money.format(a.todaySpentPaise, cur)} today. Your daily limit is ${Money.format(a.dailyLimitPaise ?: 0, cur)}."
        }
    }

    private fun String.titleCase() = replaceFirstChar { it.uppercase() }
}

/** Port of the app's formatMoney: Indian digit grouping, paise only when non-zero. */
object Money {
    fun format(paise: Long, currency: String): String {
        val sign = if (paise < 0) "-" else ""
        val abs = kotlin.math.abs(paise)
        val rupees = group((abs / 100).toString())
        val rem = abs % 100
        return if (rem == 0L) "$sign$currency$rupees" else "$sign$currency$rupees.${rem.toString().padStart(2, '0')}"
    }

    private fun group(s: String): String {
        if (s.length <= 3) return s
        val last3 = s.takeLast(3)
        var rest = s.dropLast(3)
        val parts = ArrayList<String>()
        while (rest.length > 2) {
            parts.add(0, rest.takeLast(2))
            rest = rest.dropLast(2)
        }
        if (rest.isNotEmpty()) parts.add(0, rest)
        return parts.joinToString(",") + "," + last3
    }
}

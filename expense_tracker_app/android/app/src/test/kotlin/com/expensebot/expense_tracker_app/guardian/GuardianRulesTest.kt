package com.expensebot.expense_tracker_app.guardian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class GuardianRulesTest {
    private val today = LocalDate.of(2026, 11, 21)

    private val settings = GuardianSettings(
        enabled = true,
        apps = GuardianApps.SUPPORTED.keys,
        cautionPercent = 80,
        alertCaution = true,
        alertLimit = true,
        alertDaily = false,
        alertCategory = true,
        cooldownMinutes = 30,
        notifyThresholds = true,
    )

    private fun snapshot(
        spent: Long,
        budget: Long = 2_000_000,
        month: String = "2026-11",
        day: String = "2026-11-21",
        today: Long = 0,
        categories: List<CategorySpend> = emptyList(),
    ) = BudgetSnapshot(0, month, day, "₹", budget, spent, today, categories)

    @Test
    fun levelsMatchTheAppRules() {
        assertEquals(Level.NONE, GuardianRules.monthLevel(1_599, 2_000, 80))
        assertEquals(Level.CAUTION, GuardianRules.monthLevel(1_600, 2_000, 80))
        assertEquals(Level.REACHED, GuardianRules.monthLevel(2_000, 2_000, 80))
        assertEquals(Level.EXCEEDED, GuardianRules.monthLevel(2_001, 2_000, 80))
        assertEquals(Level.NONE, GuardianRules.monthLevel(5_000, 0, 80))
    }

    @Test
    fun exceededHeadlineStatesTheOverspend() {
        val a = GuardianRules.assess(snapshot(spent = 2_245_000), settings, today)!!
        assertEquals(Level.EXCEEDED, a.severity)
        val (title, message) = GuardianRules.headline(a, settings)
        assertEquals("Your monthly budget has been exceeded!", title)
        assertEquals("You have exceeded your budget by ₹2,450.", message)
    }

    @Test
    fun lastMonthsFiguresAreNeverUsed() {
        assertNull(GuardianRules.assess(snapshot(spent = 3_000_000, month = "2026-10"), settings, today))
    }

    @Test
    fun cautionStillAppliesWhenLimitAlertsAreOff() {
        val a = GuardianRules.assess(snapshot(spent = 2_100_000), settings.copy(alertLimit = false), today)!!
        assertEquals(Level.CAUTION, a.severity)
        assertEquals("You've used your monthly budget", GuardianRules.headline(a, settings.copy(alertLimit = false)).first)
    }

    @Test
    fun categoryOverspendTriggersOnlyWhenEnabled() {
        val cats = listOf(CategorySpend("food", 500_000, 600_000))
        val on = GuardianRules.assess(snapshot(spent = 100_000, categories = cats), settings, today)!!
        assertEquals(Level.CAUTION, on.severity)
        assertEquals("You're ₹1,000 over your food budget this month.", GuardianRules.headline(on, settings).second)

        val off = GuardianRules.assess(snapshot(spent = 100_000, categories = cats), settings.copy(alertCategory = false), today)!!
        assertEquals(Level.NONE, off.severity)
    }

    @Test
    fun dailyLimitUsesWhatWasLeftThisMorning() {
        // ₹20,000 − (₹15,000 − ₹1,000 today) = ₹6,000 over 10 days left.
        val a = GuardianRules.assess(snapshot(spent = 1_500_000, today = 100_000), settings.copy(alertDaily = true), today)!!
        assertEquals(60_000L, a.dailyLimitPaise)
        assertTrue(a.dailyOver)

        // Yesterday's snapshot: nothing is known to be spent today yet.
        val stale = GuardianRules.assess(
            snapshot(spent = 1_500_000, today = 100_000, day = "2026-11-20"),
            settings.copy(alertDaily = true), today,
        )!!
        assertEquals(0L, stale.todaySpentPaise)
    }

    @Test
    fun moneyUsesIndianGrouping() {
        assertEquals("₹2,450", Money.format(245_000, "₹"))
        assertEquals("₹1,23,45,678.90", Money.format(1_234_567_890, "₹"))
        assertEquals("-₹5.05", Money.format(-505, "₹"))
    }

    @Test
    fun snapshotParsingRejectsGarbage() {
        assertNull(BudgetSnapshot.parse("not json"))
        val parsed = BudgetSnapshot.parse(
            """{"computedAt":1,"month":"2026-11","day":"2026-11-21","currency":"₹","budget":10,"spent":5,"todaySpent":1,"categories":[{"name":"food","cap":3,"spent":4}]}""",
        )!!
        assertEquals(1, parsed.categories.size)
        assertEquals(5L, parsed.spentPaise)
    }
}

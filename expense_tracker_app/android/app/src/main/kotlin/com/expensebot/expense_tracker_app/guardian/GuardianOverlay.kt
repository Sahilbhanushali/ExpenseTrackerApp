package com.expensebot.expense_tracker_app.guardian

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.PixelFormat
import android.os.Build
import android.provider.Settings
import android.util.AttributeSet
import android.util.Log
import android.util.TypedValue
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import com.expensebot.expense_tracker_app.R
import kotlin.math.min

/** ScrollView that never grows past [maxHeightPx], so the card stays compact. */
class MaxHeightScrollView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : ScrollView(context, attrs) {
    var maxHeightPx = Int.MAX_VALUE

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(maxHeightPx, MeasureSpec.AT_MOST))
    }
}

/**
 * The budget warning window. Purely informational: it is not focusable (the
 * keyboard and every touch outside the card go to the app underneath), it
 * never reads or changes anything in that app, and it sits at the top of the
 * screen, clear of payment buttons.
 *
 * Must be used from the main thread.
 */
class GuardianOverlay(private val context: Context, private val onOpenApp: () -> Unit) {
    private val wm = context.getSystemService(WindowManager::class.java)
    private var view: View? = null
    private var shown: Pair<Assessment, GuardianSettings>? = null

    val isShowing: Boolean get() = view != null

    private fun themed(): Context = ContextThemeWrapper(
        context,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) android.R.style.Theme_DeviceDefault_DayNight
        else android.R.style.Theme_Material_Light_NoActionBar,
    )

    /** Shows (or refreshes in place) the alert. False if the OS refused the window. */
    // An overlay window has no parent to inflate against.
    @SuppressLint("InflateParams")
    fun show(a: Assessment, settings: GuardianSettings): Boolean {
        if (!Settings.canDrawOverlays(context)) {
            hide()
            return false
        }
        view?.let {
            bind(it, a, settings)
            shown = a to settings
            return true
        }
        val v = LayoutInflater.from(themed()).inflate(R.layout.guardian_overlay, null)
        bind(v, a, settings)
        return try {
            wm.addView(v, layoutParams())
            view = v
            shown = a to settings
            animateIn(v)
            true
        } catch (e: RuntimeException) {
            // BadTokenException / SecurityException when the permission was
            // revoked between the check and the call.
            Log.w(TAG, "Overlay refused: ${e.javaClass.simpleName}")
            false
        }
    }

    /** Refreshes the figures if the card is on screen. */
    fun update(a: Assessment, settings: GuardianSettings) {
        val v = view ?: return
        bind(v, a, settings)
        shown = a to settings
    }

    fun hide() {
        val v = view ?: return
        view = null
        shown = null
        try {
            wm.removeViewImmediate(v)
        } catch (e: RuntimeException) {
            Log.w(TAG, "Overlay already gone: ${e.javaClass.simpleName}")
        }
    }

    /** Rotation, resize, or a light/dark switch: rebuild for the new config. */
    fun onConfigurationChanged() {
        val (a, settings) = shown ?: return
        hide()
        show(a, settings)
    }

    private fun dp(v: Int) = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), context.resources.displayMetrics,
    ).toInt()

    private fun layoutParams(): WindowManager.LayoutParams {
        val dm = context.resources.displayMetrics
        val margin = dp(12)
        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }
        return WindowManager.LayoutParams(
            min(dm.widthPixels - margin * 2, dp(440)),
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = statusBarHeight() + margin
            title = "Spendo budget alert"
        }
    }

    @Suppress("DiscouragedApi", "InternalInsetResource")
    private fun statusBarHeight(): Int {
        val id = context.resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) context.resources.getDimensionPixelSize(id) else dp(24)
    }

    private fun animateIn(v: View) {
        val enabled = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled()
        if (!enabled) return
        v.alpha = 0f
        v.translationY = -dp(12).toFloat()
        v.animate().alpha(1f).translationY(0f).setDuration(220).start()
    }

    private fun bind(v: View, a: Assessment, settings: GuardianSettings) {
        val res = context.resources
        val severe = a.severity >= Level.REACHED
        val accent = context.getColor(
            when {
                severe -> R.color.guardian_expense
                a.severity == Level.CAUTION -> R.color.guardian_warning
                else -> R.color.guardian_ok
            },
        )
        val cur = a.snapshot.currency
        val (title, message) = GuardianRules.headline(a, settings)

        v.findViewById<ImageView>(R.id.guardian_icon).apply {
            setImageResource(
                when {
                    severe -> R.drawable.ic_guardian_error
                    a.severity == Level.CAUTION -> R.drawable.ic_guardian_warning
                    else -> R.drawable.ic_guardian
                },
            )
            imageTintList = ColorStateList.valueOf(accent)
            backgroundTintList = ColorStateList.valueOf(accent and 0x00FFFFFF or 0x26000000)
        }
        v.findViewById<TextView>(R.id.guardian_title).text = title
        v.findViewById<TextView>(R.id.guardian_message).text = message
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            v.findViewById<View>(R.id.guardian_root).accessibilityPaneTitle = title
        }
        (v.findViewById<View>(R.id.guardian_scroll) as MaxHeightScrollView).maxHeightPx =
            (res.displayMetrics.heightPixels * 0.6).toInt()

        val summary = v.findViewById<View>(R.id.guardian_summary)
        if (a.budget > 0) {
            summary.visibility = View.VISIBLE
            v.findViewById<TextView>(R.id.guardian_budget).text = Money.format(a.budget, cur)
            v.findViewById<TextView>(R.id.guardian_spent).text = Money.format(a.spent, cur)
            val over = a.spent > a.budget
            v.findViewById<TextView>(R.id.guardian_delta_label).text = if (over) "Exceeded by" else "Remaining"
            v.findViewById<TextView>(R.id.guardian_delta).apply {
                text = Money.format(kotlin.math.abs(a.budget - a.spent), cur)
                setTextColor(if (over) accent else context.getColor(R.color.guardian_text_primary))
            }
            v.findViewById<ProgressBar>(R.id.guardian_progress).apply {
                progress = a.percent.coerceIn(0, 100)
                progressTintList = ColorStateList.valueOf(accent)
                contentDescription = "${a.percent} percent of monthly budget used"
            }
            v.findViewById<TextView>(R.id.guardian_percent).text = "${a.percent}% of monthly budget used"
        } else {
            summary.visibility = View.GONE
        }

        val details = buildList {
            if (settings.alertCategory && a.overCategories.isNotEmpty()) {
                a.overCategories.take(3).forEach {
                    add("• ${it.name}: ${Money.format(it.spentPaise - it.capPaise, cur)} over its ${Money.format(it.capPaise, cur)} budget")
                }
                if (a.overCategories.size > 3) add("• and ${a.overCategories.size - 3} more categories")
            }
            if (settings.alertDaily && a.dailyLimitPaise != null) {
                add("• Today: ${Money.format(a.todaySpentPaise, cur)} spent of a ${Money.format(a.dailyLimitPaise, cur)} daily limit")
            }
        }
        v.findViewById<TextView>(R.id.guardian_details).apply {
            visibility = if (details.isEmpty()) View.GONE else View.VISIBLE
            text = details.joinToString("\n")
        }

        val age = System.currentTimeMillis() - a.snapshot.computedAt
        v.findViewById<TextView>(R.id.guardian_updated).apply {
            if (age > STALE_AFTER_MS) {
                text = "Figures from ${ago(age)}, so they may be out of date. Open Spendo to refresh."
                setTextColor(context.getColor(R.color.guardian_warning))
            } else {
                text = "Updated ${ago(age)}"
                setTextColor(context.getColor(R.color.guardian_text_tertiary))
            }
        }

        v.findViewById<View>(R.id.guardian_dismiss).setOnClickListener { hide() }
        v.findViewById<View>(R.id.guardian_open).setOnClickListener {
            hide()
            onOpenApp()
        }
    }

    private fun ago(ms: Long): String {
        val min = ms / 60_000
        return when {
            min < 1 -> "just now"
            min < 60 -> "$min min ago"
            min < 24 * 60 -> "${min / 60} h ago"
            else -> "${min / (24 * 60)} days ago"
        }
    }

    companion object {
        private const val TAG = "GuardianOverlay"

        /** Spending recorded outside the app (e.g. on another device) can't be known. */
        const val STALE_AFTER_MS = 6 * 60 * 60 * 1000L
    }
}

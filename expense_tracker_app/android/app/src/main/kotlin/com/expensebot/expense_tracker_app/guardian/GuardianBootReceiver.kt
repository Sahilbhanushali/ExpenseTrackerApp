package com.expensebot.expense_tracker_app.guardian

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Resumes monitoring after a reboot or an app update, but only if the user
 * had turned it on and both permissions are still granted. Some phone makers
 * block boot receivers for apps the user hasn't allowed to auto-start; then
 * monitoring resumes the next time Spendo is opened.
 */
class GuardianBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) return
        if (!GuardianStore(context).settings().enabled) return
        if (!GuardianService.hasUsageAccess(context) || !GuardianService.canDrawOverlays(context)) return
        GuardianService.start(context)
    }
}

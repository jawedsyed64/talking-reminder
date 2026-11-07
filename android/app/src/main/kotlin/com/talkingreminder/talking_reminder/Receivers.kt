package com.talkingreminder.talking_reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** The system alarm fired: start the speaking service. */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val i = Intent(ctx, ReminderService::class.java).setAction(ReminderService.ACTION_PROCESS)
        try {
            ctx.startForegroundService(i)
        } catch (e: Exception) {
            // The system refused to start the service: still show the reminders as notifications.
            val st = Store.settings(Store.read(ctx))
            val r = Scheduler.processDue(ctx, false)
            r.alerts.forEach { Notifier.postAlert(ctx, it, st.optInt("snooze", 10)) }
            Notifier.postMissed(ctx, r.missed)
            Scheduler.reschedule(ctx)
        }
    }
}

/** Buttons on the reminder notification. */
class ActionReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        Actions.perform(
            ctx,
            intent.getStringExtra("act") ?: "dismiss",
            intent.getStringExtra("taskId"),
            intent.getLongExtra("occ", 0L),
            intent.getStringExtra("key") ?: "",
            intent.getIntExtra("minutes", 10),
            0L
        )
    }
}

/** Phone restarted, app updated, or clock / time zone changed: set the alarm again. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val pending = goAsync()
        Thread {
            try {
                val boot = intent.action != Intent.ACTION_TIME_CHANGED && intent.action != Intent.ACTION_TIMEZONE_CHANGED &&
                    intent.action != "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"
                val r = Scheduler.processDue(ctx, boot)
                val st = Store.settings(Store.read(ctx))
                // Without the speaking service (not allowed at boot), recent reminders still appear.
                r.alerts.forEach { Notifier.postAlert(ctx, it, st.optInt("snooze", 10)) }
                Notifier.postMissed(ctx, r.missed)
                Scheduler.reschedule(ctx)
            } finally {
                pending.finish()
            }
        }.start()
    }
}

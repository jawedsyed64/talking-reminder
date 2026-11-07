package com.talkingreminder.talking_reminder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import org.json.JSONObject

object Notifier {
    const val CH_REM = "reminders_v1"
    const val CH_SVC = "service_v1"
    const val CH_MISSED = "missed_v1"
    const val FG_ID = 7001
    private const val MISSED_ID = 7002
    private const val COLOR = 0xFF5B4BDB.toInt()

    private fun nm(ctx: Context) = ctx.getSystemService(NotificationManager::class.java)

    fun ensureChannels(ctx: Context) {
        val nm = nm(ctx) ?: return
        val rem = NotificationChannel(CH_REM, "Spoken reminders", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Your task reminders. The app plays its own sound and voice."
            setSound(null, null)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 450, 250, 450)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        val svc = NotificationChannel(CH_SVC, "Speaking a reminder", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Shown briefly while a reminder is being spoken."
            setSound(null, null)
        }
        val missed = NotificationChannel(CH_MISSED, "Missed reminders", NotificationManager.IMPORTANCE_DEFAULT)
        nm.createNotificationChannels(listOf(rem, svc, missed))
    }

    fun canFullScreen(ctx: Context): Boolean =
        if (Build.VERSION.SDK_INT >= 34) nm(ctx)?.canUseFullScreenIntent() ?: false else true

    fun serviceNotification(ctx: Context): Notification {
        ensureChannels(ctx)
        return Notification.Builder(ctx, CH_SVC)
            .setSmallIcon(R.drawable.ic_stat_bell)
            .setContentTitle("Talking Reminder")
            .setContentText("Speaking your reminder…")
            .setColor(COLOR)
            .setOngoing(true)
            .build()
    }

    private fun actionPI(ctx: Context, a: Alert, act: String, minutes: Int, req: Int): PendingIntent {
        val i = Intent(ctx, ActionReceiver::class.java)
            .setAction("com.talkingreminder.ACT.$act.${a.key}")
            .putExtra("act", act).putExtra("taskId", a.taskId ?: "").putExtra("occ", a.occ)
            .putExtra("key", a.key).putExtra("minutes", minutes)
        return PendingIntent.getBroadcast(ctx, req, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun postAlert(ctx: Context, a: Alert, snoozeMin: Int) {
        ensureChannels(ctx)
        val id = a.key.hashCode()
        val open = PendingIntent.getActivity(ctx, id, MainActivity.alertIntent(ctx, a),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val icon = Icon.createWithResource(ctx, R.drawable.ic_stat_bell)
        val title = when (a.kind) {
            "advance" -> "In ${a.off} min: ${a.title}"
            "test" -> "🔔 Test reminder"
            else -> "🔔 ${a.title}"
        }
        val b = Notification.Builder(ctx, CH_REM)
            .setSmallIcon(R.drawable.ic_stat_bell)
            .setContentTitle(title)
            .setContentText(a.text)
            .setStyle(Notification.BigTextStyle().bigText(a.text))
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setColor(COLOR)
            .setContentIntent(open)
            .setAutoCancel(true)
            .setWhen(a.occ).setShowWhen(true)
        if (a.kind != "advance" && canFullScreen(ctx)) b.setFullScreenIntent(open, true)
        if (a.kind != "test") {
            b.addAction(Notification.Action.Builder(icon, "✔ Done", actionPI(ctx, a, "done", 0, id * 4 + 1)).build())
            b.addAction(Notification.Action.Builder(icon, "Snooze $snoozeMin min", actionPI(ctx, a, "snooze", snoozeMin, id * 4 + 2)).build())
        }
        b.addAction(Notification.Action.Builder(icon, "Dismiss", actionPI(ctx, a, "dismiss", 0, id * 4 + 3)).build())
        try { nm(ctx)?.notify(id, b.build()) } catch (e: SecurityException) { /* notifications not allowed */ }
    }

    fun postMissed(ctx: Context, missed: List<JSONObject>) {
        if (missed.isEmpty()) return
        ensureChannels(ctx)
        val titles = missed.joinToString(", ") { Store.str(it, "title") }
        val open = PendingIntent.getActivity(ctx, MISSED_ID, Intent(ctx, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val n = Notification.Builder(ctx, CH_MISSED)
            .setSmallIcon(R.drawable.ic_stat_bell)
            .setContentTitle("⏰ You missed ${missed.size} reminder${if (missed.size > 1) "s" else ""}")
            .setContentText(titles)
            .setStyle(Notification.BigTextStyle().bigText(titles))
            .setColor(COLOR)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try { nm(ctx)?.notify(MISSED_ID, n) } catch (e: SecurityException) { }
    }

    fun cancel(ctx: Context, key: String) { nm(ctx)?.cancel(key.hashCode()) }
}

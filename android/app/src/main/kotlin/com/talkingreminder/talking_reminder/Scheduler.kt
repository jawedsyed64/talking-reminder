package com.talkingreminder.talking_reminder

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDateTime

data class Alert(
    val key: String, val taskId: String?, val title: String, val occ: Long,
    val kind: String, val off: Int, val text: String
) {
    fun toJson(): JSONObject = JSONObject().put("key", key).put("taskId", taskId ?: "").put("title", title)
        .put("occ", occ).put("kind", kind).put("offset", off).put("text", text)

    companion object {
        fun fromJson(o: JSONObject) = Alert(
            Store.str(o, "key"), Store.str(o, "taskId").ifEmpty { null }, Store.str(o, "title"),
            o.optLong("occ"), Store.str(o, "kind"), o.optInt("offset"), Store.str(o, "text")
        )
    }
}

/**
 * Uses ONE exact system alarm for the earliest upcoming reminder. When it fires, every due
 * reminder is processed and the alarm is set again for the next one. The system keeps the
 * alarm while the app is closed; BootReceiver sets it again after a restart.
 */
object Scheduler {
    const val ACTION_FIRE = "com.talkingreminder.FIRE"
    const val MISSED_MS = 5 * 60_000L

    private class Ev(val at: Long, val taskId: String?, val occ: Long, val off: Int, val kind: String,
                     val snoozeId: String?, val key: String?)

    private fun events(st: JSONObject, now: LocalDateTime): List<Ev> {
        val out = mutableListOf<Ev>()
        val fired = st.optJSONObject("fired") ?: JSONObject()
        val tasks = st.optJSONArray("tasks") ?: JSONArray()
        for (i in 0 until tasks.length()) {
            val t = tasks.optJSONObject(i) ?: continue
            if (t.optBoolean("completed")) continue
            val id = Store.str(t, "id")
            val first = Rec.pendingOcc(t, now) ?: continue
            val offs = mutableListOf(0)
            t.optJSONArray("advance")?.let { for (j in 0 until it.length()) if (it.optInt(j) > 0) offs.add(it.optInt(j)) }
            var occ: LocalDateTime? = first
            for (n in 0 until 3) {
                val oc = occ ?: break
                val om = Rec.toMs(oc)
                for (off in offs) {
                    val key = "$id|$om|$off"
                    if (fired.has(key)) continue
                    out.add(Ev(om - off * 60_000L, id, om, off, if (off > 0) "advance" else "due", null, key))
                }
                if (!Rec.isRec(t)) break
                occ = Rec.nextOcc(t, oc.plusMinutes(1))
            }
        }
        val sn = st.optJSONArray("snoozes") ?: JSONArray()
        for (i in 0 until sn.length()) {
            val z = sn.optJSONObject(i) ?: continue
            val test = z.optBoolean("test")
            out.add(Ev(z.optLong("at"), Store.str(z, "taskId").ifEmpty { null }, z.optLong("occ"), 0,
                if (test) "test" else "snooze", Store.str(z, "id"), null))
        }
        return out
    }

    class Result(val alerts: List<Alert>, val missed: List<JSONObject>)

    /** Marks every due reminder as handled and returns what must be announced now. */
    fun processDue(ctx: Context, fromBoot: Boolean): Result {
        val alerts = mutableListOf<Alert>()
        val missed = mutableListOf<JSONObject>()
        Store.mutate(ctx) { st ->
            val now = System.currentTimeMillis()
            val nowL = Rec.fromMs(now)
            val fired = Store.obj(st, "fired")
            val settings = Store.settings(st)
            // keep recurring cursors pointing at the current occurrence
            val tasks = st.optJSONArray("tasks") ?: JSONArray()
            for (i in 0 until tasks.length()) {
                val t = tasks.optJSONObject(i) ?: continue
                if (t.optBoolean("completed") || !Rec.isRec(t)) continue
                val o = Rec.pendingOcc(t, nowL) ?: continue
                val om = Rec.toMs(o)
                if (t.optLong("cursor", 0L) < om) t.put("cursor", om)
            }
            val due = events(st, nowL).filter { it.at <= now + 1000 }.sortedBy { it.at }
            val removeSnoozes = mutableSetOf<String>()
            for (e in due) {
                if (e.key != null) fired.put(e.key, now)
                if (e.snoozeId != null) removeSnoozes.add(e.snoozeId)
                if (e.kind == "test") {
                    if (now - e.at < MISSED_MS)
                        alerts.add(Alert("test|${e.snoozeId}", null, "Test reminder", now, "test", 0,
                            Store.str(settings, "sample").ifEmpty { Messages.DEFAULT_SAMPLE }))
                    continue
                }
                val t = Store.findTask(st, e.taskId) ?: continue
                if (t.optBoolean("completed")) continue
                val title = Store.str(t, "title")
                if (e.kind == "advance") {
                    if (now < e.occ && !fromBoot && now - e.at < MISSED_MS)
                        alerts.add(Alert("advance|${e.taskId}|${e.occ}|${e.off}|", e.taskId, title, e.occ, "advance", e.off,
                            Messages.build(t, Rec.fromMs(e.occ), "advance", e.off, settings)))
                    continue
                }
                if (fromBoot || now - e.at > MISSED_MS) {
                    missed.add(JSONObject().put("taskId", e.taskId).put("occ", e.occ).put("title", title))
                    continue
                }
                alerts.add(Alert("${e.kind}|${e.taskId}|${e.occ}|${e.off}|${e.snoozeId ?: ""}", e.taskId, title, e.occ,
                    e.kind, e.off, Messages.build(t, Rec.fromMs(e.occ), e.kind, e.off, settings)))
            }
            if (removeSnoozes.isNotEmpty()) {
                val old = Store.arr(st, "snoozes"); val keep = JSONArray()
                for (i in 0 until old.length()) {
                    val z = old.optJSONObject(i) ?: continue
                    if (!removeSnoozes.contains(Store.str(z, "id"))) keep.put(z)
                }
                st.put("snoozes", keep)
            }
            if (missed.isNotEmpty()) {
                val m = Store.arr(st, "missed")
                for (x in missed) m.put(x)
            }
            // prune old "already fired" markers
            val limit = now - 45L * 86_400_000L
            val stale = mutableListOf<String>()
            fired.keys().forEach { k -> if (fired.optLong(k) < limit) stale.add(k) }
            stale.forEach { fired.remove(it) }
        }
        return Result(alerts, missed)
    }

    private fun firePI(ctx: Context): PendingIntent =
        PendingIntent.getBroadcast(ctx, 1, Intent(ctx, AlarmReceiver::class.java).setAction(ACTION_FIRE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun openPI(ctx: Context): PendingIntent =
        PendingIntent.getActivity(ctx, 2, Intent(ctx, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun canExact(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        val am = ctx.getSystemService(AlarmManager::class.java) ?: return false
        return am.canScheduleExactAlarms()
    }

    /** Sets the system alarm for the earliest upcoming reminder. Returns its time (0 = none). */
    fun reschedule(ctx: Context): Long {
        val st = Store.read(ctx)
        val now = System.currentTimeMillis()
        val evs = events(st, Rec.fromMs(now))
        val dueNow = evs.any { it.at <= now }
        val next = evs.map { it.at }.filter { it > now }.minOrNull()
        val at: Long? = if (dueNow) now + 1500 else next
        val am = ctx.getSystemService(AlarmManager::class.java) ?: return 0
        val pi = firePI(ctx)
        if (at == null) {
            am.cancel(pi)
            Store.prefs(ctx).edit().putLong("nextAlarm", 0L).apply()
            return 0
        }
        try {
            if (canExact(ctx)) am.setAlarmClock(AlarmManager.AlarmClockInfo(at, openPI(ctx)), pi)
            else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        } catch (e: SecurityException) {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
        Store.prefs(ctx).edit().putLong("nextAlarm", if (dueNow) (next ?: at) else at).apply()
        return at
    }
}

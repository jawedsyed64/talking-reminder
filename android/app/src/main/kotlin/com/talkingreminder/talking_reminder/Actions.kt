package com.talkingreminder.talking_reminder

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.time.LocalDateTime

/** DONE / SNOOZE / REMIND LATER / DISMISS — shared by notification buttons and the in-app alert screen. */
object Actions {
    fun markDone(st: JSONObject, taskId: String, occ: Long?) {
        val t = Store.findTask(st, taskId) ?: return
        val now = System.currentTimeMillis()
        if (Rec.isRec(t)) {
            val o = if (occ != null && occ > 0) occ
                    else Rec.pendingOcc(t, LocalDateTime.now())?.let { Rec.toMs(it) } ?: return
            val e = JSONObject().put("id", Store.uid()).put("taskId", taskId).put("title", Store.str(t, "title"))
                .put("category", Store.str(t, "category")).put("occ", o).put("at", now)
            val h = Store.arr(st, "history")
            val nh = JSONArray().put(e)
            for (i in 0 until minOf(h.length(), 399)) nh.put(h.get(i))
            st.put("history", nh)
            t.put("cursor", maxOf(t.optLong("cursor", 0L), o + 60_000L))
        } else {
            t.put("completed", true)
            t.put("completedAt", now)
        }
        removeSnoozes(st, taskId)
    }

    fun addSnooze(st: JSONObject, taskId: String, occ: Long, at: Long) {
        Store.arr(st, "snoozes").put(JSONObject().put("id", Store.uid()).put("taskId", taskId).put("occ", occ).put("at", at))
    }

    fun remindLater(st: JSONObject, taskId: String, occ: Long, at: Long) {
        val t = Store.findTask(st, taskId) ?: return
        if (Rec.isRec(t)) { addSnooze(st, taskId, occ, at); return }
        val d = Rec.fromMs(at)
        t.put("date", d.toLocalDate().toString())
        t.put("time", "%02d:%02d".format(java.util.Locale.US, d.hour, d.minute))
        removeSnoozes(st, taskId)
    }

    private fun removeSnoozes(st: JSONObject, taskId: String) {
        val old = Store.arr(st, "snoozes"); val keep = JSONArray()
        for (i in 0 until old.length()) {
            val z = old.optJSONObject(i) ?: continue
            if (Store.str(z, "taskId") != taskId) keep.put(z)
        }
        st.put("snoozes", keep)
    }

    /** act = done | snooze | later | dismiss */
    fun perform(ctx: Context, act: String, taskId: String?, occ: Long, key: String, minutes: Int, at: Long) {
        if (!taskId.isNullOrEmpty() && act != "dismiss") {
            Store.mutate(ctx) { st ->
                when (act) {
                    "done" -> markDone(st, taskId, occ)
                    "snooze" -> addSnooze(st, taskId, occ, System.currentTimeMillis() + minutes * 60_000L)
                    "later" -> remindLater(st, taskId, occ, at)
                }
            }
        }
        if (key.isNotEmpty()) Notifier.cancel(ctx, key)
        ReminderService.instance?.ack(key)
        Scheduler.reschedule(ctx)
        MainActivity.stateChanged()
    }
}

package com.talkingreminder.talking_reminder

import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Recurrence engine. Tasks are stored as local wall-clock date + time, so a reminder set
 * for 10:00 rings at 10:00 local time even after a time-zone or daylight-saving change.
 * Mirrors lib/core.dart exactly.
 */
object Rec {
    private fun zone(): ZoneId = ZoneId.systemDefault()
    fun toMs(t: LocalDateTime): Long = t.atZone(zone()).toInstant().toEpochMilli()
    fun fromMs(ms: Long): LocalDateTime = LocalDateTime.ofInstant(Instant.ofEpochMilli(ms), zone())
    /** 0 = Sunday … 6 = Saturday (same as JavaScript / the Dart side). */
    fun jsDow(d: LocalDate): Int = d.dayOfWeek.value % 7

    fun start(t: JSONObject): LocalDateTime? = try {
        val d = LocalDate.parse(Store.str(t, "date"))
        val p = Store.str(t, "time").ifEmpty { "09:00" }.split(":")
        d.atTime(p[0].trim().toInt(), p.getOrElse(1) { "0" }.trim().toInt())
    } catch (e: Exception) { null }

    fun isRec(t: JSONObject): Boolean {
        val ty = Store.str(t.optJSONObject("repeat"), "type")
        return ty.isNotEmpty() && ty != "none"
    }

    private class Rule(val unit: String, val every: Int, val days: List<Int>)

    private fun rule(t: JSONObject, s: LocalDateTime): Rule? {
        val r = t.optJSONObject("repeat") ?: return null
        val sd = listOf(jsDow(s.toLocalDate()))
        val days = mutableListOf<Int>()
        r.optJSONArray("days")?.let { for (i in 0 until it.length()) days.add(it.optInt(i)) }
        return when (Store.str(r, "type")) {
            "daily" -> Rule("day", 1, sd)
            "weekly" -> Rule("week", 1, if (days.isEmpty()) sd else days)
            "monthly" -> Rule("month", 1, sd)
            "custom" -> {
                val u = Store.str(r, "unit").ifEmpty { "day" }
                Rule(u, maxOf(1, r.optInt("every", 1)), if (days.isEmpty()) sd else days)
            }
            else -> null
        }
    }

    private fun until(t: JSONObject): LocalDateTime? {
        val u = Store.str(t.optJSONObject("repeat"), "until")
        if (u.isEmpty()) return null
        return try { LocalDate.parse(u).atTime(23, 59) } catch (e: Exception) { null }
    }

    /** First occurrence at or after [after], or null. */
    fun nextOcc(t: JSONObject, after: LocalDateTime): LocalDateTime? {
        val s = start(t) ?: return null
        val r = rule(t, s) ?: return if (!s.isBefore(after)) s else null
        val base = if (after.isAfter(s)) after else s
        var c: LocalDateTime? = null
        when (r.unit) {
            "day" -> {
                var k = maxOf(0L, ChronoUnit.DAYS.between(s.toLocalDate(), base.toLocalDate()) / r.every)
                for (i in 0 until 4) {
                    val x = s.plusDays(k * r.every)
                    if (!x.isBefore(after)) { c = x; break }
                    k++
                }
            }
            "week" -> {
                val ws = s.toLocalDate().minusDays(jsDow(s.toLocalDate()).toLong())
                val b = base.toLocalDate()
                for (i in 0 until 7 * r.every + 8) {
                    val d = b.plusDays(i.toLong())
                    val wk = Math.floorDiv(ChronoUnit.DAYS.between(ws, d), 7L)
                    if (wk % r.every == 0L && r.days.contains(jsDow(d))) {
                        val x = d.atTime(s.toLocalTime())
                        if (!x.isBefore(after) && !x.isBefore(s)) { c = x; break }
                    }
                }
            }
            else -> {
                var k = maxOf(0L, ((base.year - s.year) * 12L + base.monthValue - s.monthValue) / r.every - 1)
                for (i in 0 until 5) {
                    val x = s.plusMonths(k * r.every)
                    if (!x.isBefore(after) && !x.isBefore(s)) { c = x; break }
                    k++
                }
            }
        }
        val u = until(t)
        if (c != null && u != null && c.isAfter(u)) return null
        return c
    }

    /** The occurrence the user currently has to deal with: the latest past undone one, or the next one. */
    fun pendingOcc(t: JSONObject, now: LocalDateTime): LocalDateTime? {
        if (!isRec(t)) return if (t.optBoolean("completed")) null else start(t)
        var o = nextOcc(t, fromMs(t.optLong("cursor", 0L))) ?: return null
        for (g in 0 until 3000) {
            val n = nextOcc(t, o.plusMinutes(1))
            if (n != null && !n.isAfter(now)) o = n else break
        }
        return o
    }
}

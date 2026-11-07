package com.talkingreminder.talking_reminder

import org.json.JSONObject
import java.time.LocalDateTime
import java.time.temporal.ChronoUnit
import java.util.Locale

/** Builds the sentence that is spoken aloud for a reminder. */
object Messages {
    const val DEFAULT_SAMPLE =
        "Hello! This is your reminder. You have a business meeting scheduled for today at 10 AM. Please get ready."

    private val CLOSING = mapOf(
        "Work" to "Please get ready.",
        "Health" to "Don't forget to take care of your health.",
        "Family" to "Your family will appreciate it.",
        "Shopping" to "Don't forget your list.",
        "Finance" to "Please take care of it on time.",
        "Study" to "Good luck with your studies.",
        "Personal" to "Have a great day.",
        "Other" to "Have a great day."
    )
    private val MONTHS = arrayOf("January", "February", "March", "April", "May", "June", "July",
        "August", "September", "October", "November", "December")
    private val DAYS = arrayOf("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")

    private fun p2(n: Int) = if (n < 10) "0$n" else "$n"

    fun speakTime(d: LocalDateTime, fmt24: Boolean): String {
        if (fmt24) return "${p2(d.hour)}:${p2(d.minute)}"
        val h = if (d.hour % 12 == 0) 12 else d.hour % 12
        val ap = if (d.hour < 12) "AM" else "PM"
        return if (d.minute == 0) "$h $ap" else "$h:${p2(d.minute)} $ap"
    }

    private fun spokenDay(d: LocalDateTime): String {
        val diff = ChronoUnit.DAYS.between(LocalDateTime.now().toLocalDate(), d.toLocalDate())
        return when (diff) {
            0L -> "today"
            1L -> "tomorrow"
            -1L -> "yesterday"
            else -> "on ${DAYS[Rec.jsDow(d.toLocalDate())]}, ${d.dayOfMonth} ${MONTHS[d.monthValue - 1]}"
        }
    }

    private fun dot(s: String): String {
        val x = s.trim()
        if (x.isEmpty()) return x
        return if (x.last() in ".!?۔") x else "$x."
    }

    private fun fill(tpl: String, title: String, time: String, day: String) =
        tpl.replace(Regex("\\{title\\}", RegexOption.IGNORE_CASE), title)
            .replace(Regex("\\{time\\}", RegexOption.IGNORE_CASE), time)
            .replace(Regex("\\{date\\}", RegexOption.IGNORE_CASE), day)

    fun lang(settings: JSONObject): String =
        Store.str(settings, "lang").ifEmpty { Store.str(settings, "voiceLang") }.ifEmpty { Locale.getDefault().toLanguageTag() }

    fun build(t: JSONObject, occ: LocalDateTime, kind: String, offset: Int, settings: JSONObject): String {
        val title = Store.str(t, "title")
        val desc = Store.str(t, "description")
        val notes = Store.str(t, "notes")
        val custom = Store.str(t, "message")
        val fmt24 = Store.str(settings, "timeFormat") == "24"
        val time = speakTime(occ, fmt24)
        val day = spokenDay(occ)

        if (lang(settings).lowercase().startsWith("ur")) {
            val diff = ChronoUnit.DAYS.between(LocalDateTime.now().toLocalDate(), occ.toLocalDate())
            val dUr = when (diff) { 0L -> "آج"; 1L -> "کل"; else -> "${occ.dayOfMonth} ${MONTHS[occ.monthValue - 1]} کو" }
            val h = if (occ.hour % 12 == 0) 12 else occ.hour % 12
            val part = when { occ.hour < 12 -> "صبح"; occ.hour < 17 -> "دوپہر"; else -> "شام" }
            val tUr = "$part ${h}:${p2(occ.minute)} بجے"
            val n = if (notes.isNotEmpty()) " نوٹ: $notes۔" else ""
            if (kind == "advance") return "السلام علیکم! $offset منٹ بعد، $tUr، آپ کا کام ہے: $title۔$n"
            if (custom.isNotEmpty()) return fill(custom, title, tUr, dUr) + n
            val again = if (kind == "snooze") "دوبارہ یاد دہانی۔ " else ""
            val d = if (desc.isNotEmpty() && desc.length < 220) " $desc۔" else ""
            return "السلام علیکم! ${again}یہ آپ کی یاد دہانی ہے۔ $dUr $tUr آپ کا کام ہے: $title۔$d$n"
        }

        val parts = mutableListOf<String>()
        if (kind == "advance") {
            parts.add("Hello! This is an early reminder. In $offset minutes, at $time, you have: ${dot(title)}")
            if (notes.isNotEmpty()) parts.add("Note: ${dot(notes)}")
            return parts.joinToString(" ")
        }
        if (custom.isNotEmpty()) {
            if (kind == "snooze") parts.add("Hello again! This is your snoozed reminder.")
            parts.add(dot(fill(custom, title, time, day)))
            if (notes.isNotEmpty()) parts.add("Note: ${dot(notes)}")
            return parts.joinToString(" ")
        }
        parts.add(if (kind == "snooze") "Hello again! This is your snoozed reminder." else "Hello! This is your reminder.")
        parts.add("It's time for: ${dot(title)} Scheduled for $day at $time.")
        if (desc.isNotEmpty() && desc.length < 220) parts.add(dot(desc))
        if (notes.isNotEmpty()) parts.add("Note: ${dot(notes)}")
        parts.add(CLOSING[Store.str(t, "category")] ?: CLOSING.getValue("Other"))
        return parts.joinToString(" ")
    }
}

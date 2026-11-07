package com.talkingreminder.talking_reminder

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import org.json.JSONObject
import java.util.Locale

/** Applies the user's voice settings and plays the alert sound. Speech uses the ALARM volume. */
object Voice {
    val ALARM_ATTRS: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    fun configure(tts: TextToSpeech, s: JSONObject) {
        try { tts.setAudioAttributes(ALARM_ATTRS) } catch (e: Exception) { }
        var ok = false
        val vn = Store.str(s, "voiceName")
        if (vn.isNotEmpty()) {
            try {
                val v = tts.voices?.firstOrNull { it.name == vn }
                if (v != null) ok = tts.setVoice(v) == TextToSpeech.SUCCESS
            } catch (e: Exception) { }
        }
        if (!ok) {
            val lang = Store.str(s, "lang")
            if (lang.isNotEmpty()) try { tts.setLanguage(Locale.forLanguageTag(lang)) } catch (e: Exception) { }
        }
        tts.setSpeechRate(s.optDouble("rate", 0.95).toFloat())
        tts.setPitch(s.optDouble("pitch", 1.0).toFloat())
    }

    fun speak(tts: TextToSpeech, text: String, s: JSONObject, id: String) {
        val b = Bundle()
        b.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, s.optDouble("volume", 1.0).toFloat())
        b.putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, AudioManager.STREAM_ALARM)
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, b, id)
    }

    /** Plays the chosen alert sound; returns how long to wait before speaking (ms). */
    fun playSound(ctx: Context, name: String): Long {
        val h = Handler(Looper.getMainLooper())
        try {
            when (name) {
                "none" -> return 0
                "beep" -> {
                    val tg = ToneGenerator(AudioManager.STREAM_ALARM, 85)
                    tg.startTone(ToneGenerator.TONE_PROP_BEEP2, 900)
                    h.postDelayed({ tg.release() }, 1500)
                    return 1100
                }
                else -> {
                    val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION) ?: return 0
                    val r = RingtoneManager.getRingtone(ctx, uri) ?: return 0
                    r.audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
                    r.play()
                    h.postDelayed({ try { r.stop() } catch (e: Exception) { } }, 2600)
                    return 2000
                }
            }
        } catch (e: Exception) { return 0 }
    }
}

/** A long-lived TextToSpeech used by the app screens (voice list, TEST VOICE, previews). */
class PreviewSpeaker(ctx: Context) {
    private val app = ctx.applicationContext
    private var ready = false
    private var failed = false
    private val waiting = mutableListOf<() -> Unit>()
    private val tts: TextToSpeech = TextToSpeech(app) { status ->
        ready = status == TextToSpeech.SUCCESS
        failed = !ready
        val w = waiting.toList(); waiting.clear(); w.forEach { it() }
    }

    fun whenReady(fn: () -> Unit) { if (ready || failed) fn() else waiting.add(fn) }
    fun isReady() = ready

    fun voices(): List<Map<String, Any>> {
        if (!ready) return emptyList()
        return try {
            (tts.voices ?: emptySet())
                .filter { !it.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED) }
                .sortedWith(compareBy({ it.locale.toLanguageTag() }, { it.name }))
                .map {
                    mapOf(
                        "name" to it.name,
                        "lang" to it.locale.toLanguageTag(),
                        "langName" to it.locale.getDisplayName(Locale.ENGLISH),
                        "network" to it.isNetworkConnectionRequired,
                        "quality" to it.quality
                    )
                }
        } catch (e: Exception) { emptyList() }
    }

    fun defaultLang(): String = try { tts.defaultVoice?.locale?.toLanguageTag() ?: "" } catch (e: Exception) { "" }

    fun speak(text: String, settings: JSONObject, onDone: ((Boolean) -> Unit)? = null) {
        whenReady {
            if (!ready) { onDone?.invoke(false); return@whenReady }
            Voice.configure(tts, settings)
            tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(id: String?) {}
                override fun onDone(id: String?) { onDone?.invoke(true) }
                @Deprecated("Deprecated in Java")
                override fun onError(id: String?) { onDone?.invoke(false) }
                override fun onError(id: String?, code: Int) { onDone?.invoke(false) }
            })
            Voice.speak(tts, text, settings, "preview")
        }
    }

    fun stop() { try { tts.stop() } catch (e: Exception) { } }
    fun shutdown() { try { tts.shutdown() } catch (e: Exception) { } }
}

package com.talkingreminder.talking_reminder

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import org.json.JSONObject

/**
 * Started by the system alarm. Shows the reminder notification(s) and speaks them aloud with
 * the phone's Text-to-Speech engine, even when the app is closed or the screen is off.
 * Optionally repeats the spoken reminder twice (45 s apart) until you press a button.
 */
class ReminderService : Service() {
    companion object {
        const val ACTION_PROCESS = "com.talkingreminder.PROCESS"
        @Volatile var instance: ReminderService? = null
    }

    private val handler = Handler(Looper.getMainLooper())
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var speaking = false
    private var waitingRepeats = 0
    private val active = LinkedHashMap<String, Alert>()
    private val repeats = HashMap<String, Int>()
    private val queue = ArrayDeque<Alert>()
    private var settings = JSONObject()
    private var wake: PowerManager.WakeLock? = null
    private var finished = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startFg()
        finished = false
        settings = Store.settings(Store.read(this))
        val r = Scheduler.processDue(this, false)
        Scheduler.reschedule(this)
        Notifier.postMissed(this, r.missed)
        val snooze = settings.optInt("snooze", 10)
        for (a in r.alerts) {
            Notifier.postAlert(this, a, snooze)
            active[a.key] = a
            repeats[a.key] = 0
            queue.addLast(a)
            MainActivity.onAlert(a)
        }
        MainActivity.stateChanged()
        if (queue.isEmpty()) { finishIfIdle(); return START_NOT_STICKY }
        acquireWake()
        ensureTts()
        handler.postDelayed({ finish() }, 4 * 60_000L) // hard safety limit
        return START_NOT_STICKY
    }

    private fun startFg() {
        val n = Notifier.serviceNotification(this)
        if (Build.VERSION.SDK_INT >= 29) startForeground(Notifier.FG_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        else startForeground(Notifier.FG_ID, n)
    }

    private fun acquireWake() {
        if (wake?.isHeld == true) return
        val pm = getSystemService(PowerManager::class.java) ?: return
        wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TalkingReminder:speak").apply { acquire(4 * 60_000L) }
    }

    private fun ensureTts() {
        if (tts != null) { if (ttsReady && !speaking) speakNext(); return }
        tts = TextToSpeech(applicationContext) { status ->
            handler.post {
                if (status == TextToSpeech.SUCCESS) {
                    ttsReady = true
                    tts?.let { Voice.configure(it, settings); it.setOnUtteranceProgressListener(listener) }
                    speakNext()
                } else {
                    // No speech engine: notifications are already shown, so just finish.
                    queue.clear(); waitingRepeats = 0; finishIfIdle()
                }
            }
        }
    }

    private val listener = object : UtteranceProgressListener() {
        override fun onStart(id: String?) {}
        override fun onDone(id: String?) { handler.post { afterSpeech(id) } }
        @Deprecated("Deprecated in Java")
        override fun onError(id: String?) { handler.post { afterSpeech(id) } }
        override fun onError(id: String?, code: Int) { handler.post { afterSpeech(id) } }
        override fun onStop(id: String?, interrupted: Boolean) { handler.post { afterSpeech(id) } }
    }

    private fun speakNext() {
        if (speaking || finished) return
        var a: Alert? = null
        while (queue.isNotEmpty()) { val x = queue.removeFirst(); if (active.containsKey(x.key)) { a = x; break } }
        if (a == null) { finishIfIdle(); return }
        val al: Alert = a
        speaking = true
        val wait = Voice.playSound(this, Store.str(settings, "sound").ifEmpty { "chime" })
        handler.postDelayed({
            val t = tts
            if (t == null || !active.containsKey(al.key)) { speaking = false; speakNext(); return@postDelayed }
            Voice.speak(t, al.text, settings, al.key)
        }, wait + 250)
    }

    private fun afterSpeech(id: String?) {
        if (!speaking) return
        speaking = false
        val key = id ?: ""
        val n = repeats[key] ?: 0
        if (settings.optBoolean("repeatSpeak", true) && active.containsKey(key) && n < 2) {
            repeats[key] = n + 1
            waitingRepeats++
            handler.postDelayed({
                waitingRepeats--
                active[key]?.let { queue.addLast(it) }
                if (!speaking) speakNext()
            }, 45_000L)
        }
        speakNext()
    }

    /** Called when the user presses Done/Snooze/Dismiss for an alert. */
    fun ack(key: String) {
        handler.post {
            active.remove(key)
            if (active.isEmpty()) { try { tts?.stop() } catch (e: Exception) { }; queue.clear(); finish() }
        }
    }

    private fun finishIfIdle() {
        if (!speaking && queue.isEmpty() && waitingRepeats <= 0) finish()
    }

    private fun finish() {
        if (finished) return
        finished = true
        handler.removeCallbacksAndMessages(null)
        try { tts?.stop(); tts?.shutdown() } catch (e: Exception) { }
        tts = null; ttsReady = false; speaking = false
        try { if (wake?.isHeld == true) wake?.release() } catch (e: Exception) { }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (!finished) finish()
        instance = null
        super.onDestroy()
    }
}

package com.talkingreminder.talking_reminder

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.speech.RecognizerIntent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL = "talking_reminder/native"
        private const val REQ_SPEECH = 4242
        private const val REQ_NOTIF = 4343
        @Volatile var instance: MainActivity? = null

        fun alertIntent(ctx: Context, a: Alert): Intent =
            Intent(ctx, MainActivity::class.java)
                .setAction("com.talkingreminder.ALERT.${a.key}")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra("alert", a.toJson().toString())

        fun onAlert(a: Alert) {
            val act = instance ?: return
            act.runOnUiThread { act.channel?.invokeMethod("showAlert", a.toJson().toString()) }
        }

        fun stateChanged() {
            val act = instance ?: return
            act.runOnUiThread { act.channel?.invokeMethod("stateChanged", null) }
        }
    }

    var channel: MethodChannel? = null
    private var preview: PreviewSpeaker? = null
    private var launchAlert: String? = null
    private var pendingListen: MethodChannel.Result? = null
    private var pendingPerm: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        readAlert(intent)
        super.onCreate(savedInstanceState)
        instance = this
        Notifier.ensureChannels(this)
        preview = PreviewSpeaker(this)
        Scheduler.reschedule(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readAlert(intent)
        launchAlert?.let { channel?.invokeMethod("showAlert", it); launchAlert = null }
    }

    override fun onResume() { super.onResume(); instance = this }

    override fun onDestroy() {
        if (instance === this) instance = null
        preview?.shutdown()
        super.onDestroy()
    }

    private fun readAlert(i: Intent?) {
        val a = i?.getStringExtra("alert") ?: return
        launchAlert = a
        i.removeExtra("alert")
        if (Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(true); setTurnScreenOn(true) }
        else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            try { handle(call, result) } catch (e: Exception) { result.error("native", e.message, null) }
        }
    }

    private fun str(call: MethodCall, k: String): String = call.argument<String>(k) ?: ""
    private fun num(call: MethodCall, k: String): Long = (call.argument<Any>(k) as? Number)?.toLong() ?: 0L

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "load" -> result.success(Store.read(this).toString())
            "save" -> {
                Store.write(this, JSONObject(call.arguments as String))
                Scheduler.reschedule(this)
                result.success(true)
            }
            "reschedule" -> result.success(Scheduler.reschedule(this))
            "status" -> result.success(status())
            "voices" -> {
                val p = preview ?: return result.success(mapOf("voices" to emptyList<Any>(), "default" to ""))
                var answered = false
                val reply = {
                    if (!answered) { answered = true; result.success(mapOf("voices" to p.voices(), "default" to p.defaultLang(), "ready" to p.isReady())) }
                }
                p.whenReady { main.post { reply() } }
                main.postDelayed({ reply() }, 5000)
            }
            "speak" -> {
                val settings = try { JSONObject(str(call, "settings")) } catch (e: Exception) { Store.settings(Store.read(this)) }
                val sound = call.argument<Boolean>("sound") ?: false
                val text = str(call, "text")
                val wait = if (sound) Voice.playSound(this, Store.str(settings, "sound").ifEmpty { "chime" }) else 0L
                main.postDelayed({ preview?.speak(text, settings) }, wait)
                result.success(preview?.isReady() ?: false)
            }
            "stopSpeaking" -> { preview?.stop(); result.success(true) }
            "playSound" -> { Voice.playSound(this, str(call, "sound")); result.success(true) }
            "buildMessage" -> {
                val t = JSONObject(str(call, "task"))
                val st = Store.settings(Store.read(this))
                val s2 = try { JSONObject(str(call, "settings")) } catch (e: Exception) { st }
                result.success(Messages.build(t, Rec.fromMs(num(call, "occ")), str(call, "kind").ifEmpty { "due" },
                    num(call, "offset").toInt(), s2))
            }
            "alertAction" -> {
                Actions.perform(this, str(call, "act"), str(call, "taskId").ifEmpty { null }, num(call, "occ"),
                    str(call, "key"), num(call, "minutes").toInt(), num(call, "at"))
                preview?.stop()
                result.success(true)
            }
            "takeLaunchAlert" -> { result.success(launchAlert); launchAlert = null }
            "testIn" -> {
                val at = System.currentTimeMillis() + num(call, "seconds") * 1000L
                Store.mutate(this) { st ->
                    Store.arr(st, "snoozes").put(JSONObject().put("id", Store.uid()).put("test", true).put("occ", at).put("at", at))
                }
                Scheduler.reschedule(this)
                result.success(at)
            }
            "requestNotifications" -> {
                if (Build.VERSION.SDK_INT >= 33 &&
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    pendingPerm = result
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF)
                } else { openSettings("notifications"); result.success(true) }
            }
            "openSettings" -> { openSettings(str(call, "which")); result.success(true) }
            "listen" -> {
                val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                    .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    .putExtra(RecognizerIntent.EXTRA_PROMPT, "Say your reminder, e.g. “Remind me to call Ahmed tomorrow at 3 PM”")
                val lang = str(call, "lang")
                if (lang.isNotEmpty()) i.putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang)
                try { pendingListen = result; startActivityForResult(i, REQ_SPEECH) }
                catch (e: ActivityNotFoundException) { pendingListen = null; result.error("no_speech", "Speech input is not available on this phone.", null) }
            }
            "share" -> {
                val i = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, str(call, "text"))
                    .putExtra(Intent.EXTRA_SUBJECT, "Talking Reminder backup")
                startActivity(Intent.createChooser(i, "Save backup"))
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun status(): Map<String, Any> {
        val nm = getSystemService(NotificationManager::class.java)
        val pm = getSystemService(PowerManager::class.java)
        val notifPerm = Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val ch = nm?.getNotificationChannel(Notifier.CH_REM)
        return mapOf(
            "notifications" to (notifPerm && (nm?.areNotificationsEnabled() ?: false) &&
                (ch == null || ch.importance != NotificationManager.IMPORTANCE_NONE)),
            "exactAlarms" to Scheduler.canExact(this),
            "battery" to (pm?.isIgnoringBatteryOptimizations(packageName) ?: false),
            "fullScreen" to Notifier.canFullScreen(this),
            "manufacturer" to Build.MANUFACTURER,
            "sdk" to Build.VERSION.SDK_INT,
            "nextAlarm" to Store.prefs(this).getLong("nextAlarm", 0L)
        )
    }

    private fun openSettings(which: String) {
        val pkg = Uri.parse("package:$packageName")
        val i = when (which) {
            "exact" -> if (Build.VERSION.SDK_INT >= 31) Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, pkg) else null
            "battery" -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, pkg)
            "fullscreen" -> if (Build.VERSION.SDK_INT >= 34) Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, pkg) else null
            "notifications" -> Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            "tts" -> Intent("com.android.settings.TTS_SETTINGS")
            else -> null
        } ?: Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg)
        try { startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        catch (e: Exception) {
            try { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (e2: Exception) { }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_SPEECH) {
            val text = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            pendingListen?.success(text)
            pendingListen = null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIF) {
            pendingPerm?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingPerm = null
        }
    }
}

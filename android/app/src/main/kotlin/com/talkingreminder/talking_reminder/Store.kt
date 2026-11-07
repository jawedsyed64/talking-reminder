package com.talkingreminder.talking_reminder

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Single source of truth for all app data: one JSON file in the app's private storage.
 * Both the Flutter UI (through the method channel) and the background alarm code read
 * and write it, always under the same lock.
 */
object Store {
    private const val FILE = "state.json"
    private val lock = Any()

    fun read(ctx: Context): JSONObject {
        synchronized(lock) {
            val f = File(ctx.filesDir, FILE)
            if (!f.exists()) return JSONObject()
            return try { JSONObject(f.readText()) } catch (e: Exception) { JSONObject() }
        }
    }

    fun write(ctx: Context, o: JSONObject) {
        synchronized(lock) {
            val tmp = File(ctx.filesDir, "$FILE.tmp")
            tmp.writeText(o.toString())
            val dest = File(ctx.filesDir, FILE)
            if (!tmp.renameTo(dest)) { dest.writeText(o.toString()); tmp.delete() }
        }
    }

    fun mutate(ctx: Context, fn: (JSONObject) -> Unit): JSONObject {
        synchronized(lock) {
            val o = read(ctx)
            fn(o)
            write(ctx, o)
            return o
        }
    }

    fun arr(st: JSONObject, key: String): JSONArray {
        val a = st.optJSONArray(key)
        if (a != null) return a
        val n = JSONArray(); st.put(key, n); return n
    }

    fun obj(st: JSONObject, key: String): JSONObject {
        val o = st.optJSONObject(key)
        if (o != null) return o
        val n = JSONObject(); st.put(key, n); return n
    }

    fun settings(st: JSONObject): JSONObject = st.optJSONObject("settings") ?: JSONObject()

    /** optString that treats JSON null as empty. */
    fun str(o: JSONObject?, key: String): String =
        if (o == null || !o.has(key) || o.isNull(key)) "" else o.optString(key, "")

    fun findTask(st: JSONObject, id: String?): JSONObject? {
        if (id.isNullOrEmpty()) return null
        val a = st.optJSONArray("tasks") ?: return null
        for (i in 0 until a.length()) {
            val t = a.optJSONObject(i) ?: continue
            if (str(t, "id") == id) return t
        }
        return null
    }

    fun uid(): String = java.lang.Long.toString(System.currentTimeMillis(), 36) +
        java.lang.Long.toString((Math.random() * 1e8).toLong(), 36)

    // Small key/value store for things the UI only displays (next alarm time).
    fun prefs(ctx: Context) = ctx.getSharedPreferences("tr_meta", Context.MODE_PRIVATE)
}

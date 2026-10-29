package org.godotengine.editor

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Public upstream release metadata only; no account, auth cookies or assistant keys. */
object AIZivaUpdates {
    private val executor = Executors.newSingleThreadExecutor()
    private val checking = AtomicBoolean(false)
    private fun file(context: Context) = File(AIZivaRuntime.directory(context), "updates.json")
    fun status(context: Context): JSONObject {
        val state = AILinuxRuntimeFiles.readJson(file(context))
        val release = state.optJSONObject("release")
        val current = AIZivaPackage.activeRelease(AILinuxRuntime.core(context).root).version
        state.put("checking", checking.get()).put("available", release != null && newer(release.optString("version"), current))
        if (checking.get()) state.put("message", "Verific versiunea oficială Ziva…")
        else if (release != null && !state.optBoolean("available")) state.put("message", "$current · versiunea oficială este la zi")
        return state
    }
    fun newer(candidate: String, current: String): Boolean {
        fun parts(value: String) = value.removePrefix("v").split('.').map { it.toIntOrNull() ?: -1 }
        val a = parts(candidate); val b = parts(current)
        if (a.size != 3 || b.size != 3 || a.any { it < 0 } || b.any { it < 0 }) return false
        for (i in 0..2) if (a[i] != b[i]) return a[i] > b[i]
        return false
    }
    fun release(metadata: JSONObject): AIZivaPackage.Release {
        check(!metadata.optBoolean("draft") && !metadata.optBoolean("prerelease")) { "Versiune Ziva nestabilă." }
        val version = metadata.getString("tag_name")
        val name = "ziva-ai-agent-$version-godot-v4.2.0-linux-arm64.zip"
        val assets = metadata.getJSONArray("assets")
        val matches = (0 until assets.length()).map { assets.getJSONObject(it) }.filter { it.optString("name") == name }
        check(matches.size == 1) { "Versiunea oficială nu are un pachet Linux ARM64 compatibil." }
        val asset = matches.single()
        val digest = asset.getString("digest")
        check(digest.startsWith("sha256:")) { "Versiunea oficială nu publică SHA-256." }
        return AIZivaPackage.fromJson(JSONObject().put("version", version).put("url", asset.getString("browser_download_url"))
            .put("archive_size", asset.getLong("size")).put("archive_hash", digest.removePrefix("sha256:")))
    }
    fun available(context: Context): JSONObject {
        val state = status(context)
        check(state.optBoolean("available")) { "Nu există o actualizare Ziva verificată." }
        return releaseFromCache(state.getJSONObject("release"))
    }
    private fun releaseFromCache(value: JSONObject) = AIZivaPackage.fromJson(value).json()
    fun check(context: Context) {
        if (!checking.compareAndSet(false, true)) return
        val app = context.applicationContext
        executor.execute {
            val state = JSONObject().put("checked_at", System.currentTimeMillis())
            try {
                val connection = URL("https://api.github.com/repos/ziva-sh/ziva-agent-plugin-godot/releases/latest").openConnection() as HttpURLConnection
                val text = try {
                    connection.connectTimeout = 10000; connection.readTimeout = 10000; connection.instanceFollowRedirects = false
                    connection.setRequestProperty("Accept", "application/vnd.github+json")
                    connection.setRequestProperty("User-Agent", "Godot-AI-Ziva")
                    check(connection.responseCode == 200) { "Verificarea Ziva a răspuns HTTP ${connection.responseCode}." }
                    connection.inputStream.use { input ->
                        val bytes = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer); if (count < 0) break
                            check(bytes.size() + count <= 1_048_576) { "Metadate Ziva prea mari." }
                            bytes.write(buffer, 0, count)
                        }
                        bytes.toString("UTF-8")
                    }
                } finally { connection.disconnect() }
                val release = release(JSONObject(text))
                state.put("release", release.json()).put("message", "Versiune oficială disponibilă: ${release.version}")
            } catch (error: Exception) { state.put("message", error.message?.take(240) ?: "Nu pot verifica actualizările Ziva.") }
            finally {
                try { AILinuxRuntimeFiles.writeJson(file(app), state) } finally { checking.set(false) }
            }
        }
    }
}

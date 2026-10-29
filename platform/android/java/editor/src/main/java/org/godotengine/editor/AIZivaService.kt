package org.godotengine.editor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.nio.file.Files
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Runs the official addon in its own headless Godot Linux editor, beside the Android editor. */
class AIZivaService : Service() {
    companion object {
        const val FIRST_PORT = 7012
        const val LAST_PORT = 7041
        const val READY_TIMEOUT_MS = 180_000L
        const val MAX_LOG = 131072
    }
    private val stopping = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor()
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private val lock = Any()
    private var state = JSONObject()
    @Volatile private var running = false
    @Volatile private var child: Process? = null
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("godot_ai_ziva", "Ziva", NotificationManager.IMPORTANCE_LOW))
        startForeground(7343, notification("Pregătesc Ziva…"))
    }
    private fun notification(message: String): Notification {
        val stop = PendingIntent.getService(this, 7343, Intent(this, AIZivaService::class.java).putExtra("cancel", true),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, "godot_ai_ziva").setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("Godot AI · Ziva").setContentText(message.take(120)).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Oprește Ziva", stop).build()).build()
    }
    private fun cancelled() = stopping.get() || AIZivaRuntime.cancelFile(this).exists()
    private fun update(status: String, message: String) = synchronized(lock) {
        state.put("status", status).put("message", message)
        AIZivaRuntime.save(this, state)
        getSystemService(NotificationManager::class.java).notify(7343, notification(message))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.getBooleanExtra("cancel", false) == true) {
            stopping.set(true)
            if (!running) stopSelf(startId)
            return START_NOT_STICKY
        }
        val action = intent?.getStringExtra("action")
        if (!BuildConfig.GODOT_AI_ZIVA || action !in listOf("ziva_install", "ziva_start")) {
            if (!running) stopSelf(startId)
            return START_NOT_STICKY
        }
        if (running) return START_NOT_STICKY
        running = true
        state = AIZivaRuntime.read(this)
        executor.execute { work(action!!, intent.getStringExtra("project_directory"), startId) }
        return START_NOT_STICKY
    }

    private fun work(action: String, projectPath: String?, startId: Int) {
        var finalStatus = "stopped"
        var finalMessage = "Ziva oprit"
        var logFile: File? = null
        val output = StringBuilder()
        val heartbeat = timer.scheduleAtFixedRate({ synchronized(lock) {
            try { AIZivaRuntime.save(this, state) } catch (_: Exception) { }
        } }, 0, 2, TimeUnit.SECONDS)
        try {
            synchronized(lock) { state.remove("ui_port"); AIZivaRuntime.save(this, state) }
            val runtime = AILinuxRuntime.core(this, ::cancelled)
            check(runtime.state().optBoolean("ready")) { "Runtime Linux indisponibil." }
            val ziva = AIZivaPackage(runtime.root)
            val godot = AIZivaGodot(runtime.root)
            if (action == "ziva_install") {
                val install = File(cacheDir, "ai-ziva")
                update("installing", "Descarc pluginul oficial Ziva…")
                val zivaValid = try { ziva.verify(); true } catch (_: Exception) { false }
                if (!zivaValid) ziva.install(install, ::cancelled) { update("installing", it) }
                ziva.verify()
                val godotValid = try { godot.verify(); true } catch (_: Exception) { false }
                if (!godotValid) godot.install(install, ::cancelled) { update("installing", it) }
                godot.verify()
                AIZivaDependencies(runtime.root, { command, seconds -> runtime.launch(command, null, seconds) }) {
                    update("installing", it)
                }.ensure()
                check(!cancelled()) { "Operație anulată." }
                val version = runtime.launch(listOf(ziva.guestBinary, "--version"), null, 30)
                check(version.getInt("exit_code") == 0 && version.getString("output").lineSequence().any { it.trim() == AIZivaPackage.RELEASE.version }) {
                    "Ziva s-a descărcat, dar executabilul nu a trecut verificarea."
                }
                val engine = runtime.launch(listOf(godot.guestBinary, "--version"), null, 30)
                check(engine.getInt("exit_code") == 0 && engine.getString("output").contains("4.7.2.stable")) {
                    "Godot s-a descărcat, dar executabilul nu a trecut verificarea."
                }
                finalStatus = "installed"
                finalMessage = "Ziva instalat · ${AIZivaPackage.RELEASE.version}"
            } else {
                ziva.verify()
                godot.verify()
                AIZivaDependencies(runtime.root, { command, seconds -> runtime.launch(command, null, seconds) }) {
                    update("starting", it)
                }.ensure()
                val project = File(projectPath ?: error("Proiect absent.")).canonicalFile
                check(File(project, "project.godot").isFile && !project.path.contains(':')) { "Proiect Godot invalid." }
                val projectId = AIZivaRuntime.projectId(project)
                val data = privateDirectory("projects/$projectId")
                check(identityPort() == 0) { "O altă sesiune Ziva răspunde deja. Oprește-o înainte de pornire." }
                synchronized(lock) { state.put("project_id", projectId) }
                update("starting", "Pornesc editorul oficial Godot…")
                val binds = listOf(
                    ziva.addon.absolutePath to "/workspace/addons/ziva_agent",
                    privateDirectory("projects/$projectId/local-share").absolutePath to "/root/.local/share",
                    privateDirectory("projects/$projectId/cache").absolutePath to "/root/.cache",
                    privateDirectory("projects/$projectId/config").absolutePath to "/root/.config",
                    privateDirectory("projects/$projectId/godot").absolutePath to "/workspace/.godot"
                )
                logFile = File(data, "godot.log")
                child = runtime.startProcess(
                    listOf(godot.guestBinary, "--headless", "--editor", "--path", "/workspace"), project,
                    mapOf("ZIVA_ENABLE_HEADLESS" to "1", "GODOT_SILENCE_ROOT_WARNING" to "1"), binds)
                val reader = drain(child!!, output, logFile)
                try {
                    val deadline = System.nanoTime() + READY_TIMEOUT_MS * 1_000_000L
                    var port = 0
                    var tools = false
                    while (!cancelled() && child!!.isAlive && System.nanoTime() < deadline) {
                        synchronized(output) {
                            check(!output.contains("Can't open GDExtension dynamic library") && !output.contains("Error loading extension:")) {
                                "Pluginul oficial Ziva nu s-a încărcat. Reia instalarea și verifică jurnalul sesiunii."
                            }
                        }
                        if (port == 0) port = identityPort()
                        if (port > 0 && !tools) tools = editorToolReady(port)
                        if (tools && uiReady(port)) break
                        Thread.sleep(500)
                    }
                    check(!cancelled()) { "Operație anulată." }
                    check(port > 0 && tools && child!!.isAlive && uiReady(port)) {
                        "Interfața Ziva nu a pornit în editorul separat. Verifică jurnalul privat al sesiunii."
                    }
                    synchronized(lock) { state.put("ui_port", port) }
                    update("running", "Editorul separat Ziva rulează · interfața este disponibilă")
                    var failures = 0
                    while (!cancelled() && !child!!.waitFor(2, TimeUnit.SECONDS)) {
                        failures = if (uiReady(port)) 0 else failures + 1
                        check(failures < 30) { "Interfața Ziva nu mai răspunde. Repornește sesiunea." }
                    }
                    if (!cancelled()) error("Editorul Ziva s-a oprit (cod ${child!!.exitValue()}).")
                } finally {
                    terminate()
                    reader.join(2000)
                }
                finalMessage = "Ziva oprit · istoricul propriu este păstrat"
            }
        } catch (error: Exception) {
            finalStatus = if (cancelled()) "stopped" else "error"
            finalMessage = if (cancelled()) "Ziva oprit" else (error.message?.take(240) ?: "Ziva nu a pornit.")
        } finally {
            terminate()
            try {
                val log = logFile
                if (log != null && output.isNotEmpty()) log.writeText(output.toString())
            } catch (_: Exception) { }
            heartbeat.cancel(false)
            // Publish an idle state only after cleanup. A quick Start after installation
            // must not be lost while this service is still completing the previous operation.
            Handler(Looper.getMainLooper()).post {
                AIZivaRuntime.cancelFile(this).delete()
                stopForeground(STOP_FOREGROUND_REMOVE)
                running = false
                synchronized(lock) {
                    state.remove("ui_port")
                    state.put("status", finalStatus).put("message", finalMessage)
                    AIZivaRuntime.save(this, state)
                }
                stopSelf(startId)
            }
        }
    }

    private fun privateDirectory(relative: String): File {
        var file = AIZivaRuntime.directory(this)
        for (part in relative.split('/')) {
            require(part.isNotEmpty() && part != "." && part != "..")
            file = File(file, part)
            check(!Files.isSymbolicLink(file.toPath())) { "Director Ziva privat nesigur." }
        }
        check(file.isDirectory || file.mkdirs()) { "Directorul privat Ziva nu poate fi creat." }
        return file
    }

    private fun drain(process: Process, output: StringBuilder, log: File?): Thread = Thread({
        var lastWrite = 0L
        try { process.inputStream.use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val read = input.read(buffer); if (read < 0) break
                synchronized(output) {
                    output.append(String(buffer, 0, read))
                    if (output.length > MAX_LOG) output.delete(0, output.length - MAX_LOG)
                    if (log != null && System.currentTimeMillis() - lastWrite > 1000) {
                        try { log.writeText(output.toString()); lastWrite = System.currentTimeMillis() } catch (_: Exception) { }
                    }
                }
            }
        } } catch (_: Exception) { }
    }, "ZivaEditorOutput").apply { isDaemon = true; start() }

    private fun post(port: Int, body: String): JSONObject? {
        val connection = URL("http://127.0.0.1:$port/api/mcp").openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 400; connection.readTimeout = 3000
            connection.instanceFollowRedirects = false
            connection.requestMethod = "POST"; connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json, text/event-stream")
            connection.outputStream.use { it.write(body.toByteArray()) }
            if (connection.responseCode != 200) return null
            val text = connection.inputStream.use { input ->
                val bytes = ByteArray(65536); var count = 0
                while (count < bytes.size) { val read = input.read(bytes, count, bytes.size - count); if (read < 0) break; count += read }
                String(bytes, 0, count)
            }
            val data = if (text.trimStart().startsWith("{")) text else text.lineSequence()
                .filter { it.startsWith("data:") }.map { it.removePrefix("data:").trimStart() }.joinToString("\n")
            if (data.isBlank()) null else JSONObject(data)
        } catch (_: Exception) { null } finally { connection.disconnect() }
    }

    /** Identifies the official endpoint; a random local HTTP server is not a Ziva editor. */
    private fun identity(port: Int): Boolean {
        val json = post(port, """{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"godot-ai-ziva","version":"1"}}}""") ?: return false
        val info = json.optJSONObject("result")?.optJSONObject("serverInfo") ?: return false
        return info.optString("name") == "ziva-godot" && info.optString("version") == AIZivaPackage.RELEASE.version
    }

    private fun identityPort(): Int {
        for (port in FIRST_PORT..LAST_PORT) { if (cancelled()) return 0; if (identity(port)) return port }
        return 0
    }

    /** A read-only editor tool call proves that the addon is running inside a real editor. */
    private fun editorToolReady(port: Int): Boolean {
        val json = post(port, """{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_project_info","arguments":{"reasoning":"Readiness check."}}}""") ?: return false
        val content = json.optJSONObject("result")?.optJSONArray("content") ?: return false
        return content.length() > 0 && content.optJSONObject(0)?.optString("text").orEmpty().isNotBlank()
    }

    private fun uiReady(port: Int): Boolean {
        val connection = URL("http://127.0.0.1:$port/").openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 400; connection.readTimeout = 1200
            connection.instanceFollowRedirects = false
            connection.responseCode == 200 && connection.contentType.orEmpty().startsWith("text/html")
        } catch (_: Exception) { false } finally { connection.disconnect() }
    }

    @Synchronized private fun terminate() {
        val process = child ?: return
        try {
            process.destroy()
            if (!process.waitFor(2, TimeUnit.SECONDS)) process.destroyForcibly()
        } catch (_: InterruptedException) {
            process.destroyForcibly()
            Thread.currentThread().interrupt()
        } finally { child = null }
    }
    override fun onTimeout(startId: Int, fgsType: Int) { stopping.set(true); terminate(); stopSelf(startId) }
    override fun onDestroy() { stopping.set(true); terminate(); executor.shutdownNow(); timer.shutdownNow(); super.onDestroy() }
}

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
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Keeps Ziva independent of the finite Linux command queue and our agent's lifecycle. */
class AIZivaService : Service() {
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
        executor.execute { work(action!!, intent.getStringExtra("project_directory"), intent.getIntExtra("editor_mcp_port", 0), intent.getStringExtra("editor_mcp_token"), startId) }
        return START_NOT_STICKY
    }

    private fun work(action: String, projectPath: String?, editorPort: Int, editorToken: String?, startId: Int) {
        var finalStatus = "stopped"
        var finalMessage = "Ziva oprit"
        var mcpConfig: AIZivaMcpConfig? = null
        val heartbeat = timer.scheduleAtFixedRate({ synchronized(lock) {
            try { AIZivaRuntime.save(this, state) } catch (_: Exception) { }
        } }, 0, 2, TimeUnit.SECONDS)
        try {
            val runtime = AILinuxRuntime.core(this, ::cancelled)
            check(runtime.state().optBoolean("ready")) { "Runtime Linux indisponibil." }
            val distribution = AIZivaPackage(runtime.root)
            if (action == "ziva_install") {
                update("installing", "Descarc Ziva…")
                val valid = try { distribution.verify(); true } catch (_: Exception) { false }
                if (!valid) distribution.install(File(cacheDir, "ai-ziva"), ::cancelled) { update("installing", it) }
                distribution.verify()
                check(!cancelled()) { "Operație anulată." }
                val version = runtime.launch(listOf(distribution.guestBinary, "--version"), null, 30)
                check(version.getInt("exit_code") == 0 && version.getString("output").lineSequence().any { it.trim() == AIZivaPackage.RELEASE.version }) {
                    "Ziva s-a descărcat, dar executabilul nu a trecut verificarea."
                }
                finalStatus = "installed"
                finalMessage = "Ziva instalat · ${AIZivaPackage.RELEASE.version}"
            } else {
                distribution.verify()
                val project = File(projectPath ?: error("Proiect absent.")).canonicalFile
                check(File(project, "project.godot").isFile && !project.path.contains(':')) { "Proiect Godot invalid." }
                // Never attach to another app's listener, or silently reuse another project's session.
                ServerSocket().use { socket -> socket.bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), 7012)) }
                val projectId = AIZivaRuntime.projectId(project)
                check(editorPort in 1024..65535 && editorToken?.matches(Regex("[a-f0-9]{64}")) == true) { "Conexiune MCP editor invalidă." }
                check(editorReady(editorPort, editorToken!!)) { "Editorul nu răspunde prin MCP. Revino în Godot AI și reia pornirea." }
                mcpConfig = AIZivaMcpConfig(project, File(AIZivaRuntime.directory(this), "projects/$projectId"))
                mcpConfig.prepare(editorPort)
                synchronized(lock) { state.put("project_id", projectId) }
                val relativeData = "var/lib/godot-ai-ziva/$projectId"
                var data = runtime.root
                for (part in relativeData.split('/')) {
                    data = File(data, part)
                    check(!java.nio.file.Files.isSymbolicLink(data.toPath())) { "Director Ziva nesigur." }
                }
                check(data.isDirectory || data.mkdirs())
                update("starting", "Pornesc interfața Ziva…")
                child = runtime.startProcess(listOf(distribution.guestBinary), project,
                    mapOf("ZIVA_DATA_PATH" to "/$relativeData", AIZivaMcpConfig.TOKEN_ENV to editorToken))
                // Drain stderr even when Bun prints a large error. Never copy account data to our journal.
                val reader = Thread({ try { child?.inputStream?.use { input ->
                    val buffer = ByteArray(8192)
                    while (input.read(buffer) >= 0) { }
                } } catch (_: Exception) { } }, "ZivaOutput").apply { isDaemon = true; start() }
                try {
                    val deadline = System.nanoTime() + 45_000_000_000L
                    var responsive = false
                    while (!cancelled() && child!!.isAlive && System.nanoTime() < deadline) {
                        if (probe() && webReady()) { responsive = true; break }
                        Thread.sleep(250)
                    }
                    check(!cancelled()) { "Operație anulată." }
                    check(responsive && child!!.isAlive) { "Interfața Ziva nu a pornit. Verifică compatibilitatea runtime-ului." }
                    update("running", "Server Ziva pornit · conexiune MCP disponibilă")
                    var failures = 0
                    while (!cancelled() && !child!!.waitFor(2, TimeUnit.SECONDS)) {
                        failures = if (webReady() && editorReady(editorPort, editorToken)) 0 else failures + 1
                        check(failures < 15) { "Ziva sau editorul nu mai răspunde. Revino în Godot AI și reia pornirea." }
                    }
                    if (!cancelled()) error("Procesul Ziva s-a oprit (cod ${child!!.exitValue()}).")
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
                if (mcpConfig?.restore() == false) finalMessage += " · Configurație MCP editată; originalul rămâne în recuperare."
            } catch (_: Exception) { finalMessage += " · Configurația MCP necesită recuperare la următoarea pornire." }
            heartbeat.cancel(false)
            // Publish an idle state only after cleanup. A quick Start after installation
            // must not be lost while this service is still completing the previous operation.
            Handler(Looper.getMainLooper()).post {
                AIZivaRuntime.cancelFile(this).delete()
                stopForeground(STOP_FOREGROUND_REMOVE)
                running = false
                synchronized(lock) {
                    state.put("status", finalStatus).put("message", finalMessage)
                    AIZivaRuntime.save(this, state)
                }
                stopSelf(startId)
            }
        }
    }

    private fun editorReady(port: Int, token: String): Boolean {
        val connection = URL("http://127.0.0.1:$port/mcp").openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 1000; connection.readTimeout = 2000
            connection.instanceFollowRedirects = false
            connection.setRequestProperty("Authorization", "Bearer $token")
            connection.responseCode == 405 // MCP GET is deliberately disabled; response proves editor loop is alive.
        } catch (_: Exception) { false } finally { connection.disconnect() }
    }

    /** Identifies the actual Ziva endpoint; a random HTTP 200 cannot establish readiness. */
    private fun probe(): Boolean {
        val connection = URL(AIZivaPackage.BASE_URL + "api/mcp").openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 800; connection.readTimeout = 800
            connection.instanceFollowRedirects = false
            connection.requestMethod = "POST"; connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json, text/event-stream")
            val body = """{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"godot-ai-ziva","version":"1"}}}"""
            connection.outputStream.use { it.write(body.toByteArray()) }
            if (connection.responseCode != 200) false else {
                val text = connection.inputStream.use { input ->
                    val bytes = ByteArray(32769); var count = 0
                    while (count < bytes.size) { val size = input.read(bytes, count, bytes.size - count); if (size < 0) break; count += size }
                    check(count <= 32768); String(bytes, 0, count)
                }
                val json = if (text.trimStart().startsWith("{")) text else
                    text.lineSequence().firstOrNull { it.startsWith("data: ") }?.removePrefix("data: ") ?: "{}"
                val info = JSONObject(json).optJSONObject("result")?.optJSONObject("serverInfo")
                info?.optString("name") == "ziva-godot" && info.optString("version") == AIZivaPackage.RELEASE.version
            }
        } catch (_: Exception) { false } finally { connection.disconnect() }
    }
    private fun webReady(): Boolean {
        val connection = URL(AIZivaPackage.BASE_URL).openConnection() as HttpURLConnection
        return try {
            connection.connectTimeout = 800; connection.readTimeout = 800
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

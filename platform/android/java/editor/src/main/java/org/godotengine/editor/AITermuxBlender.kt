package org.godotengine.editor

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.PermissionInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.provider.Settings
import android.util.Base64
import org.json.JSONObject
import java.lang.ref.WeakReference
import java.net.InetAddress
import java.net.ServerSocket
import java.net.SocketTimeoutException
import java.security.SecureRandom
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Editor-only, optional bridge. No arbitrary command/URL/path supplied by the model. */
object AITermuxBlender {
    private const val PACKAGE = "com.termux"
    private const val PERMISSION = "com.termux.permission.RUN_COMMAND"
    private const val SERVICE = "com.termux.app.RunCommandService"
    private const val SECRET = "integration_termux_blender"
    private var activity = WeakReference<Activity>(null)
    private val main = Handler(Looper.getMainLooper())
    private var bootstrapServer: ServerSocket? = null

    fun initialize(value: Activity) { activity = WeakReference(value) }

    private fun preferences(context: Context) = context.getSharedPreferences("ai_termux_blender", Context.MODE_PRIVATE)

    private fun failure(message: String) = JSONObject().put("ok", false).put("error", message)

    private fun status(current: Activity): JSONObject {
        val result = JSONObject().put("ok", true).put("installed", false).put("permission", false)
            .put("supported", Build.SUPPORTED_ABIS.contains("arm64-v8a"))
        try {
            val info = current.packageManager.getPackageInfo(PACKAGE, PackageManager.GET_PERMISSIONS or PackageManager.GET_SERVICES)
            val permission = info.permissions?.firstOrNull { it.name == PERMISSION }
            val service = info.services?.firstOrNull { it.name == SERVICE }
            val protection = permission?.protectionLevel?.and(PermissionInfo.PROTECTION_MASK_BASE)
            val direct = service?.exported == true && service.enabled && service.permission == PERMISSION &&
                protection in listOf(PermissionInfo.PROTECTION_NORMAL, PermissionInfo.PROTECTION_DANGEROUS) &&
                (if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()) >= 118
            result.put("installed", true).put("version", info.versionName)
                .put("permission_declared", permission != null).put("external_commands", direct)
                .put("launch_mode", if (direct) "direct" else "manual").put("compatible", true)
        } catch (_: PackageManager.NameNotFoundException) { }
        result.put("permission", current.checkSelfPermission(PERMISSION) == PackageManager.PERMISSION_GRANTED)
        result.put("launching", preferences(current).getLong("launch_started", 0L) > System.currentTimeMillis() - 180_000)
        result.put("error", preferences(current).getString("error", ""))
        return result
    }

    @JvmStatic @Synchronized fun command(action: String, payload: String): String {
        val current = activity.get() ?: return failure("Editorul Android nu este activ.").toString()
        val args = try { JSONObject(payload) } catch (_: Exception) { JSONObject() }
        return try {
            when (action) {
                "status" -> status(current)
                "connected" -> {
                    preferences(current).edit().putLong("launch_started", 0L).putString("error", "").apply()
                    JSONObject().put("ok", true)
                }
                "connection" -> {
                    val prefs = preferences(current)
                    var port = prefs.getInt("port", 0)
                    if (port == 0) {
                        port = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { it.localPort }
                        check(prefs.edit().putInt("port", port).commit())
                    }
                    var token = AISecretVault.read(SECRET)
                    if (token.isEmpty()) {
                        token = ByteArray(32).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it.toInt() and 255) }
                        check(AISecretVault.store(SECRET, token) == "ok")
                    }
                    JSONObject().put("ok", true).put("url", "http://127.0.0.1:$port").put("token", token)
                }
                "permission" -> {
                    if (!status(current).optBoolean("external_commands"))
                        return failure("Această versiune Termux nu oferă permisiunea RUN_COMMAND. Folosește Pornește în Termux.")
                            .put("code", "manual_start_required").toString()
                    main.post {
                        if (current.checkSelfPermission(PERMISSION) != PackageManager.PERMISSION_GRANTED)
                            current.requestPermissions(arrayOf(PERMISSION), 0x424c)
                    }
                    status(current)
                }
                "copy_bootstrap" -> {
                    val state = status(current)
                    if (!state.optBoolean("installed") || !state.optBoolean("supported"))
                        return failure("Configurarea necesită Termux instalat pe Android ARM64.").toString()
                    val script = bootstrap(current, args.optBoolean("install_python", true))
                    // The full worker stays inside Godot. A short one-use loopback URL avoids
                    // pasting tens of thousands of characters into the Play Store terminal.
                    val clip = ClipData.newPlainText("Godot Blender", serveBootstrap(script))
                    clip.description.extras = PersistableBundle().apply {
                        putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                    }
                    val clipboard = current.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    if (Looper.myLooper() == Looper.getMainLooper()) {
                        clipboard.setPrimaryClip(clip)
                    } else {
                        val copied = CountDownLatch(1)
                        var copyError: Exception? = null
                        main.post {
                            try { clipboard.setPrimaryClip(clip) }
                            catch (error: Exception) { copyError = error }
                            finally { copied.countDown() }
                        }
                        if (!copied.await(3, TimeUnit.SECONDS) || copyError != null)
                            return failure("Nu am putut copia comanda de conectare. Încearcă din nou.").toString()
                    }
                    JSONObject().put("ok", true).put("command_length", clip.getItemAt(0).text.length)
                }
                "settings", "open_termux", "install_termux" -> {
                    val intent = when (action) {
                        "settings" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${current.packageName}"))
                        "install_termux" -> Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$PACKAGE")).setPackage("com.android.vending")
                        else -> current.packageManager.getLaunchIntentForPackage(PACKAGE)
                    }
                    if (intent == null) failure("Termux nu este instalat.") else {
                        main.post { try { current.startActivity(intent) } catch (_: Exception) {
                            if (action == "install_termux") {
                                try { current.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$PACKAGE"))) }
                                catch (_: Exception) { preferences(current).edit().putString("error", "Nu pot deschide Play Store.").apply() }
                            } else preferences(current).edit().putString("error", "Nu pot deschide aplicația. Verifică instalarea Termux.").apply()
                        } }
                        JSONObject().put("ok", true)
                    }
                }
                "start" -> start(current, args.optBoolean("install_python", false))
                else -> failure("Operație Termux necunoscută.")
            }.toString()
        } catch (_: Exception) {
            failure("Conectorul Termux nu a putut porni. Verifică permisiunile și inițializarea Termux.").toString()
        }
    }

    private fun bootstrap(current: Activity, installPython: Boolean): String {
        val connection = JSONObject(command("connection", "{}"))
        check(connection.optBoolean("ok"))
        val port = Uri.parse(connection.getString("url")).port
        val token = connection.getString("token")
        check(port in 1024..65535 && token.matches(Regex("[a-f0-9]{64}")))
        val worker = current.assets.open("godot_ai/blender_worker.py").use { it.readBytes() }
        val encoded = Base64.encodeToString(worker, Base64.NO_WRAP)
        val script = current.assets.open("godot_ai/blender_bootstrap.sh").bufferedReader(Charsets.UTF_8).use { it.readText() }
            .replace("__GODOT_INSTALL_PYTHON__", installPython.toString())
            .replace("__GODOT_WORKER_BASE64__", encoded)
            .replace("__GODOT_PORT__", port.toString())
            .replace("__GODOT_TOKEN__", token)
        check(script.toByteArray().size < 120_000)
        return script
    }

    private fun serveBootstrap(script: String): String {
        bootstrapServer?.close()
        val server = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))
        server.soTimeout = 10 * 60 * 1000
        bootstrapServer = server
        val nonce = UUID.randomUUID().toString().replace("-", "")
        val body = script.toByteArray(Charsets.UTF_8)
        Thread({
            try {
                server.use { listener ->
                    listener.accept().use { client ->
                        client.soTimeout = 5000
                        val request = client.getInputStream().bufferedReader(Charsets.US_ASCII).readLine()
                        val valid = request == "GET /$nonce HTTP/1.1" || request == "GET /$nonce HTTP/1.0"
                        val output = client.getOutputStream()
                        if (valid) {
                            output.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: ${body.size}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".toByteArray(Charsets.US_ASCII))
                            output.write(body)
                        } else {
                            output.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray(Charsets.US_ASCII))
                        }
                        output.flush()
                    }
                }
            } catch (_: SocketTimeoutException) {
                server.close()
            } catch (_: Exception) {
                server.close()
            } finally {
                synchronized(this) { if (bootstrapServer === server) bootstrapServer = null }
            }
        }, "GodotBlenderBootstrap").apply { isDaemon = true; start() }
        // The one-time URL contains a random capability; never return it to Godot or a model.
        return "curl --fail --silent --show-error --noproxy 127.0.0.1 'http://127.0.0.1:${server.localPort}/$nonce' | bash"
    }

    private fun start(current: Activity, installPython: Boolean): JSONObject {
        val state = status(current)
        if (!state.optBoolean("supported")) return failure("Configurarea automată Blender necesită Android ARM64.")
        if (!state.optBoolean("installed")) return failure("Instalează și deschide Termux o dată.")
        if (!state.optBoolean("external_commands")) return failure("Această versiune Termux necesită pornire din terminal.").put("code", "manual_start_required")
        if (!state.optBoolean("permission")) return failure("Acordă permisiunea de rulare a comenzilor în Termux.")
        if (state.optBoolean("launching")) return JSONObject().put("ok", true).put("launching", true)
        val script = bootstrap(current, installPython)
        val nonce = UUID.randomUUID().toString()
        val prefs = preferences(current)
        check(prefs.edit().putString("nonce", nonce).putString("error", "").putLong("launch_started", System.currentTimeMillis()).commit())
        val resultIntent = Intent(current, AITermuxBlenderResult::class.java).apply {
            data = Uri.parse("godot-blender://result/$nonce")
        }
        val callback = PendingIntent.getBroadcast(current, nonce.hashCode(), resultIntent,
            PendingIntent.FLAG_ONE_SHOT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0))
        val intent = Intent("com.termux.RUN_COMMAND").apply {
            component = ComponentName(PACKAGE, SERVICE)
            putExtra("com.termux.RUN_COMMAND_PATH", "\$PREFIX/bin/bash")
            putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf("-s"))
            putExtra("com.termux.RUN_COMMAND_STDIN", script)
            putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            putExtra("com.termux.RUN_COMMAND_COMMAND_LABEL", "Godot · Blender")
            putExtra("com.termux.RUN_COMMAND_PENDING_INTENT", callback)
        }
        main.post {
            try { current.startService(intent) } catch (_: Exception) {
                callback.cancel()
                prefs.edit().putLong("launch_started", 0L).putString("error", "Termux a refuzat pornirea. Activează comenzile externe și verifică permisiunea Android.").apply()
            }
        }
        return JSONObject().put("ok", true).put("launching", true)
    }

    fun receive(context: Context, intent: Intent) {
        val prefs = preferences(context)
        if (intent.data?.lastPathSegment != prefs.getString("nonce", "")) return
        val bundle = intent.getBundleExtra("result") ?: return
        val message = listOf(bundle.getString("errmsg", ""), bundle.getString("stderr", ""), bundle.getString("stdout", ""))
            .filter { it.isNotBlank() }.joinToString("\n").takeLast(6000)
        val token = AISecretVault.read(SECRET)
        val safe = if (token.isEmpty()) message else message.replace(token, "[redacted]")
        prefs.edit().putLong("launch_started", 0L).putString("error", safe.ifBlank {
            if (bundle.getInt("exitCode", 0) == 0) "Conectorul Blender s-a închis." else "Pornirea Termux a eșuat. Verifică inițializarea și comenzile externe."
        }).apply()
    }
}

/** Explicit, unexported PendingIntent target; nonce is part of immutable intent data. */
class AITermuxBlenderResult : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        AISecretVault.initialize(context)
        AITermuxBlender.receive(context, intent)
    }
}

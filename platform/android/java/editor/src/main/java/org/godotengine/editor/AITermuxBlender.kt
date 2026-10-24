package org.godotengine.editor

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Base64
import org.json.JSONObject
import java.lang.ref.WeakReference
import java.net.InetAddress
import java.net.ServerSocket
import java.security.SecureRandom
import java.util.UUID

/** Editor-only, optional bridge. No arbitrary command/URL/path supplied by the model. */
object AITermuxBlender {
    private const val PACKAGE = "com.termux"
    private const val PERMISSION = "com.termux.permission.RUN_COMMAND"
    private const val SECRET = "integration_termux_blender"
    private var activity = WeakReference<Activity>(null)
    private val main = Handler(Looper.getMainLooper())

    fun initialize(value: Activity) { activity = WeakReference(value) }

    private fun preferences(context: Context) = context.getSharedPreferences("ai_termux_blender", Context.MODE_PRIVATE)

    private fun failure(message: String) = JSONObject().put("ok", false).put("error", message)

    private fun status(current: Activity): JSONObject {
        val result = JSONObject().put("ok", true).put("installed", false).put("permission", false)
            .put("supported", Build.SUPPORTED_ABIS.contains("arm64-v8a"))
        try {
            val info = current.packageManager.getPackageInfo(PACKAGE, 0)
            result.put("installed", true).put("version", info.versionName)
            result.put("compatible", (if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()) >= 118)
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
                    main.post {
                        if (current.checkSelfPermission(PERMISSION) != PackageManager.PERMISSION_GRANTED)
                            current.requestPermissions(arrayOf(PERMISSION), 0x424c)
                    }
                    status(current)
                }
                "settings", "open_termux", "install_termux" -> {
                    val intent = when (action) {
                        "settings" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${current.packageName}"))
                        "install_termux" -> Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/termux/termux-app/releases/latest"))
                        else -> current.packageManager.getLaunchIntentForPackage(PACKAGE)
                    }
                    if (intent == null) failure("Termux nu este instalat.") else {
                        main.post { try { current.startActivity(intent) } catch (_: Exception) {
                            preferences(current).edit().putString("error", "Nu pot deschide aplicația. Verifică instalarea Termux.").apply()
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

    private fun start(current: Activity, installPython: Boolean): JSONObject {
        val state = status(current)
        if (!state.optBoolean("supported")) return failure("Configurarea automată Blender necesită Android ARM64.")
        if (!state.optBoolean("installed")) return failure("Instalează și deschide Termux o dată.")
        if (!state.optBoolean("compatible")) return failure("Este necesar Termux 0.118 sau mai nou.")
        if (!state.optBoolean("permission")) return failure("Acordă permisiunea de rulare a comenzilor în Termux.")
        if (state.optBoolean("launching")) return JSONObject().put("ok", true).put("launching", true)
        val connection = JSONObject(command("connection", "{}"))
        if (!connection.optBoolean("ok")) return connection
        val port = Uri.parse(connection.getString("url")).port
        val token = connection.getString("token")
        val worker = current.assets.open("godot_ai/blender_worker.py").use { it.readBytes() }
        val encoded = Base64.encodeToString(worker, Base64.NO_WRAP)
        val packageStep = if (installPython) "pkg install -y python" else "printf '%s\\n' 'Python lipsește. Apasă Conectează în Integrări.' >&2; exit 42"
        // Only fixed commands, numeric port and hex token. User scripts are transferred over the authenticated bridge.
        val script = """
            set -eu
            umask 077
            if ! command -v python >/dev/null 2>&1; then
                $packageStep
            fi
            task_root="${'$'}HOME/.local/share/godot-ai/blender"
            mkdir -p "${'$'}task_root"
            printf '%s' '$encoded' | base64 -d > "${'$'}task_root/worker.py.tmp"
            mv "${'$'}task_root/worker.py.tmp" "${'$'}task_root/worker.py"
            exec python "${'$'}task_root/worker.py" --root "${'$'}task_root" --port $port <<'GODOT_BLENDER_TOKEN'
            $token
            GODOT_BLENDER_TOKEN
        """.trimIndent()
        check(script.toByteArray().size < 120_000)
        val nonce = UUID.randomUUID().toString()
        val prefs = preferences(current)
        check(prefs.edit().putString("nonce", nonce).putString("error", "").putLong("launch_started", System.currentTimeMillis()).commit())
        val resultIntent = Intent(current, AITermuxBlenderResult::class.java).apply {
            data = Uri.parse("godot-blender://result/$nonce")
        }
        val callback = PendingIntent.getBroadcast(current, nonce.hashCode(), resultIntent,
            PendingIntent.FLAG_ONE_SHOT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0))
        val intent = Intent("com.termux.RUN_COMMAND").apply {
            component = ComponentName(PACKAGE, "com.termux.app.RunCommandService")
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

package org.godotengine.editor

import android.app.Activity
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.Process
import org.json.JSONObject
import java.io.File
import java.lang.ref.WeakReference
import java.util.concurrent.TimeUnit

/** First embedded-runtime milestone: verify a packaged native PIE in a separate app process. */
object AIEmbeddedRuntime {
    private const val PREFS = "ai_embedded_runtime_probe"
    private const val PROBE = "libai_runtime_probe.so"
    private var activity = WeakReference<Activity>(null)

    fun initialize(value: Activity) { activity = WeakReference(value) }

    @JvmStatic fun command(action: String): String {
        val current = activity.get() ?: return JSONObject().put("ok", false).put("error", "Editorul Android nu este activ.").toString()
        val prefs = current.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val file = File(current.applicationInfo.nativeLibraryDir, PROBE)
        val result = JSONObject().put("ok", true)
            .put("supported", Build.SUPPORTED_ABIS.contains("arm64-v8a"))
            .put("packaged", file.isFile)
            .put("result", prefs.getString("result", ""))
            .put("error", prefs.getString("error", ""))
            .put("pid", prefs.getInt("pid", 0))
        if (action == "embedded_status") return result.toString()
        if (action != "embedded_probe") return JSONObject().put("ok", false).put("error", "Operație necunoscută.").toString()
        if (!file.isFile || !Build.SUPPORTED_ABIS.contains("arm64-v8a")) {
            return JSONObject().put("ok", false).put("error", "Proba nativă ARM64 lipsește din instalare.").toString()
        }
        prefs.edit().putString("result", "").putString("error", "").putInt("pid", 0).apply()
        return try {
            current.startService(Intent(current, AIEmbeddedRuntimeService::class.java))
            result.put("started", true).toString()
        } catch (error: Exception) {
            JSONObject().put("ok", false).put("error", "Procesul separat nu a pornit: ${error.javaClass.simpleName}").toString()
        }
    }

    fun receive(context: Context, intent: Intent) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("result", intent.getStringExtra("result") ?: "")
            .putString("error", intent.getStringExtra("error") ?: "")
            .putInt("pid", intent.getIntExtra("pid", 0)).apply()
    }
}

/** Android creates this service under :ai_runtime; it never accepts outside intents. */
class AIEmbeddedRuntimeService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Thread({
            var output = ""
            var error = ""
            var child: java.lang.Process? = null
            try {
                val executable = File(applicationInfo.nativeLibraryDir, "libai_runtime_probe.so")
                check(executable.isFile && executable.canExecute()) { "Executabilul ambalat nu este disponibil." }
                val running = ProcessBuilder(executable.absolutePath).redirectErrorStream(true).start()
                child = running
                if (!running.waitFor(8, TimeUnit.SECONDS)) {
                    running.destroyForcibly()
                    error = "Proba nativă a depășit limita de 8 secunde."
                } else {
                    output = running.inputStream.bufferedReader().use { it.readText().take(256) }.trim()
                    if (running.exitValue() != 0 || !output.startsWith("AI_RUNTIME_PROBE_V1 ")) {
                        error = "Proba nativă a eșuat (cod ${running.exitValue()})."
                        output = ""
                    }
                }
            } catch (failure: Exception) {
                error = "Proba nativă nu a pornit: ${failure.javaClass.simpleName}"
            } finally {
                child?.destroy()
                sendBroadcast(Intent(this, AIEmbeddedRuntimeResult::class.java).apply {
                    putExtra("result", output)
                    putExtra("error", error)
                    putExtra("pid", Process.myPid())
                })
                stopSelf(startId)
            }
        }, "AIEmbeddedRuntimeProbe").start()
        return START_NOT_STICKY
    }
}

class AIEmbeddedRuntimeResult : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        AIEmbeddedRuntime.receive(context, intent)
    }
}

package org.godotengine.editor

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import org.json.JSONObject
import java.lang.ref.WeakReference
import java.util.concurrent.ConcurrentLinkedQueue

/** UI-thread speech service; Godot polls results on its own thread. */
object AIVoice {
    private const val PERMISSION = 0x4149
    private var activity = WeakReference<Activity>(null)
    private var recognizer: SpeechRecognizer? = null
    private val main = Handler(Looper.getMainLooper())
    private val events = ConcurrentLinkedQueue<String>()
    private var pending: JSONObject? = null
    private var generation = 0

    fun initialize(value: Activity) { activity = WeakReference(value) }

    @JvmStatic fun command(action: String, payload: String): String {
        val current = activity.get() ?: return JSONObject().put("error", "Editorul Android nu este activ.").toString()
        if (action == "poll") return events.poll() ?: "{}"
        val args = try { JSONObject(payload) } catch (_: Exception) { JSONObject() }
        val granted = current.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        if (action == "permission") {
            if (!granted) main.post { current.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION) }
            return JSONObject().put("granted", granted).toString()
        }
        main.post {
            when (action) {
                "start" -> {
                    events.clear()
                    if (!granted) {
                        pending = args
                        current.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION)
                    } else begin(current, args)
                }
                "stop" -> recognizer?.stopListening()
                "cancel" -> close()
            }
        }
        return "{}"
    }

    fun permissionResult(code: Int, grants: IntArray): Boolean {
        if (code != PERMISSION) return false
        val args = pending
        pending = null
        if (grants.isNotEmpty() && grants[0] == PackageManager.PERMISSION_GRANTED) {
            if (args != null) activity.get()?.let { begin(it, args) }
        } else events.add(JSONObject().put("error", "Accesul la microfon a fost refuzat.").toString())
        return true
    }

    fun close() {
        generation++
        pending = null
        recognizer?.cancel()
        recognizer?.destroy()
        recognizer = null
    }

    private fun begin(current: Activity, args: JSONObject) {
        close()
        val session = generation
        try {
            val local = Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(current)
            if (!local && !SpeechRecognizer.isRecognitionAvailable(current)) {
                events.add(JSONObject().put("error", "Nu există serviciu de dictare. Configurează un endpoint în Setări → Voce.").toString())
                return
            }
            recognizer = if (local) SpeechRecognizer.createOnDeviceSpeechRecognizer(current) else SpeechRecognizer.createSpeechRecognizer(current)
            recognizer?.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onError(error: Int) {
                    if (session != generation) return
                    events.add(JSONObject().put("error", "Dictare Android: eroare $error. Verifică limba și serviciul de recunoaștere sau configurează endpointul.").toString())
                    close()
                }
                override fun onResults(results: Bundle?) {
                    if (session != generation) return
                    val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                    events.add(JSONObject().put("text", text).toString())
                    close()
                }
            })
            recognizer?.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, args.optString("language", "ro"))
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            })
            main.postDelayed({ if (session == generation) recognizer?.stopListening() }, 60000)
        } catch (_: Exception) {
            events.add(JSONObject().put("error", "Serviciul Android nu poate porni dictarea.").toString())
            close()
        }
    }
}

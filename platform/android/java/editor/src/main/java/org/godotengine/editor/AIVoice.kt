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
import android.util.Base64
import org.json.JSONObject
import java.lang.ref.WeakReference
import java.util.concurrent.ConcurrentLinkedQueue

/** Shared Android microphone lifecycle; Godot polls state, audio or final text. */
object AIVoice {
    private var activity = WeakReference<Activity>(null)
    private var recognizer: SpeechRecognizer? = null
    private var capture: AIVoiceCapture? = null
    private val main = Handler(Looper.getMainLooper())
    private val events = ConcurrentLinkedQueue<String>()
    private var generation = 0
    private var phase = "idle"
    @Volatile private var level = 0f
    @Volatile private var client = ""

    fun initialize(value: Activity) {
        if (activity.get() !== value) close()
        activity = WeakReference(value)
    }

    private fun event(value: JSONObject) { events.add(value.put("client", client).toString()) }
    private fun state(value: String) { phase = value; event(JSONObject().put("state", value)) }

    @JvmStatic fun command(action: String, payload: String): String {
        if (action == "poll") return events.poll() ?: JSONObject().put("level", level.toDouble()).put("client", client).toString()
        val current = activity.get() ?: return JSONObject().put("error", "Editorul Android nu este activ.").toString()
        val args = try { JSONObject(payload) } catch (_: Exception) { JSONObject() }
        if (action == "permission") {
            val granted = current.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
            if (!granted) AIMicrophonePermission.request(current, this) { ok -> event(JSONObject().put("permission", ok)) }
            return JSONObject().put("granted", granted).toString()
        }
        if (action !in setOf("start", "record_start", "stop", "record_stop", "cancel"))
            return JSONObject().put("error", "Comandă vocală necunoscută.").toString()
        main.post {
            if (activity.get() !== current) return@post
            if (action in setOf("stop", "record_stop", "cancel") && args.optString("client").isNotEmpty() &&
                args.optString("client") != client) return@post
            when (action) {
                "start", "record_start" -> {
                    close(false); events.clear()
                    client = args.optString("client")
                    val session = generation
                    state("permission")
                    AIMicrophonePermission.request(current, this) { granted ->
                        if (session != generation || activity.get() !== current) return@request
                        if (!granted) { event(JSONObject().put("error", "Accesul la microfon a fost refuzat. Verifică permisiunea Microfon în Setări Android.")); close(false) }
                        else {
                            state("starting")
                            if (action == "record_start") beginCapture(current, session)
                            else beginRecognition(current, args, session)
                            main.postDelayed({
                                if (session == generation && phase == "starting") {
                                    event(JSONObject().put("error", "Serviciul vocal nu a pornit microfonul. Încearcă din nou.")); close(false)
                                }
                            }, 10000)
                        }
                    }
                }
                "stop", "record_stop" -> finish()
                "cancel" -> close()
            }
        }
        return JSONObject().put("ok", true).toString()
    }

    fun close(notify: Boolean = true) {
        generation++
        AIMicrophonePermission.cancel(this)
        val active = phase != "idle"
        phase = "idle"; level = 0f
        capture?.stop(true); capture = null
        recognizer?.cancel(); recognizer?.destroy(); recognizer = null
        if (notify && active) event(JSONObject().put("cancelled", true))
    }

    fun pause(value: Activity) { if (activity.get() === value) close() }

    private fun finish() {
        if (phase in setOf("permission", "starting")) { close(); return }
        if (phase != "recording") return
        state("transcribing")
        if (capture != null) capture?.stop() else recognizer?.stopListening()
        val session = generation
        main.postDelayed({
            if (session == generation && phase == "transcribing") {
                event(JSONObject().put("error", "Serviciul de dictare nu a returnat un rezultat. Încearcă din nou.")); close(false)
            }
        }, 15000)
    }

    private fun recording(session: Int) {
        state("recording")
        main.postDelayed({ if (session == generation && phase == "recording") finish() }, 60000)
    }

    private fun beginCapture(current: Activity, session: Int) {
        try {
            check(!current.isFinishing && !current.isDestroyed)
            capture = AIVoiceCapture({ value -> if (session == generation) level = value }) { audio, error ->
                if (session != generation) return@AIVoiceCapture
                if (error != null || audio == null) event(JSONObject().put("error", error ?: "Nu am primit audio."))
                else event(JSONObject().put("audio_base64", Base64.encodeToString(audio, Base64.NO_WRAP)).put("media_type", "audio/wav"))
                close(false)
            }
            capture!!.start(); recording(session)
        } catch (_: Exception) {
            event(JSONObject().put("error", "Microfonul nu poate porni înregistrarea. Verifică permisiunea și dacă altă aplicație îl folosește.")); close(false)
        }
    }

    private fun beginRecognition(current: Activity, args: JSONObject, session: Int) {
        try {
            val local = Build.VERSION.SDK_INT >= 31 && SpeechRecognizer.isOnDeviceRecognitionAvailable(current)
            if (!local && !SpeechRecognizer.isRecognitionAvailable(current)) {
                event(JSONObject().put("error", "Nu există serviciu de dictare. Configurează un endpoint în Setări → Voce.")); close(false); return
            }
            recognizer = if (local) SpeechRecognizer.createOnDeviceSpeechRecognizer(current) else SpeechRecognizer.createSpeechRecognizer(current)
            recognizer!!.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) { if (session == generation) recording(session) }
                override fun onBeginningOfSpeech() { }
                override fun onRmsChanged(rmsdB: Float) { if (session == generation) level = ((rmsdB + 2f) / 12f).coerceIn(0f, 1f) }
                override fun onBufferReceived(buffer: ByteArray?) { }
                override fun onEndOfSpeech() { if (session == generation) { state("transcribing"); finishTimeout(session) } }
                override fun onEvent(eventType: Int, params: Bundle?) { }
                override fun onPartialResults(partialResults: Bundle?) { }
                override fun onError(error: Int) {
                    if (session != generation) return
                    val text = when (error) {
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Accesul la microfon a fost refuzat."
                        SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Nu am detectat vorbire. Apasă microfonul și încearcă din nou."
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Serviciul de dictare este ocupat. Încearcă din nou."
                        else -> "Dictarea Android a eșuat ($error). Verifică limba și serviciul sau configurează endpointul în Setări → Voce."
                    }
                    event(JSONObject().put("error", text)); close(false)
                }
                override fun onResults(results: Bundle?) {
                    if (session != generation) return
                    val text = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty()
                    event(if (text.isBlank()) JSONObject().put("error", "Nu am detectat vorbire.") else JSONObject().put("text", text))
                    close(false)
                }
            })
            recognizer!!.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, args.optString("language", "ro"))
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            })
        } catch (_: Exception) { event(JSONObject().put("error", "Serviciul Android nu poate porni dictarea.")); close(false) }
    }

    private fun finishTimeout(session: Int) {
        main.postDelayed({
            if (session == generation && phase == "transcribing") { event(JSONObject().put("error", "Dictarea nu a returnat text.")); close(false) }
        }, 15000)
    }
}

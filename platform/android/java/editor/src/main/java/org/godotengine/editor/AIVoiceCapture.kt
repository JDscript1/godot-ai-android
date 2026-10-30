package org.godotengine.editor

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.sqrt

internal object AIVoiceWav {
    const val RATE = 16000
    const val MAX_BYTES = RATE * 2 * 60
    fun encode(pcm: ByteArray): ByteArray {
        require(pcm.isNotEmpty() && pcm.size % 2 == 0 && pcm.size <= MAX_BYTES)
        return ByteBuffer.allocate(44 + pcm.size).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray()); putInt(36 + pcm.size); put("WAVEfmt ".toByteArray())
            putInt(16); putShort(1); putShort(1); putInt(RATE); putInt(RATE * 2)
            putShort(2); putShort(16); put("data".toByteArray()); putInt(pcm.size); put(pcm)
        }.array()
    }
}

/** Bounded, in-memory mono capture; never depends on Godot's startup audio input setting. */
internal class AIVoiceCapture(private val level: (Float) -> Unit, private val done: (ByteArray?, String?) -> Unit) {
    private val main = Handler(Looper.getMainLooper())
    private val running = AtomicBoolean(true)
    private val discarded = AtomicBoolean(false)
    @Volatile private var recorder: AudioRecord? = null

    fun start() {
        val minimum = AudioRecord.getMinBufferSize(AIVoiceWav.RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        check(minimum > 0) { "Dispozitivul nu acceptă înregistrare mono la 16 kHz." }
        val audio = AudioRecord.Builder().setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
            .setAudioFormat(AudioFormat.Builder().setSampleRate(AIVoiceWav.RATE).setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build()).setBufferSizeInBytes(maxOf(minimum, 4096)).build()
        if (audio.state != AudioRecord.STATE_INITIALIZED) { audio.release(); error("Microfonul nu poate fi inițializat.") }
        recorder = audio
        try { audio.startRecording() } catch (error: Exception) { recorder = null; audio.release(); throw error }
        if (audio.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            recorder = null; audio.release(); error("Microfonul nu a pornit înregistrarea.")
        }
        Thread({
            val pcm = ByteArrayOutputStream()
            val buffer = ByteArray(2048)
            var failure: String? = null
            var lastLevel = 0L
            try {
                while (running.get() && pcm.size() < AIVoiceWav.MAX_BYTES) {
                    val count = audio.read(buffer, 0, minOf(buffer.size, AIVoiceWav.MAX_BYTES - pcm.size()))
                    if (count <= 0) { if (running.get()) failure = "Microfonul nu mai furnizează audio ($count)."; break }
                    pcm.write(buffer, 0, count - count % 2)
                    val now = android.os.SystemClock.elapsedRealtime()
                    if (now - lastLevel >= 100) {
                        var sum = 0.0
                        for (index in 0 until count - 1 step 2) {
                            val sample = (((buffer[index].toInt() and 255) or (buffer[index + 1].toInt() shl 8)).toShort()).toDouble() / 32768
                            sum += sample * sample
                        }
                        val value = (sqrt(sum / maxOf(1, count / 2)) * 4).toFloat().coerceIn(0f, 1f)
                        main.post { if (!discarded.get()) level(value) }; lastLevel = now
                    }
                }
            } catch (_: Exception) { if (running.get()) failure = "Înregistrarea audio a eșuat." }
            finally {
                running.set(false)
                try { audio.stop() } catch (_: Exception) { }
                audio.release(); recorder = null
            }
            val bytes = pcm.toByteArray()
            main.post {
                if (!discarded.get()) {
                    if (failure != null || bytes.isEmpty()) done(null, failure ?: "Nu am primit audio de la microfon.")
                    else done(AIVoiceWav.encode(bytes), null)
                }
            }
        }, "Godot-AI-microphone").start()
    }

    fun stop(discard: Boolean = false) {
        if (discard) discarded.set(true)
        running.set(false)
        try { recorder?.stop() } catch (_: Exception) { }
    }
}

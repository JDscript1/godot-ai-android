import org.godotengine.editor.AIMicrophonePermission
import org.godotengine.editor.AIMicrophoneRequests
import org.godotengine.editor.AIVoiceWav
import java.nio.ByteBuffer
import java.nio.ByteOrder

fun main() {
    var checks = 0
    fun expect(value: Boolean) { check(value) { "check ${checks + 1}" }; checks++ }
    val pending = AIMicrophoneRequests()
    val results = mutableListOf<String>()
    expect(pending.add("ziva") { results += "ziva:$it" })
    expect(!pending.add("agent") { results += "agent:$it" })
    expect(pending.prompting && pending.hasPending)
    pending.cancel("ziva")
    expect(results == listOf("ziva:false") && pending.hasPending)
    pending.resolve(true)
    expect(results == listOf("ziva:false", "agent:true") && !pending.prompting && !pending.hasPending)
    pending.resolve(true)
    expect(results.size == 2)
    expect(pending.add("cancelled") { results += "cancelled:$it" })
    pending.cancel("cancelled")
    expect(pending.prompting && !pending.hasPending)
    expect(!pending.add("new") { results += "new:$it" })
    pending.resolve(false)
    expect(results.takeLast(2) == listOf("cancelled:false", "new:false"))
    pending.add("same") { results += "first:$it" }
    pending.add("same") { results += "second:$it" }
    pending.resolve(true)
    expect(results.takeLast(2) == listOf("first:false", "second:true"))
    expect(AIMicrophonePermission.localOrigin("http://127.0.0.1:7013/", 7013))
    for (url in listOf("https://127.0.0.1:7013/", "http://127.0.0.1:7014/", "http://127.0.0.1.evil:7013/",
        "http://user@127.0.0.1:7013/", "http://localhost:7013/", "file:///private", "not a URL"))
        expect(!AIMicrophonePermission.localOrigin(url, 7013))
    expect(!AIMicrophonePermission.localOrigin("http://127.0.0.1:0/", 0))
    val pcm = byteArrayOf(1, 2, 3, 4)
    val wav = AIVoiceWav.encode(pcm)
    val data = ByteBuffer.wrap(wav).order(ByteOrder.LITTLE_ENDIAN)
    expect(wav.size == 48 && String(wav.copyOfRange(0, 4)) == "RIFF")
    expect(data.getInt(4) == 40 && String(wav.copyOfRange(8, 16)) == "WAVEfmt ")
    expect(data.getShort(20).toInt() == 1 && data.getShort(22).toInt() == 1)
    expect(data.getInt(24) == 16000 && data.getInt(28) == 32000 && data.getShort(34).toInt() == 16)
    expect(String(wav.copyOfRange(36, 40)) == "data" && data.getInt(40) == 4 && wav.copyOfRange(44, 48).contentEquals(pcm))
    for (invalid in listOf(byteArrayOf(), byteArrayOf(1), ByteArray(AIVoiceWav.MAX_BYTES + 2))) {
        var refused = false
        try { AIVoiceWav.encode(invalid) } catch (_: IllegalArgumentException) { refused = true }
        expect(refused)
    }
    expect(AIVoiceWav.encode(ByteArray(AIVoiceWav.MAX_BYTES)).size == 1920044)
    println("Microphone permission lifecycle, origins and WAV: $checks checks, 0 failures")
}

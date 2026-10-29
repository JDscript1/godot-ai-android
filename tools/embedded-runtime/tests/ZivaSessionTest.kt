import org.godotengine.editor.AIZivaSession
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import java.nio.file.Files

fun main(args: Array<String>) {
    if (args.firstOrNull() == "hold") {
        AIZivaSession(File(args[1])).acquire()!!.use {
            println("LOCKED"); System.out.flush(); Thread.sleep(120_000)
        }
        return
    }
    val scratch = Files.createTempDirectory("ziva-session-").toFile()
    var checks = 0
    var child: Process? = null
    try {
        val session = AIZivaSession(scratch)
        File(scratch, "state.json").writeText("{\"status\":\"running\",\"heartbeat\":99999999999999,\"boot_id\":\"previous-boot\"}")
        check(!session.active()); checks++ // persisted future timestamps cannot own a session
        val lease = session.acquire()!!
        check(session.active() && session.acquire() == null); checks++
        lease.close(); check(!session.active()); checks++
        val java = File(System.getProperty("java.home"), "bin/java").path
        child = ProcessBuilder(java, "-cp", System.getProperty("java.class.path"), "ZivaSessionTestKt", "hold", scratch.path).redirectErrorStream(true).start()
        check(child.inputStream.bufferedReader().readLine() == "LOCKED"); checks++
        check(session.active() && session.acquire() == null); checks++
        child.destroyForcibly(); child.waitFor()
        check(!session.active()); checks++ // kernel releases ownership after process death
        check(File(scratch, "state.json").readText().contains("running")); checks++
        val start = AIZivaSession.processStart(ProcessHandle.current().pid().toInt())
        check(start.isNotEmpty() && AIZivaSession.processStart(Int.MAX_VALUE).isEmpty()); checks++
        val share = File(scratch, "local-share/nested").apply { mkdirs() }
        File(share, "sidecar-42-valid.port").writeText("7017\n")
        File(share, "sidecar-142-foreign.port").writeText("7018")
        File(share, "sidecar-42-low.port").writeText("80")
        File(share, "sidecar-42-invalid.port").writeText("65536")
        File(share, "sidecar-42-long.port").writeText("7".repeat(100))
        File(share, "sidecar-42-json.port").writeText("{}")
        check(AIZivaSession.ownedPorts(share.parentFile, 42) == listOf(7017)); checks++
        val outside = File(scratch, "keep").apply { writeText("KEEP") }
        File(scratch, "session.lock").delete()
        Files.createSymbolicLink(File(scratch, "session.lock").toPath(), outside.toPath())
        var rejected = false
        try { session.acquire() } catch (_: IllegalStateException) { rejected = true }
        check(rejected && outside.readText() == "KEEP"); checks++
        val nonce = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        fun proof(text: String, error: Boolean = false) = JSONObject().put("result", JSONObject()
            .put("isError", error).put("content", JSONArray().put(JSONObject().put("type", "text").put("text", text))))
        check(AIZivaSession.ownerMatches(proof("1: GODOT_AI_ZIVA_OWNER=$nonce"), nonce)); checks++
        check(!AIZivaSession.ownerMatches(proof("1: GODOT_AI_ZIVA_OWNER=foreign-session"), nonce)); checks++
        check(!AIZivaSession.ownerMatches(proof("1: GODOT_AI_ZIVA_OWNER=$nonce", true), nonce)); checks++
        check(!AIZivaSession.ownerMatches(proof("1: prefix GODOT_AI_ZIVA_OWNER=$nonce suffix"), nonce)); checks++
        check(!AIZivaSession.ownerMatches(null, nonce)); checks++
        check(!AIZivaSession.ownerMatches(proof("1: GODOT_AI_ZIVA_OWNER=anything"), "anything")); checks++
        val terrainFailure = """
            ERROR: Can't open dynamic library, file not found: '/workspace/addons/terrain_3d/bin/libterrain.linux.debug.arm64.so'.
               at: open_dynamic_library (drivers/unix/os_unix.cpp:1063)
            ERROR: GDExtension dynamic library not found: 'res://addons/terrain_3d/terrain.gdextension'.
            ERROR: Error loading extension: 'res://addons/terrain_3d/terrain.gdextension'.
            Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org
        """.trimIndent()
        check(!AIZivaSession.officialExtensionFailed(terrainFailure)); checks++
        check(!AIZivaSession.officialExtensionFailed(terrainFailure + "\nZiva ready at res://addons/ziva_agent/")); checks++
        check(AIZivaSession.officialExtensionFailed("ERROR: Error loading extension: 'res://addons/ziva_agent/ziva_agent.gdextension'.")); checks++
        check(AIZivaSession.officialExtensionFailed("ERROR: Can't open GDExtension dynamic library: /workspace/addons/ziva_agent/bin/linux_arm64/libziva_agent.so")); checks++
        check(AIZivaSession.officialExtensionFailed("ERROR: Can't open dynamic library, file not found: '/opt/godot-tools/ziva/v3.3.2/addons/ziva_agent/bin/linux_arm64/libziva_agent.so'.")); checks++
        check(AIZivaSession.officialExtensionFailed(terrainFailure + "\nERROR: Error loading extension: 'res://addons/ziva_agent/ziva_agent.gdextension'.")); checks++
        check(!AIZivaSession.officialExtensionFailed("ERROR: Error loading extension: 'res://addons/ziva_agent_backup/other.gdextension'.")); checks++
        check(!AIZivaSession.officialExtensionFailed("")); checks++
        println("Ziva session lifecycle: $checks checks, 0 failures")
    } finally { child?.destroyForcibly(); scratch.deleteRecursively() }
}

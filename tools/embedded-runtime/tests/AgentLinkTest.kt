import org.godotengine.editor.AIZivaAgentLink
import org.json.JSONObject
import java.io.File
import java.nio.file.Files

fun main(args: Array<String>) {
    val scratch = Files.createTempDirectory("agent-link-").toFile()
    var checks = 0
    fun expect(value: Boolean) { check(value) { "Agent link check ${checks + 1}" }; checks++ }
    try {
        val root = File(scratch, "private-mailbox")
        val link = AIZivaAgentLink(root)
        val owner = "a".repeat(32)
        val id = "b".repeat(32)
        val client = File(args[0]).readText()
        expect(link.register(owner, client).getBoolean("ok"))
        expect(File(root, "client.gd").readText() == client)
        fun envelope(identity: String = owner) = JSONObject().put("id", id).put("owner", identity)
            .put("action", "status").put("arguments", JSONObject()).toString()
        val request = File(root, "requests/$id.json")
        request.writeText(envelope())
        expect(link.poll(owner).getJSONArray("requests").length() == 1)
        expect(!request.exists() && File(root, "requests/$id.processing").exists())
        expect(link.poll(owner).getJSONArray("requests").length() == 0)
        link.reply(owner, id, JSONObject().put("ok", true).put("result", JSONObject().put("busy", false)))
        expect(!File(root, "requests/$id.processing").exists())
        expect(JSONObject(File(root, "responses/$id.json").readText()).getString("owner") == owner)
        request.writeText(envelope())
        expect(link.poll(owner).getJSONArray("requests").length() == 0)
        request.writeText(envelope("c".repeat(32)))
        expect(link.poll(owner).getJSONArray("requests").length() == 0)
        request.writeText("x".repeat(65537))
        expect(link.poll(owner).getJSONArray("requests").length() == 0)
        val outside = File(scratch, "outside").apply { writeText("preserve") }
        Files.createSymbolicLink(request.toPath(), outside.toPath())
        expect(link.poll(owner).getJSONArray("requests").length() == 0 && outside.readText() == "preserve")
        request.delete()
        expect(runCatching { link.poll("c".repeat(32)) }.isFailure)
        link.close("c".repeat(32))
        expect(JSONObject(File(root, "connection.json").readText()).getBoolean("available"))
        link.close(owner)
        expect(!JSONObject(File(root, "connection.json").readText()).getBoolean("available"))
        val next = "d".repeat(32)
        link.register(next, client)
        expect(runCatching { link.poll(owner) }.isFailure)
        expect(link.poll(next).getBoolean("ok"))
        // Exercise the shipped Godot client against the real Kotlin mailbox in separate processes.
        val script = File(scratch, "probe.gd")
        script.writeText("extends SceneTree\nfunc _init():\n\tvar peer = load(" + JSONObject.quote(File(root, "client.gd").absolutePath) + ").new()\n\tpeer.directory = " + JSONObject.quote(root.absolutePath) + "\n\tprint(JSON.stringify(peer.request(\"status\")))\n\tquit()\n")
        val log = File(scratch, "client.log")
        val child = ProcessBuilder(args[1], "--headless", "--path", scratch.absolutePath, "--script", script.absolutePath)
            .redirectErrorStream(true).redirectOutput(log).start()
        val deadline = System.currentTimeMillis() + 20000
        var handled = 0
        while (child.isAlive && System.currentTimeMillis() < deadline) {
            val batch = link.poll(next).getJSONArray("requests")
            for (index in 0 until batch.length()) {
                val call = batch.getJSONObject(index)
                expect(call.getString("action") == "status")
                link.reply(next, call.getString("id"), JSONObject().put("ok", true)
                    .put("result", JSONObject().put("transport", "native-mailbox-fixture")))
                handled++
            }
            Thread.sleep(20)
        }
        if (child.isAlive) child.destroyForcibly()
        child.waitFor()
        val output = log.readText()
        expect(child.exitValue() == 0 && handled == 1 && "native-mailbox-fixture" in output && "SCRIPT ERROR" !in output)
        println("Agent link: $checks checks, 0 failures (including actual Godot client / Kotlin mailbox)")
        chatChecks()
    } finally { scratch.deleteRecursively() }
}

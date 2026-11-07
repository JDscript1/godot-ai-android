import org.godotengine.editor.AIZivaChat
import org.json.JSONArray
import org.json.JSONObject
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

fun chatChecks() {
    var checks = 0
    fun expect(value: Boolean) { check(value) { "Ziva chat check ${checks + 1}" }; checks++ }
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val snapshots = AtomicInteger(0)
    val aborts = AtomicInteger(0)
    val created = System.currentTimeMillis()
    var prompt = "Describe the scene"
    fun message(id: String, role: String, parent: String, text: String, tool: Boolean = false) = JSONObject()
        .put("info", JSONObject().put("id", id).put("role", role).put("parentId", parent)
            .put("finish", if (tool) "tool-calls" else "stop").put("time", JSONObject().put("created", created).put("completed", created + 1)))
        .put("parts", JSONArray().put(JSONObject().put("type", "text").put("text", text)).also { if (tool) it.put(JSONObject().put("type", "tool")) })
    fun messages() = JSONArray().put(message("old-user", "user", "", prompt))
        .put(message("old-answer", "assistant", "old-user", "Old answer"))
        .put(message("user", "user", "", prompt))
        .put(message("tool-answer", "assistant", "user", "Inspecting", true))
        .put(message("final-answer", "assistant", "tool-answer", "Final scene answer"))
        .put(message("other-answer", "assistant", "different-user", "Foreign answer"))
    val related = AIZivaChat.relatedTurns(messages(), created, prompt)
    expect(related.map { it.getJSONObject("info").getString("id") } == listOf("tool-answer", "final-answer"))
    val pool = Executors.newCachedThreadPool { runnable -> Thread(runnable).apply { isDaemon = true } }
    server.executor = pool
    server.createContext("/api/rpc/") { exchange ->
        val input = JSONObject(exchange.requestBody.bufferedReader().use { it.readText() }).getJSONObject("json")
        val output = when (exchange.requestURI.path.substringAfter("/api/rpc/")) {
            "plugin/bootstrap" -> JSONObject().put("sidebar", JSONObject().put("chats", JSONArray().put(JSONObject()
                .put("id", "link-test-chat").put("title", AIZivaChat.TITLE)
                .put("modelSelection", JSONObject().put("provider", "zivacode").put("modelId", "fixture")))))
            "chats/sendPrompt" -> { prompt = input.getJSONArray("parts").getJSONObject(0).getString("text"); JSONObject() }
            "chats/snapshot" -> {
                val count = snapshots.incrementAndGet()
                JSONObject().put("chat", JSONObject().put("status", JSONObject().put("type", if (count == 1) "busy" else "idle")))
                    .put("messages", if (count == 1) JSONArray().put(message("user", "user", "", prompt))
                        .put(message("tool-answer", "assistant", "user", "Inspecting", true)) else messages())
            }
            "chats/abort" -> { aborts.incrementAndGet(); JSONObject() }
            else -> error("Unexpected RPC route")
        }
        val body = JSONObject().put("json", output).toString().toByteArray()
        exchange.responseHeaders.add("Content-Type", "application/json")
        exchange.sendResponseHeaders(200, body.size.toLong())
        exchange.responseBody.use { it.write(body) }
    }
    server.start()
    try {
        val started = AIZivaChat.send(server.address.port, prompt, "", 30, "project-a")
        expect(started.getBoolean("ok"))
        expect(AIZivaChat.send(server.address.port, "overlap", "", 30).optString("code") == "ziva_busy")
        val id = started.getString("job_id")
        val deadline = System.currentTimeMillis() + 12000
        var observedBusy = false
        var result = AIZivaChat.poll(id)
        while (System.currentTimeMillis() < deadline && result.optString("state") == "running") {
            if (snapshots.get() == 1) observedBusy = true
            Thread.sleep(40)
            result = AIZivaChat.poll(id)
        }
        expect(observedBusy && snapshots.get() >= 2)
        expect(result.optString("state") == "completed" && result.optString("answer") == "Final scene answer")
        expect(result.optInt("tools") == 1 && result.optString("message_id") == "final-answer")
        expect(AIZivaChat.poll(id, "project-b").optString("code") == "ziva_other_project")
        expect(AIZivaChat.cancel(id, "project-b").optString("code") == "ziva_other_project")
        expect(AIZivaChat.cancel(id, "project-a").optString("state") == "completed")
        Thread.sleep(100)
        expect(aborts.get() == 0)
        println("Ziva chat link: $checks checks, 0 failures (local RPC fixture; no live provider)")
    } finally { server.stop(0); pool.shutdownNow() }
}

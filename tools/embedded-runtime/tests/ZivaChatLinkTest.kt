import org.godotengine.editor.AIZivaChat
import org.json.JSONArray
import org.json.JSONObject
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

fun chatChecks() {
    var checks = 0
    fun expect(value: Boolean, label: String = "") { check(value) { "Ziva chat check ${checks + 1}: $label" }; checks++ }
    fun waitFor(label: String, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 8000
        while (!condition() && System.currentTimeMillis() < deadline) Thread.sleep(20)
        check(condition()) { "Timed out: $label" }
    }
    val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
    val snapshots = AtomicInteger(0)
    val sends = AtomicInteger(0)
    val aborts = AtomicInteger(0)
    val created = AtomicLong(System.currentTimeMillis())
    val scenario = AtomicReference("normal")
    val prompt = AtomicReference("Describe the scene")
    var entered = CountDownLatch(1)
    var release = CountDownLatch(1)
    fun message(id: String, role: String, parent: String, text: String, tool: Boolean = false, finish: String = "stop") = JSONObject()
        .put("info", JSONObject().put("id", id).put("role", role).put("parentId", parent)
            .put("finish", if (tool) "tool-calls" else finish).put("time", JSONObject().put("created", created.get()).put("completed", created.get() + 1)))
        .put("parts", JSONArray().put(JSONObject().put("type", "text").put("text", text)).also { if (tool) it.put(JSONObject().put("type", "tool")) })
    fun messages(): JSONArray {
        val user = message("user", "user", "", prompt.get())
        // Observed official payload: the extra context is a synthetic text part.
        user.getJSONArray("parts").put(JSONObject().put("type", "text").put("synthetic", true)
            .put("text", "<additional_context>active scene</additional_context>"))
        val mode = scenario.get()
        return JSONArray().put(message("old-user", "user", "", prompt.get()))
            .put(message("old-answer", "assistant", "old-user", "Old answer"))
            .put(user).put(message("tool-answer", "assistant", "user", "Inspecting", true))
            .put(message("final-answer", "assistant", "tool-answer", if (mode == "empty" || mode == "aborted") "" else "Final scene answer",
                finish = when (mode) { "aborted" -> "aborted"; "error" -> "error"; else -> "stop" }))
            .put(message("other-answer", "assistant", "different-user", "Foreign answer"))
    }
    val related = AIZivaChat.relatedTurns(messages(), created.get(), prompt.get())
    expect(related.map { it.getJSONObject("info").getString("id") } == listOf("tool-answer", "final-answer"), "Synthetic context preserves exact prompt correlation and excludes foreign turns")
    val pool = Executors.newCachedThreadPool { runnable -> Thread(runnable).apply { isDaemon = true } }
    server.executor = pool
    server.createContext("/api/rpc/") { exchange ->
        val input = JSONObject(exchange.requestBody.bufferedReader().use { it.readText() }).getJSONObject("json")
        val output = when (exchange.requestURI.path.substringAfter("/api/rpc/")) {
            "plugin/bootstrap" -> {
                if (scenario.get() == "resolving") { entered.countDown(); check(release.await(8, TimeUnit.SECONDS)) }
                JSONObject().put("sidebar", JSONObject().put("chats", JSONArray().put(JSONObject()
                    .put("id", "link-test-chat").put("title", "Renamed by Ziva").put("fallbackTitle", AIZivaChat.TITLE)
                    .put("modelSelection", JSONObject().put("provider", "zivacode").put("modelId", "fixture")))))
            }
            "chats/sendPrompt" -> {
                sends.incrementAndGet()
                prompt.set(input.getJSONArray("parts").getJSONObject(0).getString("text"))
                created.set(System.currentTimeMillis())
                snapshots.set(0)
                if (scenario.get() == "sending") { entered.countDown(); check(release.await(8, TimeUnit.SECONDS)) }
                JSONObject()
            }
            "chats/snapshot" -> {
                val count = snapshots.incrementAndGet()
                JSONObject().put("chat", JSONObject().put("status", JSONObject().put("type", if (count == 1) "busy" else "idle")))
                    .put("messages", if (count == 1) JSONArray().put(message("user", "user", "", prompt.get()))
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
    fun awaitJob(id: String): JSONObject {
        var result = AIZivaChat.poll(id)
        waitFor("terminal job") { result = AIZivaChat.poll(id); result.optString("state") != "running" }
        return result
    }
    fun start(mode: String): String {
        scenario.set(mode)
        return AIZivaChat.send(server.address.port, "Describe the scene: $mode", "", 30, "project-a").getString("job_id")
    }
    try {
        val started = AIZivaChat.send(server.address.port, prompt.get(), "", 30, "project-a")
        expect(started.getBoolean("ok"))
        expect(AIZivaChat.send(server.address.port, "overlap", "", 30).optString("code") == "ziva_busy")
        val id = started.getString("job_id")
        waitFor("busy snapshot") { snapshots.get() == 1 }
        val result = awaitJob(id)
        expect(snapshots.get() >= 2)
        expect(result.optString("state") == "completed" && result.optString("answer") == "Final scene answer")
        expect(result.optInt("tools") == 1 && result.optString("message_id") == "final-answer")
        expect(AIZivaChat.poll(id, "project-b").optString("code") == "ziva_other_project")
        expect(AIZivaChat.cancel(id, "project-b").optString("code") == "ziva_other_project")
        expect(AIZivaChat.cancel(id, "project-a").optString("state") == "completed")
        expect(aborts.get() == 0)

        val aborted = awaitJob(start("aborted"))
        expect(aborted.optString("state") == "cancelled" && aborted.optString("finish") == "aborted", "Official aborted result must never report completed")
        expect(aborted.optInt("tools") == 1 && aborted.optString("error").isNotBlank(), "Interrupted tool-only work keeps evidence and explains the interruption")
        val empty = awaitJob(start("empty"))
        expect(empty.optString("state") == "error" && empty.optString("answer").isBlank() && empty.optInt("tools") == 1, "An empty stop after tools cannot confirm success")
        val failure = awaitJob(start("error"))
        expect(failure.optString("state") == "error" && failure.optString("finish") == "error", "A finish error without info.error is still an error")

        val beforeResolveSends = sends.get()
        val beforeResolveAborts = aborts.get()
        entered = CountDownLatch(1); release = CountDownLatch(1)
        val resolving = start("resolving")
        expect(entered.await(5, TimeUnit.SECONDS), "Resolution entered")
        expect(AIZivaChat.cancel(resolving, "project-a").optString("state") == "cancelled")
        release.countDown()
        Thread.sleep(500)
        expect(sends.get() == beforeResolveSends && aborts.get() == beforeResolveAborts, "Cancelling resolution neither submits nor aborts unrelated chat work")

        entered = CountDownLatch(1); release = CountDownLatch(1)
        val beforeSendAborts = aborts.get()
        val sending = start("sending")
        expect(entered.await(5, TimeUnit.SECONDS), "Send entered")
        expect(AIZivaChat.cancel(sending, "project-a").optString("state") == "cancelled")
        release.countDown()
        waitFor("abort after send response") { aborts.get() >= beforeSendAborts + 2 }
        expect(AIZivaChat.poll(sending).optString("state") == "cancelled" && snapshots.get() == 0, "Cancellation during send is repeated after submission and cannot become completed")
        println("Ziva chat link: $checks checks, 0 failures (local RPC fixture; no live provider)")
    } finally { release.countDown(); server.stop(0); pool.shutdownNow() }
}

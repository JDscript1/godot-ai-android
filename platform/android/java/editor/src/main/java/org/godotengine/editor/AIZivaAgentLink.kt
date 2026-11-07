package org.godotengine.editor

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.file.Files

/** Private per-project mailbox shared with Ziva; no public listener or project files. */
class AIZivaAgentLink(private val directory: File) {
    companion object {
        const val GUEST = "/run/godot-ai-agent-link"
        private val ID = Regex("[a-f0-9]{32}")
        private const val MAX_BYTES = 64 * 1024
    }

    private fun folder(name: String): File {
        check(!Files.isSymbolicLink(directory.toPath()))
        check(directory.isDirectory || directory.mkdirs())
        val path = File(directory, name)
        check(!Files.isSymbolicLink(path.toPath()))
        check(path.isDirectory || path.mkdirs())
        return path
    }

    private fun read(file: File): JSONObject {
        check(!Files.isSymbolicLink(file.toPath()) && file.isFile && file.length() <= MAX_BYTES)
        return JSONObject(file.readText())
    }

    private fun write(file: File, text: String) {
        check(!Files.isSymbolicLink(file.toPath()) && text.toByteArray().size <= MAX_BYTES)
        val temporary = File.createTempFile(".agent-", ".tmp", file.parentFile)
        try {
            temporary.outputStream().use { it.write(text.toByteArray()); it.fd.sync() }
            check(temporary.renameTo(file))
        } finally { temporary.delete() }
    }

    private fun owns(owner: String): Boolean = ID.matches(owner) && try {
        read(File(directory, "connection.json")).optString("owner") == owner
    } catch (_: Exception) { false }

    fun register(owner: String, client: String): JSONObject {
        require(ID.matches(owner))
        folder("requests"); folder("responses")
        write(File(directory, "client.gd"), client)
        write(File(directory, "connection.json"), JSONObject().put("schema", 1)
            .put("owner", owner).put("available", true).toString())
        prune()
        return JSONObject().put("ok", true)
    }

    fun poll(owner: String): JSONObject {
        check(owns(owner)) { "Legătura aparține altei sesiuni Godot AI." }
        val requests = JSONArray()
        for (file in folder("requests").listFiles().orEmpty().sortedBy { it.name }) {
            if (requests.length() >= 8) break
            val id = file.name.removeSuffix(".json")
            if (!file.name.endsWith(".json") || !ID.matches(id) || Files.isSymbolicLink(file.toPath())) continue
            val claimed = File(file.parentFile, "$id.processing")
            if (!file.renameTo(claimed)) continue
            try {
                val request = read(claimed)
                // A repeated envelope never repeats an already acknowledged operation.
                if (request.optString("owner") != owner || request.optString("id") != id ||
                    File(folder("responses"), "$id.json").exists()) { claimed.delete(); continue }
                requests.put(request)
            } catch (_: Exception) { claimed.delete() }
        }
        return JSONObject().put("ok", true).put("requests", requests)
    }

    fun reply(owner: String, id: String, result: JSONObject): JSONObject {
        check(owns(owner) && ID.matches(id))
        write(File(folder("responses"), "$id.json"), JSONObject().put("id", id).put("owner", owner).put("result", result).toString())
        File(folder("requests"), "$id.processing").delete()
        prune()
        return JSONObject().put("ok", true)
    }

    fun close(owner: String): JSONObject {
        if (owns(owner)) write(File(directory, "connection.json"), JSONObject().put("schema", 1)
            .put("owner", owner).put("available", false).toString())
        return JSONObject().put("ok", true)
    }

    private fun prune() {
        val cutoff = System.currentTimeMillis() - 30 * 60_000L
        for (name in listOf("requests", "responses")) {
            val files = folder(name).listFiles().orEmpty().filter {
                ID.matches(it.name.substringBefore('.')) && !Files.isSymbolicLink(it.toPath())
            }.sortedByDescending { it.lastModified() }
            files.forEachIndexed { index, file -> if (index >= 96 || file.lastModified() < cutoff) file.delete() }
        }
    }
}
